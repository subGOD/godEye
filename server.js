import express from 'express';
import cors from 'cors';
import jwt from 'jsonwebtoken';
import Redis from 'ioredis';
import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import fs from 'fs';
import bcrypt from 'bcrypt';
import { createLogger, format, transports } from 'winston';
import path from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Initialize config
config();

// Logging setup
const logDir = '/var/log/godeye';
!fs.existsSync(logDir) && fs.mkdirSync(logDir);

const logger = createLogger({
    format: format.combine(
        format.timestamp(),
        format.json()
    ),
    transports: [
        new transports.File({ 
            filename: path.join(logDir, 'error.log'), 
            level: 'error',
            maxsize: 5242880, // 5MB
            maxFiles: 5
        }),
        new transports.File({ 
            filename: path.join(logDir, 'combined.log'),
            maxsize: 5242880,
            maxFiles: 5
        })
    ]
});

if (process.env.NODE_ENV !== 'production') {
    logger.add(new transports.Console({
        format: format.combine(
            format.colorize(),
            format.simple()
        )
    }));
}

// App initialization
const app = express();
const port = process.env.PORT || 3001;
const SETUP_FILE = path.join(__dirname, '.setup_complete');

// Security configurations
const helmetConfig = {
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'", "'unsafe-inline'"],
            styleSrc: ["'self'", "'unsafe-inline'"],
            imgSrc: ["'self'", "data:", "blob:"],
            connectSrc: ["'self'"]
        }
    },
    crossOriginEmbedderPolicy: false,
    crossOriginResourcePolicy: { policy: "cross-origin" }
};

// Rate limiting configurations
const rateLimitConfig = {
    windowMs: 15 * 60 * 1000,
    max: (req) => {
        if (req.path === '/api/setup') return 3;
        if (req.path === '/api/login') return 5;
        return 100;
    },
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
        logger.warn('Rate limit exceeded', { ip: req.ip, path: req.path });
        res.status(429).json({
            error: 'Too many requests',
            message: 'Please try again later',
            retryAfter: res.getHeader('Retry-After')
        });
    }
};

// Middleware setup
app.use(helmet(helmetConfig));
app.use(rateLimit(rateLimitConfig));
app.use(cors({
    origin: process.env.NODE_ENV === 'production' 
        ? ['http://localhost:3000', 'http://localhost:1337'] 
        : '*',
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true,
    maxAge: 86400
}));
app.use(express.json({ limit: '1mb' }));

// Redis configuration
const redis = new Redis({
    port: 6379,
    host: '127.0.0.1',
    password: process.env.REDIS_PASSWORD,
    retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
    },
    maxRetriesPerRequest: 3
});

redis.on('error', (err) => {
    logger.error('Redis connection error:', err);
    if (err.code === 'ECONNREFUSED') {
        process.exit(1);
    }
});

redis.on('connect', () => {
    logger.info('Redis connection established');
});

// Utilities
const validatePassword = (password) => {
    const minLength = 8;
    const hasUpperCase = /[A-Z]/.test(password);
    const hasLowerCase = /[a-z]/.test(password);
    const hasNumbers = /\d/.test(password);
    const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password);

    const errors = [];
    if (password.length < minLength) errors.push('Password must be at least 8 characters long');
    if (!hasUpperCase) errors.push('Password must contain at least one uppercase letter');
    if (!hasLowerCase) errors.push('Password must contain at least one lowercase letter');
    if (!hasNumbers) errors.push('Password must contain at least one number');
    if (!hasSpecialChar) errors.push('Password must contain at least one special character');

    return {
        isValid: errors.length === 0,
        errors
    };
};

const isSetupComplete = () => {
    try {
        return fs.existsSync(SETUP_FILE);
    } catch (error) {
        logger.error('Error checking setup status:', error);
        return false;
    }
};

const completeSetup = () => {
    try {
        fs.writeFileSync(SETUP_FILE, new Date().toISOString());
        return true;
    } catch (error) {
        logger.error('Error writing setup file:', error);
        return false;
    }
};

// Authentication middleware
const authenticateToken = async (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        logger.warn('Authentication attempt without token', { ip: req.ip });
        return res.status(401).json({
            error: 'Authentication required',
            message: 'No token provided'
        });
    }

    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        const userSession = await redis.get(`session:${decoded.id}`);
        
        if (!userSession || userSession !== token) {
            logger.warn('Invalid session detected', { ip: req.ip, userId: decoded.id });
            return res.status(401).json({
                error: 'Invalid session',
                message: 'Session expired or invalid'
            });
        }

        req.user = decoded;
        next();
    } catch (err) {
        logger.error('Authentication error:', err);
        
        if (err instanceof jwt.TokenExpiredError) {
            return res.status(401).json({
                error: 'Token expired',
                message: 'Please log in again'
            });
        }
        
        return res.status(403).json({
            error: 'Invalid token',
            message: 'Authentication failed'
        });
    }
};

