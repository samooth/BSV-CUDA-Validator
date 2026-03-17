// Job router
import axios from 'axios';

const HOME_GPU_URL = 'http://192.168.1.2:8080';

export async function validateBlockGPU(blockHex: string): Promise<boolean> {
    try {
        const response = await axios.post(
            `${HOME_GPU_URL}/validate`,
            { block: blockHex },
            { timeout: 5000, headers: { Authorization: `Bearer ${process.env.GPU_TOKEN}` } }
        );
        return response.data.valid;
    } catch (e) {
        console.error('GPU validation failed, falling back to CPU:', e.message);
        return validateBlockCPU(blockHex);  // Fallback
    }
}