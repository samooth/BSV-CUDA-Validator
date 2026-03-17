#!/bin/bash

# Use existing GPU_TOKEN if provided (via docker-compose env_file)
if [ -n "$GPU_TOKEN" ]; then
    echo "Using GPU_TOKEN from environment"
    # Ensure .env file exists for any other tools that expect it
    echo "GPU_TOKEN=$GPU_TOKEN" > /app/.env
else
    # Generate .env if missing (and handle if docker created a directory)
    if [ -d /app/.env ]; then
        rm -rf /app/.env
    fi

    if [ ! -f /app/.env ]; then
        TOKEN=$(openssl rand -hex 32)
        echo "GPU_TOKEN=$TOKEN" > /app/.env
        echo "--------------------------------------------------------"
        echo "Generated new GPU_TOKEN: $TOKEN"
        echo "--------------------------------------------------------"
    fi
    export GPU_TOKEN=$(cat /app/.env | grep GPU_TOKEN | cut -d= -f2)
fi

# Start the app
exec node dist/validator.js