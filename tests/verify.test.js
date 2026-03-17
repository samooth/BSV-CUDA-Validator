const axios = require('axios');
const { execSync } = require('child_process');

// Note: This test expects the server to be running.
// You can run it with: docker compose up -d --build
// Or run locally if you have CUDA.

const BASE_URL = 'http://localhost:8080';
const GPU_TOKEN = 'test_token';

async function runTest() {
    console.log('--- BSV CUDA Validator Test ---');
    
    try {
        const health = await axios.get(`${BASE_URL}/health`);
        console.log('Health:', health.data);
    } catch (e) {
        console.error('Health check failed. Is the server running?');
        return;
    }

    const tasks = [
        {
            // A valid signature from BSV network
            hash: "f68255748d703b75d3495f4d29c62c1cf687e998301e7c1639245ee24959a13b",
            sig: "30440220734a61fe19960e730dc6d131656b6a61154e50f286ce8f7f93d76a9f89d2e971022031892b4cebebbe58fccad4235a242f024371578c2689ca192268754dc86c1cba41",
            pubKey: "0222cfa3253e2706e5a7d69785259d098c998e20d185ee515a2b9ad3177bca5b0f"
        }
    ];

    try {
        const response = await axios.post(`${BASE_URL}/verify/signatures`, { tasks }, {
            headers: { 'Authorization': `Bearer ${GPU_TOKEN}` }
        });
        console.log('Verification response:', response.data);
    } catch (e) {
        console.error('Verification failed:', e.response?.data || e.message);
    }
}

runTest();
