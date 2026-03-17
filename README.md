# BSV CUDA Validator

GPU-accelerated BSV block validation using NVIDIA CUDA.

## Quick Start

```bash
# Setup
echo "GPU_TOKEN=$(openssl rand -hex 32)" > .env
docker compose up -d --build

# Test
curl http://localhost:8080/health
```

## API Endpoints

### GET /health

Check service status.

curl -X POST http://localhost:9090/verify/signatures \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(cat .env | cut -d= -f2)" \
  -d '{"tasks":[]}'

```bash
curl http://localhost:8080/health
```

**Response:**
```json
{"status":"ok","gpu":"NVIDIA GPU","timestamp":"2026-03-17T12:00:00Z"}
```

---
curl -X POST http://localhost:8080/verify/signatures \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer default_token_change_me" \
  -d '{
    "tasks": [
      {
        "hash": "788ba725e0d1f646a327b9b1facebfcbaab2646c5250677c04e38a4749e4c5a7",
        "sig": "30440220734a61fe19960e730dc6d131656b6a61154e50f286ce8f7f93d76a9f89d2e971022031892b4cebebbe58fccad4235a242f024371578c2689ca192268754dc86c1cba41",
        "pubKey": "0222cfa3253e2706e5a7d69785259d098c998e20d185ee515a2b9ad3177bca5b0f"
      }
    ]
  }'
### POST /verify/signatures

Batch verify ECDSA signatures.

```bash
curl -X POST http://localhost:8080/verify/signatures \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(cat .env | cut -d= -f2)" \
  -d '{
    "tasks": [
      {
        "hash": "0000000000000000000000000000000000000000000000000000000000000000",
        "sig": "3045022100...",
        "pubKey": "04..."
      }
    ]
  }'
```

**Response:**
```json
{"results":[true],"batchTimeMs":5,"count":1}
```

---

### POST /compute/merkle

Calculate Merkle root.

```bash
curl -X POST http://localhost:8080/compute/merkle \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(cat .env | cut -d= -f2)" \
  -d '{
    "txHashes": [
      "0000000000000000000000000000000000000000000000000000000000000000",
      "1111111111111111111111111111111111111111111111111111111111111111"
    ]
  }'
```

**Response:**
```json
{"merkleRoot":"58c3...","computationTimeMs":1,"txCount":2}
```

## Troubleshooting

**Driver mismatch:**
```bash
sudo apt install nvidia-driver-580 nvidia-utils-580
sudo reboot
```

**Check GPU:**
```bash
nvidia-smi
docker logs cuda-validator
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage CUDA + Node.js build |
| `docker-compose.yml` | Service orchestration |
| `cuda/*.cu` | GPU kernels (ECDSA, SHA-256) |
| `src/validator.ts` | HTTP API |
| `src/native/bsv_cuda.cc` | Node.js native addon |

## Environment

| Variable | Description |
|----------|-------------|
| `GPU_TOKEN` | API auth token (required) |
| `RPC_PORT` | HTTP port (default: 8080) |

## License

MIT