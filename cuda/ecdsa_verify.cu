#include <cuda_runtime.h>
#include <cstdint>
#include <stdio.h>

// Set to 1 to see intermediate math in docker logs
#define DEBUG_VERIFY 1

// ============================================================================
// Secp256k1 Constants & Types (LSB-First)
// ============================================================================

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

__constant__ uint32_t c_p[8] = {0xFFFFFC2F, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF};
__constant__ uint32_t c_n[8] = {0xD0364141, 0xBFD25E8C, 0xAF48A03B, 0xBAAEDCE6, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF};
__constant__ uint32_t c_gx[8] = {0x16F81798, 0x59F2815B, 0x2DCE28D9, 0x029BFCDB, 0xCE870B07, 0x55A06295, 0xF9DCBBAC, 0x79BE667E};
__constant__ uint32_t c_gy[8] = {0xFB10D4B8, 0x9C47D08F, 0xA6855419, 0xFD17B448, 0x0E1108A8, 0x5DA4FBFC, 0x26A3C465, 0x483ADA77};

__constant__ uint32_t c_p_inv = 0xD2253531;
__constant__ uint32_t c_p_r2[8] = {0x000E90A1, 0x000007A2, 0x00000001, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000};
__constant__ uint32_t c_n_inv = 0x5588B13F;
__constant__ uint32_t c_n_r2[8] = {0x67D7D140, 0x896CF214, 0x0E7CF878, 0x741496C2, 0x5BCD07C6, 0xE697F5E4, 0x81C69BC5, 0x9D671CD5};
__constant__ uint32_t c_sqrt_e[8] = {0xFFFFFE0C, 0xFFFFFFFB, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0x3FFFFFFF};

// ============================================================================
// Arithmetic
// ============================================================================

__device__ __forceinline__ void print256(const char* label, const uint32_t* a) {
#if DEBUG_VERIFY
    printf("%s: %08x%08x%08x%08x%08x%08x%08x%08x\n", label, a[7], a[6], a[5], a[4], a[3], a[2], a[1], a[0]);
#endif
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

__device__ __forceinline__ bool isZero256(const uint32_t* a) {
    return (a[0] | a[1] | a[2] | a[3] | a[4] | a[5] | a[6] | a[7]) == 0;
}

__device__ void montMul(uint32_t* r, const uint32_t* a, const uint32_t* b, const uint32_t* m, uint32_t minv) {
    uint32_t t[9] = {0};
    for (int i = 0; i < 8; i++) {
        uint32_t ui = (t[0] + a[i] * b[0]) * minv;
        
        // Iteración inicial limpia (garantiza evitar overflow)
        uint64_t term1 = (uint64_t)a[i] * b[0] + t[0];
        uint64_t term2 = (uint64_t)ui * m[0] + (uint32_t)term1;
        uint64_t carry_in = (term1 >> 32) + (term2 >> 32);
        
        for (int j = 1; j < 8; j++) {
            // Dividimos la carga para que ninguna variable supere jamás los 64 bits
            term1 = (uint64_t)a[i] * b[j] + t[j];
            term2 = (uint64_t)ui * m[j] + (uint32_t)term1;
            uint64_t carry = (term1 >> 32) + (term2 >> 32);
            
            // Añadimos el acarreo de la iteración anterior
            uint64_t term3 = (uint32_t)term2 + carry_in;
            t[j-1] = (uint32_t)term3;
            carry_in = carry + (term3 >> 32);
        }
        
        uint64_t final_sum = (uint64_t)t[8] + carry_in;
        t[7] = (uint32_t)final_sum;
        t[8] = (uint32_t)(final_sum >> 32);
    }
    
    uint32_t res[8];
    uint32_t borrow = sub256(res, t, m);
    if (t[8] > 0 || !borrow) {
        for(int k=0; k<8; k++) r[k] = res[k];
    } else {
        for(int k=0; k<8; k++) r[k] = t[k];
    }
}

__device__ void modAdd(uint32_t* r, const uint32_t* a, const uint32_t* b, const uint32_t* m) {
    uint32_t t[8], carry = 0;
    asm volatile(
        "add.cc.u32 %0, %8, %16;\n\t"  "addc.cc.u32 %1, %9, %17;\n\t"
        "addc.cc.u32 %2, %10, %18;\n\t" "addc.cc.u32 %3, %11, %19;\n\t"
        "addc.cc.u32 %4, %12, %20;\n\t" "addc.cc.u32 %5, %13, %21;\n\t"
        "addc.cc.u32 %6, %14, %22;\n\t" "addc.cc.u32 %7, %15, %23;\n\t"
        "addc.u32 %24, 0, 0;\n\t"
        : "=r"(t[0]), "=r"(t[1]), "=r"(t[2]), "=r"(t[3]), "=r"(t[4]), "=r"(t[5]), "=r"(t[6]), "=r"(t[7]), "=r"(carry)
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]), "r"(a[4]), "r"(a[5]), "r"(a[6]), "r"(a[7]),
          "r"(b[0]), "r"(b[1]), "r"(b[2]), "r"(b[3]), "r"(b[4]), "r"(b[5]), "r"(b[6]), "r"(b[7])
    );
    uint32_t res[8], borrow = 0;
    asm volatile(
        "sub.cc.u32 %0, %8, %16;\n\t"  "subc.cc.u32 %1, %9, %17;\n\t"
        "subc.cc.u32 %2, %10, %18;\n\t" "subc.cc.u32 %3, %11, %19;\n\t"
        "subc.cc.u32 %4, %12, %20;\n\t" "subc.cc.u32 %5, %13, %21;\n\t"
        "subc.cc.u32 %6, %14, %22;\n\t" "subc.cc.u32 %7, %15, %23;\n\t"
        "subc.u32 %24, 0, 0;\n\t"
        : "=r"(res[0]), "=r"(res[1]), "=r"(res[2]), "=r"(res[3]), "=r"(res[4]), "=r"(res[5]), "=r"(res[6]), "=r"(res[7]), "=r"(borrow)
        : "r"(t[0]), "r"(t[1]), "r"(t[2]), "r"(t[3]), "r"(t[4]), "r"(t[5]), "r"(t[6]), "r"(t[7]),
          "r"(m[0]), "r"(m[1]), "r"(m[2]), "r"(m[3]), "r"(m[4]), "r"(m[5]), "r"(m[6]), "r"(m[7])
    );
    if (carry || borrow == 0) { // Si hubo acarreo de suma, o NO hubo acarreo negativo en la resta (t >= m)
        for(int i=0; i<8; i++) r[i] = res[i];
    } else {
        for(int i=0; i<8; i++) r[i] = t[i];
    }
}

