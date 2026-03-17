# BSV CUDA Validator

GPU-accelerated BSV block validation using NVIDIA CUDA. Optimized for high-throughput Bitcoin SV signature verification and Merkle tree computation.

## Quick Start

```bash
# 1. Setup environment locally
echo "GPU_TOKEN=$(openssl rand -hex 32)" > .env

# 2. Sync and Deploy to Server
# (Ensure .env.sync is configured with your server details)
npm run sync:deploy

# 3. Verify on Server
curl -H "Authorization: Bearer $(cat .env | cut -d= -f2)" http://localhost:8080/health
```

## API Endpoints

### 1. Batch Signature Verification
`POST /verify/signatures`

Verifies Secp256k1 signatures using GPU parallelism.

**Example (Known Valid Case):**
```bash
curl -X POST http://localhost:8080/verify/signatures \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(cat .env | cut -d= -f2)" \
  -d '{
    "tasks": [
      {
        "hash": "3d2117bc943ba3863e3385af09536b32c5103b20f472e7f93ac75150c0e1c8fb",
        "sig": "3045022100d5404371bb627e481dd118bb2ff0982ef2330a122b639f0c4cd3287071efea90022035aa1b9a075651a4cc6fe4b8fb88bd725310bc575d171a6f9d37ba9e193c7b7a",
        "pubKey": "04a34b99f22c790c4e36b2b3c2c35a36db06226e41c692fc82b8b56ac1c540c5bd5b8dec5235a0fa8722476c7709c02559e3aa73aa03918ba2d492eea75abea235"
      }
    ]
  }'
```

### 2. Merkle Root Computation
`POST /compute/merkle`

Calculates double-SHA256 Merkle root.

```bash
curl -X POST http://localhost:8080/compute/merkle \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(cat .env | cut -d= -f2)" \
  -d '{
    "txHashes": [
      "f68255748d703b75d3495f4d29c62c1cf687e998301e7c1639245ee24959a13b",
      "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    ]
  }'
```

## Tools

### Generating Test Data
You can generate new valid signatures for testing using:
```bash
node tests/generate_valid.js
```

### Checking Signatures on CPU
To verify if a signature is valid according to standard libraries:
```bash
node tests/check_sig.js
```

## Optimizations
- **Montgomery Arithmetic**: High-speed modular multiplication.
- **Shamir's Trick**: Combined $u_1G + u_2Q$ calculation (~30% faster).
- **Jacobian Coordinates**: Optimized for Secp256k1 ($a=0$).
- **Strict Low-S**: Mandatory for Bitcoin SV compatibility.

## Donations
If you find this GPU validator useful, feel free to support the development:
- **HandCash**: [handcash.me/samooth](https://handcash.me/samooth)
- **BSV Address**: `samooth@handcash.io`

## License
MIT
