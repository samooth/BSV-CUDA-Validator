#include <cuda_runtime.h>
#include <cstdint>
#include <stdio.h>

typedef struct { uint32_t limbs[8]; } uint256;

#pragma pack(push, 1)
typedef struct {
    uint8_t hash[32];
    uint8_t sig[72];
    uint8_t pubKey[65];
    uint16_t sigLen;
    uint16_t pubKeyLen;
} SigTask;
#pragma pack(pop)

// Field Prime P
__constant__ uint32_t c_p[8] = {0xFFFFFC2F, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF};
// Curve Order N
__constant__ uint32_t c_n[8] = {0xD0364141, 0xBFD25E8C, 0xAF48A03B, 0xBAAEDCE6, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF};
// Generator G
__constant__ uint32_t c_gx[8] = {0x16F81798, 0x59F2815B, 0x2DCE28D9, 0x029BFCDB, 0xCE870B07, 0x55A06295, 0xF9DCBBAC, 0x79BE667E};
__constant__ uint32_t c_gy[8] = {0xFB10D4B8, 0x9C47D08F, 0xA6855419, 0xFD17B448, 0x0E1108A8, 0x5DA4FBFC, 0x26A3C465, 0x483ADA77};

// Montgomery Constants (inv = -m^-1 mod 2^32)
__constant__ uint32_t c_p_inv = 0xD2253531;
__constant__ uint32_t c_p_r2[8] = {0x000E90A1, 0x000007A2, 0x00000001, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000};
__constant__ uint32_t c_n_inv = 0x5588B13F;
__constant__ uint32_t c_n_r2[8] = {0x67D7D140, 0x896CF214, 0x0E7CF878, 0x741496C2, 0x5BCD07C6, 0xE697F5E4, 0x81C69BC5, 0x9D671CD5};

__device__ __forceinline__ void print256(const char* label, const uint32_t* a) {
    printf("%s: %08x%08x%08x%08x%08x%08x%08x%08x\n", label, a[7], a[6], a[5], a[4], a[3], a[2], a[1], a[0]);
}

__device__ __forceinline__ void add256(uint32_t* r, const uint32_t* a, const uint32_t* b) {
    asm volatile (
        "add.cc.u32 %0, %8, %16;  addc.cc.u32 %1, %9, %17;  addc.cc.u32 %2, %10, %18; addc.cc.u32 %3, %11, %19; "
        "addc.cc.u32 %4, %12, %20; addc.cc.u32 %5, %13, %21; addc.cc.u32 %6, %14, %22; addc.u32    %7, %15, %23;"
        : "=r"(r[0]), "=r"(r[1]), "=r"(r[2]), "=r"(r[3]), "=r"(r[4]), "=r"(r[5]), "=r"(r[6]), "=r"(r[7])
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]), "r"(a[4]), "r"(a[5]), "r"(a[6]), "r"(a[7]),
          "r"(b[0]), "r"(b[1]), "r"(b[2]), "r"(b[3]), "r"(b[4]), "r"(b[5]), "r"(b[6]), "r"(b[7])
    );
}

__device__ __forceinline__ uint32_t sub256(uint32_t* r, const uint32_t* a, const uint32_t* b) {
    uint32_t carry;
    asm volatile (
        "sub.cc.u32 %0, %9, %17;  subc.cc.u32 %1, %10, %18; subc.cc.u32 %2, %11, %19; subc.cc.u32 %3, %12, %20; "
        "subc.cc.u32 %4, %13, %21; subc.cc.u32 %5, %14, %22; subc.cc.u32 %6, %15, %23; subc.cc.u32 %7, %16, %24; "
        "addc.u32 %8, 0, 0; "
        : "=r"(r[0]), "=r"(r[1]), "=r"(r[2]), "=r"(r[3]), "=r"(r[4]), "=r"(r[5]), "=r"(r[6]), "=r"(r[7]), "=r"(carry)
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]), "r"(a[4]), "r"(a[5]), "r"(a[6]), "r"(a[7]),
          "r"(b[0]), "r"(b[1]), "r"(b[2]), "r"(b[3]), "r"(b[4]), "r"(b[5]), "r"(b[6]), "r"(b[7])
    );
    return carry; 
}

