#include <cuda_runtime.h>
#include <cstdint>
#include <cstring>

// SHA-256 constants
__constant__ uint32_t d_k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

// Initial hash values
__constant__ uint32_t d_h[8] = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
};

// Simplified SHA-256 for 64-byte input (one block)
__device__ void sha256_64bytes(const uint8_t* data, uint8_t* hash) {
    uint32_t w[64];
    uint32_t a, b, c, d, e, f, g, h;
    
    // Initialize
    a = d_h[0]; b = d_h[1]; c = d_h[2]; d = d_h[3];
    e = d_h[4]; f = d_h[5]; g = d_h[6]; h = d_h[7];
    
    // Prepare message schedule (first 16 words from data)
    #pragma unroll
    for (int i = 0; i < 16; i++) {
        w[i] = (data[i*4] << 24) | (data[i*4+1] << 16) | 
               (data[i*4+2] << 8) | data[i*4+3];
    }
    
    // Extend to 64 words
    #pragma unroll
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ((w[i-15] >> 7) | (w[i-15] << 25)) ^ 
                      ((w[i-15] >> 18) | (w[i-15] << 14)) ^ (w[i-15] >> 3);
        uint32_t s1 = ((w[i-2] >> 17) | (w[i-2] << 15)) ^ 
                      ((w[i-2] >> 19) | (w[i-2] << 13)) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }
    
    // Main compression loop
    #pragma unroll
    for (int i = 0; i < 64; i++) {
        uint32_t S1 = ((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7));
        uint32_t ch = (e & f) ^ ((~e) & g);
        uint32_t temp1 = h + S1 + ch + d_k[i] + w[i];
        uint32_t S0 = ((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10));
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = S0 + maj;
        
        h = g; g = f; f = e; e = d + temp1;
        d = c; c = b; b = a; a = temp1 + temp2;
    }
    
    // Add compressed chunk to current hash value
    uint32_t hv[8] = {
        d_h[0] + a, d_h[1] + b, d_h[2] + c, d_h[3] + d,
        d_h[4] + e, d_h[5] + f, d_h[6] + g, d_h[7] + h
    };
    
    // Store result (big-endian)
    #pragma unroll
    for (int i = 0; i < 8; i++) {
        hash[i*4] = (hv[i] >> 24) & 0xff;
        hash[i*4+1] = (hv[i] >> 16) & 0xff;
        hash[i*4+2] = (hv[i] >> 8) & 0xff;
        hash[i*4+3] = hv[i] & 0xff;
    }
}

// Double SHA-256 (Bitcoin standard)
__device__ void hash256(const uint8_t* data, uint8_t* hash) {
    uint8_t temp[32];
    sha256_64bytes(data, temp);
    sha256_64bytes(temp, hash);
}

__global__ void merkleLevel(
    const uint8_t* leaves,
    uint8_t* parents,
    int numPairs
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= numPairs) return;
    
    uint8_t input[64];
    uint8_t hash[32];
    
    // Concatenate two 32-byte hashes
    memcpy(input, leaves + idx * 64, 64);
    
    // Double SHA-256
    hash256(input, hash);
    
    memcpy(parents + idx * 32, hash, 32);
}

extern "C" int cudaMerkleRoot(
    const uint8_t* txHashes,
    int numTx,
    uint8_t* root
) {
    int numLeaves = 1;
    while (numLeaves < numTx) numLeaves <<= 1;
    
    uint8_t *d_buffer[2];
    cudaMalloc(&d_buffer[0], numLeaves * 32);
    cudaMalloc(&d_buffer[1], numLeaves * 32);
    
    cudaMemcpy(d_buffer[0], txHashes, numTx * 32, cudaMemcpyHostToDevice);
    
    // Duplicate last hash for padding if needed
    if (numLeaves > numTx) {
        for (int i = numTx; i < numLeaves; i++) {
            cudaMemcpy(d_buffer[0] + i * 32, txHashes + (numTx-1) * 32, 32, cudaMemcpyHostToDevice);
        }
    }
    
    int current = 0;
    int count = numLeaves;
    
    while (count > 1) {
        int pairs = count / 2;
        int threads = 256;
        int blocks = (pairs + threads - 1) / threads;
        
        merkleLevel<<<blocks, threads>>>(
            d_buffer[current], 
            d_buffer[1-current], 
            pairs
        );
        
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess) {
            cudaFree(d_buffer[0]);
            cudaFree(d_buffer[1]);
            return -1;
        }
        
        count = pairs;
        current = 1 - current;
    }
    
    cudaMemcpy(root, d_buffer[current], 32, cudaMemcpyDeviceToHost);
    
    cudaFree(d_buffer[0]);
    cudaFree(d_buffer[1]);
    
    return 0;
}