__device__ void modSub(uint32_t* r, const uint32_t* a, const uint32_t* b, const uint32_t* m) {
    uint32_t res[8], borrow = 0;
    asm volatile(
        "sub.cc.u32 %0, %8, %16;\n\t"  "subc.cc.u32 %1, %9, %17;\n\t"
        "subc.cc.u32 %2, %10, %18;\n\t" "subc.cc.u32 %3, %11, %19;\n\t"
        "subc.cc.u32 %4, %12, %20;\n\t" "subc.cc.u32 %5, %13, %21;\n\t"
        "subc.cc.u32 %6, %14, %22;\n\t" "subc.cc.u32 %7, %15, %23;\n\t"
        "subc.u32 %24, 0, 0;\n\t"
        : "=r"(res[0]), "=r"(res[1]), "=r"(res[2]), "=r"(res[3]), "=r"(res[4]), "=r"(res[5]), "=r"(res[6]), "=r"(res[7]), "=r"(borrow)
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]), "r"(a[4]), "r"(a[5]), "r"(a[6]), "r"(a[7]),
          "r"(b[0]), "r"(b[1]), "r"(b[2]), "r"(b[3]), "r"(b[4]), "r"(b[5]), "r"(b[6]), "r"(b[7])
    );
    if (borrow) {
        asm volatile(
            "add.cc.u32 %0, %8, %16;\n\t"  "addc.cc.u32 %1, %9, %17;\n\t"
            "addc.cc.u32 %2, %10, %18;\n\t" "addc.cc.u32 %3, %11, %19;\n\t"
            "addc.cc.u32 %4, %12, %20;\n\t" "addc.cc.u32 %5, %13, %21;\n\t"
            "addc.cc.u32 %6, %14, %22;\n\t" "addc.u32 %7, %15, %23;\n\t"
            : "=r"(r[0]), "=r"(r[1]), "=r"(r[2]), "=r"(r[3]), "=r"(r[4]), "=r"(r[5]), "=r"(r[6]), "=r"(r[7])
            : "r"(res[0]), "r"(res[1]), "r"(res[2]), "r"(res[3]), "r"(res[4]), "r"(res[5]), "r"(res[6]), "r"(res[7]),
              "r"(m[0]), "r"(m[1]), "r"(m[2]), "r"(m[3]), "r"(m[4]), "r"(m[5]), "r"(m[6]), "r"(m[7])
        );
    } else {
        for(int i=0; i<8; i++) r[i] = res[i];
    }
}