// Routes
app.post('/api/setup', async (req, res) => {
    try {
        if (isSetupComplete()) {
            logger.warn('Setup attempt after completion', { ip: req.ip });
            return res.status(403).json({
                error: 'Setup already completed',
                message: 'System is already configured'
            });
        }

        const { username, password } = req.body;

        if (!username || !password) {
            return res.status(400).json({
                error: 'Invalid setup data',
                message: 'Username and password are required'
            });
        }

        const passwordValidation = validatePassword(password);
        if (!passwordValidation.isValid) {
            return res.status(400).json({
                error: 'Invalid password',
                message: passwordValidation.errors
            });
        }

        const hashedPassword = await bcrypt.hash(password, 12);
        
        await redis.set('admin_credentials', JSON.stringify({
            username,
            password: hashedPassword
        }));

        if (!completeSetup()) {
            throw new Error('Failed to mark setup as complete');
        }

        const token = jwt.sign(
            { id: 1, username, role: 'admin' },
            process.env.JWT_SECRET,
            { expiresIn: '24h', algorithm: 'HS256' }
        );

        await redis.set(`session:1`, token, 'EX', 86400);

        logger.info('Initial setup completed', { username, ip: req.ip });
        
        res.json({
            success: true,
            message: 'Setup completed successfully',
            token,
            user: { id: 1, username, role: 'admin' }
        });
    } catch (error) {
        logger.error('Setup error:', error);
        res.status(500).json({
            error: 'Setup failed',
            message: 'Failed to complete setup'
        });
    }
});

app.post('/api/login', async (req, res) => {
    try {
        if (!isSetupComplete()) {
            return res.status(403).json({
                error: 'Setup required',
                message: 'Initial setup has not been completed'
            });
        }

        const { username, password } = req.body;
        
        if (!username || !password) {
            return res.status(400).json({
                error: 'Invalid credentials',
                message: 'Username and password are required'
            });
        }

        const storedCreds = await redis.get('admin_credentials');
        if (!storedCreds) {
            logger.error('Admin credentials not found in Redis');
            return res.status(500).json({
                error: 'Configuration error',
                message: 'Admin credentials not found'
            });
        }

        const adminCreds = JSON.parse(storedCreds);
        const passwordMatch = await bcrypt.compare(password, adminCreds.password);
        
        if (username !== adminCreds.username || !passwordMatch) {
            logger.warn('Failed login attempt', { username, ip: req.ip });
            return res.status(401).json({
                error: 'Invalid credentials',
                message: 'Invalid username or password'
            });
        }

        const token = jwt.sign(
            { id: 1, username, role: 'admin' },
            process.env.JWT_SECRET,
            { expiresIn: '24h', algorithm: 'HS256' }
        );

        await redis.set(`session:1`, token, 'EX', 86400);

        logger.info('Successful login', { username, ip: req.ip });

        res.json({
            token,
            user: { id: 1, username, role: 'admin' }
        });
    } catch (error) {
        logger.error('Login error:', error);
        res.status(500).json({
            error: 'Server error',
            message: 'An unexpected error occurred'
        });
    }
});

app.get('/api/setup/status', (req, res) => {
    res.json({
        isSetupComplete: isSetupComplete()
    });
});

app.post('/api/logout', authenticateToken, async (req, res) => {
    try {
        await redis.del(`session:${req.user.id}`);
        logger.info('User logged out', { userId: req.user.id, ip: req.ip });
        res.json({ success: true, message: 'Logged out successfully' });
    } catch (error) {
        logger.error('Logout error:', error);
        res.status(500).json({
            error: 'Server error',
            message: 'Failed to logout'
        });
    }
});

// Error handling
app.use((err, req, res, next) => {
    logger.error('Unhandled error:', err);
    res.status(500).json({
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'production' 
            ? 'An unexpected error occurred'
            : err.message
    });
});

// Server startup
const server = app.listen(port, () => {
    logger.info(`Server running on port ${port}`);
});

// Graceful shutdown handling
const shutdown = async (signal) => {
    logger.info(`Received ${signal}. Starting graceful shutdown...`);
    
    server.close(() => {
        logger.info('HTTP server closed');
    });

    try {
        await redis.quit();
        logger.info('Redis connection closed');
        process.exit(0);
    } catch (err) {
        logger.error('Error during shutdown:', err);
        process.exit(1);
    }
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('uncaughtException', (err) => {
    logger.error('Uncaught Exception:', err);
    shutdown('uncaughtException');
});
process.on('unhandledRejection', (reason, promise) => {
    logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
    shutdown('unhandledRejection');
});

export default app;