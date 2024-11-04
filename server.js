import express from 'express';
import cors from 'cors';
import jwt from 'jsonwebtoken';
import Redis from 'ioredis';
import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';

// Initialize dirname for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load environment variables
config();

// Validate required environment variables
const requiredEnvVars = [
    'VITE_ADMIN_USERNAME',
    'VITE_ADMIN_PASSWORD',
    'JWT_SECRET',
    'REDIS_PASSWORD'
];

const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar]);
if (missingEnvVars.length > 0) {
    console.error('Missing required environment variables:', missingEnvVars);
    process.exit(1);
}

// Initialize Express app
const app = express();
const port = process.env.PORT || 3001;

// Security middleware
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'", "'unsafe-inline'"],
            styleSrc: ["'self'", "'unsafe-inline'"],
            imgSrc: ["'self'", "data:", "blob:"],
            connectSrc: ["'self'"],
        },
    },
    crossOriginEmbedderPolicy: false,
    crossOriginResourcePolicy: { policy: "cross-origin" }
}));

// Rate limiting
const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // Limit each IP to 100 requests per windowMs
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
        res.status(429).json({
            error: 'Too many requests, please try again later.',
            retryAfter: res.getHeader('Retry-After')
        });
    }
});

// Apply rate limiter to all routes
app.use(limiter);

// CORS configuration
const corsOptions = {
    origin: process.env.NODE_ENV === 'production' ? 
        ['http://localhost:3000', 'http://localhost:1337'] : '*',
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true,
    maxAge: 86400 // 24 hours
};

app.use(cors(corsOptions));
app.use(express.json({ limit: '1mb' }));

// Redis configuration
const redisClient = new Redis({
    port: 6379,
    host: '127.0.0.1',
    password: process.env.REDIS_PASSWORD,
    retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
    },
    maxRetriesPerRequest: 3
});

// Redis error handling
redisClient.on('error', (err) => {
    console.error('Redis connection error:', err);
    // Only exit on critical errors
    if (err.code === 'ECONNREFUSED' || err.code === 'EAUTH') {
        process.exit(1);
    }
});

redisClient.on('connect', () => {
    console.log('Successfully connected to Redis');
});

// Logging middleware
const requestLogger = (req, res, next) => {
    const timestamp = new Date().toISOString();
    const { method, originalUrl, ip } = req;
    console.log(`[${timestamp}] ${method} ${originalUrl} - IP: ${ip}`);
    
    // Log request body for POST requests, excluding sensitive routes
    if (method === 'POST' && !originalUrl.includes('/login')) {
        console.log('Request body:', JSON.stringify(req.body));
    }
    next();
};

app.use(requestLogger);

// JWT Authentication middleware
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ 
            error: 'Authentication required',
            message: 'No token provided' 
        });
    }

    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        req.user = decoded;
        next();
    } catch (err) {
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

// Login endpoint with improved error handling
app.post('/api/login', async (req, res) => {
    try {
        const { username, password } = req.body;

        if (!username || !password) {
            return res.status(400).json({ 
                error: 'Missing credentials',
                message: 'Username and password are required' 
            });
        }

        const isValidCredentials = 
            username === process.env.VITE_ADMIN_USERNAME && 
            password === process.env.VITE_ADMIN_PASSWORD;

        if (!isValidCredentials) {
            console.warn(`Failed login attempt for user: ${username}`);
            return res.status(401).json({ 
                error: 'Invalid credentials',
                message: 'Username or password is incorrect' 
            });
        }

        const token = jwt.sign(
            { 
                id: 1,
                username: username,
                role: 'admin'
            },
            process.env.JWT_SECRET,
            { 
                expiresIn: '24h',
                algorithm: 'HS256'
            }
        );

        console.log(`Successful login for user: ${username}`);
        res.json({ 
            token,
            user: {
                id: 1,
                username: username,
                role: 'admin'
            }
        });
    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ 
            error: 'Internal server error',
            message: 'An unexpected error occurred during login' 
        });
    }
});

// Protected status endpoint
app.get('/api/status', authenticateToken, (req, res) => {
    res.json({ 
        status: 'operational',
        authenticated: true,
        user: req.user,
        serverTime: new Date().toISOString()
    });
});

// WireGuard client data endpoints
app.get('/api/clients', authenticateToken, async (req, res) => {
    try {
        const clientData = await redisClient.get('wireguard_clients');
        res.json(clientData ? JSON.parse(clientData) : []);
    } catch (error) {
        console.error('Error retrieving client data:', error);
        res.status(500).json({ 
            error: 'Database error',
            message: 'Failed to retrieve client data' 
        });
    }
});

app.post('/api/clients', authenticateToken, async (req, res) => {
    try {
        const { clientData } = req.body;
        
        if (!clientData || !Array.isArray(clientData)) {
            return res.status(400).json({ 
                error: 'Invalid data',
                message: 'Client data must be an array' 
            });
        }

        await redisClient.set('wireguard_clients', JSON.stringify(clientData));
        res.json({ success: true });
    } catch (error) {
        console.error('Error storing client data:', error);
        res.status(500).json({ 
            error: 'Database error',
            message: 'Failed to store client data' 
        });
    }
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Unhandled error:', err);
    res.status(500).json({ 
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'production' 
            ? 'An unexpected error occurred' 
            : err.message 
    });
});

// Start server
const server = app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});

// Graceful shutdown handling
const shutdown = async (signal) => {
    console.log(`\nReceived ${signal}. Starting graceful shutdown...`);
    
    // Close server first to stop accepting new connections
    server.close(() => {
        console.log('HTTP server closed');
    });

    try {
        // Disconnect Redis
        await redisClient.quit();
        console.log('Redis connection closed');
        
        // Exit process
        process.exit(0);
    } catch (err) {
        console.error('Error during shutdown:', err);
        process.exit(1);
    }
};

// Handle various shutdown signals
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('uncaughtException', (err) => {
    console.error('Uncaught Exception:', err);
    shutdown('uncaughtException');
});
process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
    shutdown('unhandledRejection');
});