__device__ void montExp(uint32_t* r, const uint32_t* a, const uint32_t* e, const uint32_t* m, uint32_t minv, const uint32_t* r2) {
    uint32_t res[8], base[8];
    for(int k=0; k<8; k++) { res[k] = 0; base[k] = a[k]; }
    res[0] = 1; montMul(res, res, r2, m, minv);
    for (int i = 0; i < 256; i++) {
        if ((e[i/32] >> (i%32)) & 1) montMul(res, res, base, m, minv);
        montMul(base, base, base, m, minv);
    }
    for(int k=0; k<8; k++) r[k] = res[k];
}

// ============================================================================
// Point Arithmetic
// ============================================================================

typedef struct { uint32_t x[8], y[8], z[8]; } Point;

__device__ void pointDouble(Point* r, const Point* a) {
    if (isZero256(a->z)) { for(int k=0; k<8; k++) r->z[k]=0; return; }
    uint32_t T1[8], T2[8], T3[8], S[8], M[8], nx[8], ny[8], nz[8];
    montMul(T1, a->y, a->y, c_p, c_p_inv);
    montMul(S, a->x, T1, c_p, c_p_inv);
    modAdd(S, S, S, c_p); modAdd(S, S, S, c_p);
    montMul(T2, a->x, a->x, c_p, c_p_inv);
    modAdd(M, T2, T2, c_p); modAdd(M, M, T2, c_p);
    montMul(T3, M, M, c_p, c_p_inv);
    modSub(nx, T3, S, c_p); modSub(nx, nx, S, c_p);
    modSub(T1, S, nx, c_p);
    montMul(T2, M, T1, c_p, c_p_inv);
    montMul(T1, a->y, a->y, c_p, c_p_inv);
    montMul(T3, T1, T1, c_p, c_p_inv);
    for(int k=0; k<3; k++) modAdd(T3, T3, T3, c_p);
    modSub(ny, T2, T3, c_p);
    montMul(T1, a->y, a->z, c_p, c_p_inv);
    modAdd(nz, T1, T1, c_p);
    for(int k=0; k<8; k++) { r->x[k]=nx[k]; r->y[k]=ny[k]; r->z[k]=nz[k]; }
}

__device__ void pointAdd(Point* r, const Point* a, const Point* b) {
    if (isZero256(a->z)) { *r = *b; return; }
    if (isZero256(b->z)) { *r = *a; return; }
    uint32_t Z1Z1[8], Z2Z2[8], U1[8], U2[8], S1[8], S2[8], H[8], R[8], H2[8], H3[8], V[8], T1[8], nx[8], ny[8], nz[8];
    montMul(Z1Z1, a->z, a->z, c_p, c_p_inv);
    montMul(Z2Z2, b->z, b->z, c_p, c_p_inv);
    montMul(U1, a->x, Z2Z2, c_p, c_p_inv);
    montMul(U2, b->x, Z1Z1, c_p, c_p_inv);
    montMul(T1, a->y, b->z, c_p, c_p_inv); montMul(S1, T1, Z2Z2, c_p, c_p_inv);
    montMul(T1, b->y, a->z, c_p, c_p_inv); montMul(S2, T1, Z1Z1, c_p, c_p_inv);
    modSub(H, U2, U1, c_p);
    modSub(R, S2, S1, c_p);
    if (isZero256(H)) {
        if (isZero256(R)) pointDouble(r, a); else { for(int k=0; k<8; k++) r->z[k]=0; }
        return;
    }
    montMul(H2, H, H, c_p, c_p_inv);
    montMul(H3, H2, H, c_p, c_p_inv);
    montMul(V, U1, H2, c_p, c_p_inv);
    montMul(nx, R, R, c_p, c_p_inv);
    modSub(nx, nx, H3, c_p);
    modSub(nx, nx, V, c_p); modSub(nx, nx, V, c_p);
    modSub(T1, V, nx, c_p);
    uint32_t T2[8], T3[8];
    montMul(T2, R, T1, c_p, c_p_inv);
    montMul(T3, S1, H3, c_p, c_p_inv);
    modSub(ny, T2, T3, c_p);
    montMul(T1, a->z, b->z, c_p, c_p_inv);
    montMul(nz, T1, H, c_p, c_p_inv);
    for(int k=0; k<8; k++) { r->x[k]=nx[k]; r->y[k]=ny[k]; r->z[k]=nz[k]; }
}

