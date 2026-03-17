NVCC = nvcc
CUDA_ARCH = -arch=sm_86
NVCC_FLAGS = -O3 -Xcompiler -fPIC -shared

TARGET = libbsv_cuda.so
SOURCES = ecdsa_verify.cu sha256_merkle.cu script_validate.cu

$(TARGET): $(SOURCES)
	$(NVCC) $(CUDA_ARCH) $(NVCC_FLAGS) -o $@ $^

clean:
	rm -f $(TARGET) *.o

.PHONY: clean