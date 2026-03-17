#include <cuda_runtime.h>
#include <cstdint>

// Standard SHA-256 constants and initial values
__constant__ uint32_t d_k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

__constant__ uint32_t d_h_init[8] = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
};

#define ROTR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

__device__ void sha256_compress(uint32_t* h, const uint32_t* w) {
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hv = h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t s1 = ROTR(e, 6) ^ ROTR(e, 11) ^ ROTR(e, 25);
        uint32_t ch = (e & f) ^ ((~e) & g);
        uint32_t t1 = hv + s1 + ch + d_k[i] + w[i];
        uint32_t s0 = ROTR(a, 2) ^ ROTR(a, 13) ^ ROTR(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = s0 + maj;
        hv = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hv;
}

// Double SHA-256 specifically for 64-byte Merkle nodes
__device__ void dsha256_merkle_node(const uint8_t* data64, uint8_t* out32) {
    uint32_t w[64], h[8];
    // First Pass - Chunk 1
    for(int i=0; i<8; i++) h[i] = d_h_init[i];
    for(int i=0; i<16; i++) w[i] = (data64[i*4]<<24)|(data64[i*4+1]<<16)|(data64[i*4+2]<<8)|data64[i*4+3];
    for(int i=16; i<64; i++) {
        uint32_t s0 = ROTR(w[i-15], 7) ^ ROTR(w[i-15], 18) ^ (w[i-15] >> 3);
        uint32_t s1 = ROTR(w[i-2], 17) ^ ROTR(w[i-2], 19) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }
    sha256_compress(h, w);
    // First Pass - Chunk 2 (Padding for 512-bit msg)
    for(int i=0; i<16; i++) w[i] = 0;
    w[0] = 0x80000000; w[15] = 512;
    for(int i=16; i<64; i++) {
        uint32_t s0 = ROTR(w[i-15], 7) ^ ROTR(w[i-15], 18) ^ (w[i-15] >> 3);
        uint32_t s1 = ROTR(w[i-2], 17) ^ ROTR(w[i-2], 19) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }
    sha256_compress(h, w);
    // Pass 2 - Hash the result of Pass 1
    uint8_t mid[32];
    for(int i=0; i<8; i++) { mid[i*4]=h[i]>>24; mid[i*4+1]=h[i]>>16; mid[i*4+2]=h[i]>>8; mid[i*4+3]=h[i]; h[i]=d_h_init[i]; }
    for(int i=0; i<8; i++) w[i] = (mid[i*4]<<24)|(mid[i*4+1]<<16)|(mid[i*4+2]<<8)|mid[i*4+3];
    w[8] = 0x80000000; for(int i=9; i<15; i++) w[i]=0; w[15] = 256;
    for(int i=16; i<64; i++) {
        uint32_t s0 = ROTR(w[i-15], 7) ^ ROTR(w[i-15], 18) ^ (w[i-15] >> 3);
        uint32_t s1 = ROTR(w[i-2], 17) ^ ROTR(w[i-2], 19) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }
    sha256_compress(h, w);
    for(int i=0; i<8; i++) { out32[i*4]=h[i]>>24; out32[i*4+1]=h[i]>>16; out32[i*4+2]=h[i]>>8; out32[i*4+3]=h[i]; }
}

__global__ void merkleLevelKernel(const uint8_t* input, uint8_t* output, int numPairs, int totalInputNodes) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= numPairs) return;
    uint8_t chunk[64];
    for(int i=0; i<32; i++) chunk[i] = input[idx*64 + i]; // Left
    if (idx * 2 + 1 >= totalInputNodes) {
        for(int i=0; i<32; i++) chunk[32+i] = input[idx*64 + i]; // Duplicate Left if odd
    } else {
        for(int i=0; i<32; i++) chunk[32+i] = input[idx*64 + 32 + i]; // Right
    }
    dsha256_merkle_node(chunk, output + idx*32);
}

extern "C" int cudaMerkleRoot(const uint8_t* txHashes, int numTx, uint8_t* root) {
    if (numTx <= 0) return -1;
    uint8_t *d_buf[2];
    cudaMalloc(&d_buf[0], numTx * 32);
    cudaMalloc(&d_buf[1], numTx * 32);
    cudaMemcpy(d_buf[0], txHashes, numTx * 32, cudaMemcpyHostToDevice);
    int count = numTx;
    int curr = 0;
    while (count > 1) {
        int pairs = (count + 1) / 2;
        merkleLevelKernel<<<(pairs+255)/256, 256>>>(d_buf[curr], d_buf[1-curr], pairs, count);
        count = pairs;
        curr = 1 - curr;
    }
    cudaMemcpy(root, d_buf[curr], 32, cudaMemcpyDeviceToHost);
    cudaFree(d_buf[0]); cudaFree(d_buf[1]);
    return 0;
}