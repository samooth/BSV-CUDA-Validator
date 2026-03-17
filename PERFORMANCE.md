Expectations:

| Operation                   | CPU (single core) | GPU (RTX 3060)  | Speedup  |
| --------------------------- | ----------------- | --------------- | -------- |
| ECDSA verify                | ~2,000/sec        | ~200,000/sec    | **100x** |
| SHA-256 (64B)               | ~500,000/sec      | ~50,000,000/sec | **100x** |
| Merkle root (10k tx)        | ~50ms             | ~2ms            | **25x**  |
| Full block validation (1GB) | ~30 sec           | ~1 sec          | **30x**  |
