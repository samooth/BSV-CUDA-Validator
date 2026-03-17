# BSV CUDA Validator: Technical Architecture

This document describes the low-level implementation details of the high-performance ECDSA verification engine.

## 1. BigInt Representation
The system uses a **256-bit BigInt** representation split into eight 32-bit unsigned integers (`limbs[8]`).

*   **Memory Layout**: LSB-first (Least Significant Byte first).
*   **Limb 0**: Contains the lowest 32 bits (bits 0-31).
*   **Limb 7**: Contains the highest 32 bits (bits 224-255).

This architecture is optimized for modern NVIDIA GPUs, allowing for efficient use of the `add.cc.u32` and `addc.u32` PTX instructions.

## 2. Field Arithmetic (Montgomery)
To avoid expensive modular reduction (division), all field operations ($GF(p)$ and $GF(n)$) are performed in the **Montgomery Domain**.

*   **Conversion**: Integers are converted to the Montgomery domain by multiplying by $R^2 \pmod m$, where $R = 2^{256}$.
*   **Multiplication**: We use a **Product-Sum Montgomery Multiplication** algorithm. This reduces the modular reduction to simple additions and shifts.
*   **Inversion**: Modular inversion is performed using **Fermat's Little Theorem** ($a^{p-2} \pmod p$) implemented via Montgomery Exponentiation.

## 3. Elliptic Curve Arithmetic
The validator implements the **Secp256k1** curve ($y^2 = x^3 + 7$) using **Jacobian Coordinates**.

### Jacobian Coordinates $(X, Y, Z)$
In Jacobian coordinates, the affine point $(x, y)$ is represented as $(X/Z^2, Y/Z^3, Z)$. 
*   **Benefit**: This eliminates the need for modular inversion during point addition and doubling. We only perform a single inversion at the very end of the scalar multiplication.
*   **Optimization**: Since Secp256k1 has $a=0$, the doubling formula is significantly simplified, reducing the total number of multiplications required per bit.

### Shamir's Trick
For ECDSA, we need to compute $P = u_1G + u_2Q$. 
Instead of performing two independent scalar multiplications (which would take $2 \times 256$ doublings), we use **Shamir's Trick**:
1.  Precompute $G+Q$.
2.  Process bits of $u_1$ and $u_2$ simultaneously.
3.  Perform only **one** set of doublings (256 total).
4.  Add $G$, $Q$, or $G+Q$ based on the bit pair $(b_1, b_2)$.
**Result**: ~30-40% reduction in total EC operations.

## 4. Bitcoin SV Optimizations

### High-Throughput Batching
The kernel is designed for **massive batching**. A single CUDA kernel call can verify thousands of signatures in parallel.
*   **Grid Mapping**: Each thread processes a single signature task.
*   **Memory Coalescing**: `SigTask` structures are packed to ensure efficient global memory access.

### Strict Low-S Compliance
Bitcoin SV requires that the $s$ value of a signature be in the lower half of the curve order $n$. The validator performs a strict limb-by-limb check before starting the EC math to fail early on non-compliant signatures.

### Compressed Point Recovery
The engine supports on-the-fly recovery of the $y$ coordinate from 33-byte compressed public keys. This involves calculating the modular square root in $GF(p)$ using the property $p \equiv 3 \pmod 4$.

## 5. Integration Layer
The bridge between Node.js and CUDA is handled by a C++ native addon using **NAN**.
*   **Zero-Copy Strategy**: Wherever possible, we minimize memory copies between the V8 heap and the GPU device.
*   **Hex Decoding**: The native layer decodes hex strings directly into `SigTask` structs to keep the Node.js event loop free for handling API requests.
