#!/bin/bash
export $(cat .env.sync | xargs)

echo "Syncing test file..."
rsync -avzc -e "ssh -p $SSH_PORT" cuda/test_math.cu $REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/cuda/

echo "Compiling and running on remote GPU (via Docker)..."
ssh -p $SSH_PORT $REMOTE_USER@$REMOTE_HOST "cd $REMOTE_DIR/cuda && docker run --rm --gpus all -v \$(pwd):/cuda -w /cuda nvidia/cuda:13.0.0-devel-ubuntu24.04 bash -c 'nvcc -arch=sm_86 -O3 test_math.cu -o test_math && ./test_math'"