// ============================================================================
// Logic
// ============================================================================

__device__ void parseRaw256(uint32_t* r, const uint8_t* data, int len) {
    for(int k=0; k<8; k++) r[k] = 0;
    for(int k=0; k<len; k++) {
        int limb_idx = k / 4;
        int byte_in_limb = k % 4;
        ((uint8_t*)r)[limb_idx * 4 + byte_in_limb] = data[len - 1 - k];
    }
}

__device__ bool parseDER(const uint8_t* sig, int len, uint32_t* r, uint32_t* s) {
    if (len < 8 || sig[0] != 0x30) return false;
    int rlen = sig[3];
    if (rlen > 33 || 5 + rlen >= len) return false;
    int slen = sig[5 + rlen];
    if (slen > 33) return false;
    const uint8_t* r_start = &sig[4];
    if (rlen > 32 && r_start[0] == 0) { r_start++; rlen--; }
    if (rlen > 32) return false;
    parseRaw256(r, r_start, rlen);
    const uint8_t* s_start = &sig[6 + sig[3]];
    if (slen > 32 && s_start[0] == 0) { s_start++; slen--; }
    if (slen > 32) return false;
    parseRaw256(s, s_start, slen);
    return true;
}

__device__ bool parsePubKey(const uint8_t* pk, int len, Point* Q) {
    if (len == 65 && pk[0] == 0x04) {
        parseRaw256(Q->x, &pk[1], 32);
        parseRaw256(Q->y, &pk[33], 32);
        for(int k=0; k<8; k++) Q->z[k] = 0;
        Q->z[0] = 1;
        montMul(Q->x, Q->x, c_p_r2, c_p, c_p_inv);
        montMul(Q->y, Q->y, c_p_r2, c_p, c_p_inv);
        montMul(Q->z, Q->z, c_p_r2, c_p, c_p_inv);
        return true;
    } else if (len == 33 && (pk[0] == 0x02 || pk[0] == 0x03)) {
        parseRaw256(Q->x, &pk[1], 32);
        montMul(Q->x, Q->x, c_p_r2, c_p, c_p_inv);
        uint32_t x2[8], x3[8], y2[8], seven_mont[8] = {7,0,0,0,0,0,0,0};
        montMul(seven_mont, seven_mont, c_p_r2, c_p, c_p_inv);
        montMul(x2, Q->x, Q->x, c_p, c_p_inv);
        montMul(x3, x2, Q->x, c_p, c_p_inv);
        modAdd(y2, x3, seven_mont, c_p);
        montExp(Q->y, y2, c_sqrt_e, c_p, c_p_inv, c_p_r2);
        uint32_t y_raw[8], one[8] = {1,0,0,0,0,0,0,0};
        montMul(y_raw, Q->y, one, c_p, c_p_inv);
        if ((y_raw[0] & 1) != (pk[0] == 0x03)) {
            modSub(Q->y, (const uint32_t[]){0,0,0,0,0,0,0,0}, Q->y, c_p);
        }
        for(int k=0; k<8; k++) Q->z[k] = 0;
        Q->z[0] = 1;
        montMul(Q->z, Q->z, c_p_r2, c_p, c_p_inv);
        return true;
    }
    return false;
}