__device__ void montMul(uint32_t* r, const uint32_t* a, const uint32_t* b, const uint32_t* m, uint32_t minv) {
    uint32_t t[9] = {0};
    for (int i = 0; i < 8; i++) {
        uint32_t ui = (t[0] + a[i] * b[0]) * minv;
        uint64_t chain = (uint64_t)a[i] * b[0] + t[0] + (uint64_t)ui * m[0];
        for (int j = 1; j < 8; j++) {
            chain = (uint64_t)a[i] * b[j] + t[j] + (uint64_t)ui * m[j] + (chain >> 32);
            t[j-1] = (uint32_t)chain;
        }
        chain = (uint64_t)t[8] + (chain >> 32);
        t[7] = (uint32_t)chain;
        t[8] = (uint32_t)(chain >> 32);
    }
    uint32_t res[8];
    uint32_t no_borrow = sub256(res, t, m);
    if (t[8] > 0 || no_borrow) {
        for(int k=0; k<8; k++) r[k] = res[k];
    } else {
        for(int k=0; k<8; k++) r[k] = t[k];
    }
}

__device__ void modAdd(uint32_t* r, const uint32_t* a, const uint32_t* b, const uint32_t* m) {
    uint32_t t[8], c;
    asm volatile (
        "add.cc.u32 %0, %9, %17;  addc.cc.u32 %1, %10, %18; addc.cc.u32 %2, %11, %19; addc.cc.u32 %3, %12, %20; "
        "addc.cc.u32 %4, %13, %21; addc.cc.u32 %5, %14, %22; addc.cc.u32 %6, %15, %23; addc.cc.u32 %7, %16, %24; "
        "addc.u32 %8, 0, 0;"
        : "=r"(t[0]), "=r"(t[1]), "=r"(t[2]), "=r"(t[3]), "=r"(t[4]), "=r"(t[5]), "=r"(t[6]), "=r"(t[7]), "=r"(c)
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]), "r"(a[4]), "r"(a[5]), "r"(a[6]), "r"(a[7]),
          "r"(b[0]), "r"(b[1]), "r"(b[2]), "r"(b[3]), "r"(b[4]), "r"(b[5]), "r"(b[6]), "r"(b[7])
    );
    uint32_t res[8];
    uint32_t no_borrow = sub256(res, t, m);
    if (c || no_borrow) {
        for(int k=0; k<8; k++) r[k] = res[k];
    } else {
        for(int k=0; k<8; k++) r[k] = t[k];
    }
}

__device__ void modSub(uint32_t* r, const uint32_t* a, const uint32_t* b, const uint32_t* m) {
    uint32_t res[8];
    uint32_t no_borrow = sub256(res, a, b);
    if (no_borrow) {
        for(int k=0; k<8; k++) r[k] = res[k];
    } else {
        add256(r, res, m);
    }
}

__global__ void testMathKernel() {
    uint32_t a[8] = {1, 0, 0, 0, 0, 0, 0, 0};
    uint32_t b[8] = {2, 0, 0, 0, 0, 0, 0, 0};
    uint32_t r[8];
    
    printf("--- CUDA Math Test ---\n");
    modSub(r, a, b, c_p);
    print256("1 - 2 mod p", r);
    
    // Test Montgomery mult
    uint32_t a_mont[8], b_mont[8], r_mont[8];
    montMul(a_mont, a, c_p_r2, c_p, c_p_inv);
    montMul(b_mont, b, c_p_r2, c_p, c_p_inv);
    montMul(r_mont, a_mont, b_mont, c_p, c_p_inv);
    
    uint32_t one[8] = {1, 0, 0, 0, 0, 0, 0, 0};
    montMul(r, r_mont, one, c_p, c_p_inv);
    print256("1 * 2 mont", r);
}

int main() {
    testMathKernel<<<1, 1>>>();
    cudaDeviceSynchronize();
    return 0;
}
