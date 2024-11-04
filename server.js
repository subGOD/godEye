import express from 'express';
import cors from 'cors';
import jwt from 'jsonwebtoken';
import Redis from 'ioredis';
import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Initialize dotenv
config();

// Debug log for environment variables
console.log('Environment variables loaded:', {
    adminUser: process.env.VITE_ADMIN_USERNAME,
    adminPassLength: process.env.VITE_ADMIN_PASSWORD?.length,
    jwtSecretLength: process.env.JWT_SECRET?.length,
    redisPassLength: process.env.REDIS_PASSWORD?.length
});

const app = express();
const port = process.env.PORT || 3001;

// Enhanced CORS configuration to match your frontend
app.use(cors({
    origin: '*', // In production, you might want to restrict this
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json());

// Request logging middleware
app.use((req, res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`, {
        headers: req.headers,
        body: req.method === 'POST' ? req.body : undefined
    });
    next();
});

// Redis setup
const redis = new Redis({
    port: 6379,
    host: '127.0.0.1',
    password: process.env.REDIS_PASSWORD
});

// Authentication middleware matching your frontend's JWT expectations
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ message: 'No token provided' });
    }

    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ message: 'Invalid token' });
        }
        req.user = user;
        next();
    });
};

// Login endpoint matching your frontend's expectations
app.post('/api/login', async (req, res) => {
    console.log('Login attempt received:', req.body);
    
    const { username, password } = req.body;
    
    // Log authentication attempt details
    console.log('Checking credentials:', {
        providedUsername: username,
        expectedUsername: process.env.VITE_ADMIN_USERNAME,
        credentialsMatch: username === process.env.VITE_ADMIN_USERNAME && 
                         password === process.env.VITE_ADMIN_PASSWORD
    });

    if (username === process.env.VITE_ADMIN_USERNAME && 
        password === process.env.VITE_ADMIN_PASSWORD) {
        
        const token = jwt.sign(
            { 
                id: 1,
                username: username,
                role: 'admin'
            },
            process.env.JWT_SECRET,
            { expiresIn: '24h' }
        );
        
        console.log('Login successful for:', username);
        res.json({ 
            token,
            user: {
                id: 1,
                username: username,
                role: 'admin'
            }
        });
    } else {
        console.log('Login failed - invalid credentials');
        res.status(401).json({ message: 'Invalid credentials' });
    }
});

// Protected status endpoint
app.get('/api/status', authenticateToken, (req, res) => {
    res.json({ 
        authenticated: true,
        user: req.user,
        serverTime: new Date().toISOString()
    });
});

// WireGuard client data endpoints
app.get('/api/clients', authenticateToken, async (req, res) => {
    try {
        const clientData = await redis.get('wireguard_clients');
        res.json(clientData ? JSON.parse(clientData) : []);
    } catch (error) {
        console.error('Error retrieving client data:', error);
        res.status(500).json({ message: 'Failed to retrieve client data' });
    }
});

app.post('/api/clients', authenticateToken, async (req, res) => {
    try {
        const { clientData } = req.body;
        await redis.set('wireguard_clients', JSON.stringify(clientData));
        res.json({ success: true });
    } catch (error) {
        console.error('Error storing client data:', error);
        res.status(500).json({ message: 'Failed to store client data' });
    }
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Server error:', err);
    res.status(500).json({ message: 'Internal server error' });
});

// Start server
app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});

// Handle Redis connection errors
redis.on('error', (err) => {
    console.error('Redis connection error:', err);
});

// Graceful shutdown handlers
process.on('SIGTERM', () => {
    console.log('Received SIGTERM. Performing graceful shutdown...');
    redis.quit();
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log('Received SIGINT. Performing graceful shutdown...');
    redis.quit();
    process.exit(0);
});