__device__ bool verify_internal(const SigTask* t, int idx) {
    uint32_t r_val[8], s_val[8], h_val[8];
    if (!parseDER(t->sig, t->sigLen, r_val, s_val)) return false;
    parseRaw256(h_val, t->hash, 32);
    
    if (idx == 0) {
        print256("Parsed H", h_val);
        print256("Parsed R", r_val);
        print256("Parsed S", s_val);
    }

    uint32_t n_half[8];
    for(int k=0; k<8; k++) n_half[k] = c_n[k];
    uint32_t carry = 0;
    for(int k=7; k>=0; k--) { uint32_t nc = (n_half[k] & 1) << 31; n_half[k] = (n_half[k] >> 1) | carry; carry = nc; }
    for(int k=7; k>=0; k--) { if (s_val[k] > n_half[k]) return false; if (s_val[k] < n_half[k]) break; }
    
    Point Q;
    if (!parsePubKey(t->pubKey, t->pubKeyLen, &Q)) return false;
    
    uint32_t s_mont[8], w_mont[8];
    montMul(s_mont, s_val, c_n_r2, c_n, c_n_inv);
    // Fermat Inverse: w = s^(n-2) mod n
    montExp(w_mont, s_mont, (const uint32_t[]){0xD036413F, 0xBFD25E8C, 0xAF48A03B, 0xBAAEDCE6, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF}, c_n, c_n_inv, c_n_r2);
    
    uint32_t h_mont[8], r_mont[8], u1[8], u2[8];
    montMul(h_mont, h_val, c_n_r2, c_n, c_n_inv);
    montMul(r_mont, r_val, c_n_r2, c_n, c_n_inv);
    montMul(u1, h_mont, w_mont, c_n, c_n_inv);
    montMul(u2, r_mont, w_mont, c_n, c_n_inv);
    
    uint32_t u1_raw[8], u2_raw[8], one[8] = {1,0,0,0,0,0,0,0};
    montMul(u1_raw, u1, one, c_n, c_n_inv);
    montMul(u2_raw, u2, one, c_n, c_n_inv);

    Point G = {{c_gx[0],c_gx[1],c_gx[2],c_gx[3],c_gx[4],c_gx[5],c_gx[6],c_gx[7]},
               {c_gy[0],c_gy[1],c_gy[2],c_gy[3],c_gy[4],c_gy[5],c_gy[6],c_gy[7]},
               {1,0,0,0,0,0,0,0}};
    montMul(G.x, G.x, c_p_r2, c_p, c_p_inv); montMul(G.y, G.y, c_p_r2, c_p, c_p_inv); montMul(G.z, G.z, c_p_r2, c_p, c_p_inv);
    
    Point GPQ, Res; for(int k=0; k<8; k++) Res.z[k]=0;
    pointAdd(&GPQ, &G, &Q);
    
    for (int i = 255; i >= 0; i--) {
        pointDouble(&Res, &Res);
        int b1 = (u1_raw[i/32] >> (i%32)) & 1;
        int b2 = (u2_raw[i/32] >> (i%32)) & 1;
        if (b1 && b2) pointAdd(&Res, &Res, &GPQ);
        else if (b1) pointAdd(&Res, &Res, &G);
        else if (b2) pointAdd(&Res, &Res, &Q);
    }
    
    if (isZero256(Res.z)) return false;
    
    uint32_t z_inv[8], z_inv2[8], x_affine[8];
    // Fermat Inverse in GF(p): z^(p-2) mod p
    montExp(z_inv, Res.z, (const uint32_t[]){0xFFFFFC2D, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF}, c_p, c_p_inv, c_p_r2);
    montMul(z_inv2, z_inv, z_inv, c_p, c_p_inv);
    montMul(x_affine, Res.x, z_inv2, c_p, c_p_inv);
    montMul(x_affine, x_affine, one, c_p, c_p_inv);

    if (idx == 0) {
        print256("Affine X", x_affine);
    }

    for(int k=0; k<8; k++) if (x_affine[k] != r_val[k]) return false;
    return true;
}

__global__ void verifyBatchKernel(const SigTask* tasks, uint8_t* results, int numTasks) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= numTasks) return;
    results[idx] = verify_internal(&tasks[idx], idx) ? 1 : 0;
}

extern "C" int cudaVerifyBatch(const SigTask* h_tasks, int numTasks, uint8_t* h_results) {
    SigTask *d_tasks; uint8_t *d_results;
    cudaMalloc(&d_tasks, numTasks * sizeof(SigTask));
    cudaMalloc(&d_results, numTasks);
    cudaMemcpy(d_tasks, h_tasks, numTasks * sizeof(SigTask), cudaMemcpyHostToDevice);
    verifyBatchKernel<<<(numTasks+255)/256, 256>>>(d_tasks, d_results, numTasks);
    cudaDeviceSynchronize();
    cudaMemcpy(h_results, d_results, numTasks, cudaMemcpyDeviceToHost);
    cudaFree(d_tasks); cudaFree(d_results);
    return 0;
}
