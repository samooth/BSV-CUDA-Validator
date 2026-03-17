# NPM Packaging TODO

This list tracks the changes required to transform this standalone project into a distributable NPM package.

## 1. Project Structure
- [ ] Add `"files": ["dist", "build/Release/bsv_cuda.node", "cuda/libbsv_cuda.so", "src/native/bsv_cuda.d.ts"]` to `package.json`.
- [ ] Set `"main": "dist/validator.js"` and `"types": "dist/validator.d.ts"`.
- [ ] Move `src/native/bsv_cuda.d.ts` to `dist/` or ensure it's properly referenced.

## 2. Build Automation
- [ ] Create a unified `npm run build` that:
    1. Checks for `nvcc` (CUDA Compiler).
    2. Runs `cd cuda && make`.
    3. Runs `node-gyp rebuild`.
    4. Runs `tsc`.
- [ ] Implement a `postinstall` script to attempt a local build on the user's machine.

## 3. Native Addon Portability
- [ ] Update `binding.gyp` to use dynamic relative paths for `libbsv_cuda.so` using `<(module_root_dir)`.
- [ ] Investigate `prebuild` or `prebuild-install` to ship binaries for common platforms (Linux x64).
- [ ] Fix RPATH in `binding.gyp` to ensure the `.node` file can find the `.so` regardless of install location.

## 4. Feature Enhancements
- [ ] Implement "Graceful Degradation": if GPU is not found, fallback to a JavaScript or C++ CPU implementation of Secp256k1.
- [ ] Add a CLI wrapper so users can run `npx bsv-cuda-validator --port 8080`.

## 5. CI/CD
- [ ] Set up GitHub Actions with a GPU-enabled runner to verify the full build and test pipeline.
- [ ] Automated publishing to NPM registry on tagged releases.
