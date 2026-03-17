import 'dotenv/config'
import express from 'express';
import { promisify } from 'util';

const app = express();
app.use(express.json({ limit: '100mb' }));

// Debug: log all requests
app.use((req, res, next) => {
    console.log(`${req.method} ${req.path}`, req.headers.authorization ? 'with auth' : 'no auth');
    next();
});

// Simple auth middleware
const authMiddleware = (req: express.Request, res: express.Response, next: express.NextFunction) => {
    const token = process.env.GPU_TOKEN || 'default_token_change_me';
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.includes(token)) {
        console.log('Auth failed:', authHeader);
        return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
};

// Load native addon or use stub
let bsvCuda: any;
let usingGPU = false;

try {
    bsvCuda = require('../build/Release/bsv_cuda.node');
    console.log('Native addon loaded:', Object.keys(bsvCuda));
    usingGPU = true;
} catch (e) {
    console.log('Native addon failed, using CPU stub:', (e as Error).message);
    // Stub for CPU-only mode
    bsvCuda = {
        verifySignatures: (tasks: any[], cb: any) => {
            console.log('CPU stub: verifySignatures called with', tasks.length, 'tasks');
            // Return all true for testing
            setImmediate(() => cb(null, tasks.map(() => true)));
        },
        computeMerkleRoot: (hashes: any[], cb: any) => {
            console.log('CPU stub: computeMerkleRoot called with', hashes.length, 'hashes');
            // Return dummy hash
            setImmediate(() => cb(null, Buffer.alloc(32, 0xab)));
        }
    };
}

const verifySignaturesAsync = promisify(bsvCuda.verifySignatures);
const computeMerkleRootAsync = promisify(bsvCuda.computeMerkleRoot);

app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        gpu: usingGPU ? 'NVIDIA GPU' : 'CPU (stub)',
        timestamp: new Date().toISOString()
    });
});

app.post('/verify/signatures', authMiddleware, async (req, res) => {
    console.log('Verify signatures:', req.body);
    
    try {
        const tasks = req.body?.tasks || [];
        if (!Array.isArray(tasks)) {
            return res.status(400).json({ error: 'tasks must be an array' });
        }
        
        const start = Date.now();
        const results = await verifySignaturesAsync(tasks);
        
        res.json({
            results,
            batchTimeMs: Date.now() - start,
            count: tasks.length,
            mode: usingGPU ? 'gpu' : 'cpu'
        });
    } catch (e) {
        console.error('Error in verifySignatures:', e);
        // Ensure we always return a valid JSON response
        res.status(500).json({ 
            error: (e as Error).message,
            mode: usingGPU ? 'gpu' : 'cpu'
        });
    }
});

app.post('/compute/merkle', authMiddleware, async (req, res) => {
    console.log('Compute merkle:', req.body);
    
    try {
        const txHashes = req.body?.txHashes || [];
        if (!Array.isArray(txHashes)) {
            return res.status(400).json({ error: 'txHashes must be an array' });
        }
        
        const start = Date.now();
        const root = await computeMerkleRootAsync(txHashes);
        
        res.json({
            merkleRoot: root.toString('hex'),
            computationTimeMs: Date.now() - start,
            txCount: txHashes.length,
            mode: usingGPU ? 'gpu' : 'cpu'
        });
    } catch (e) {
        console.error('Error in computeMerkle:', e);
        res.status(500).json({ 
            error: (e as Error).message,
            mode: usingGPU ? 'gpu' : 'cpu'
        });
    }
});

const PORT = process.env.RPC_PORT || 8080;
app.listen(PORT, () => {
    console.log(`BSV CUDA Validator listening on port ${PORT}`);
    console.log(`Mode: ${usingGPU ? 'GPU' : 'CPU (stub)'}`);
});