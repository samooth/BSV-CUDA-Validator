#!/bin/bash

# Generate .env if missing
if [ ! -f /app/.env ]; then
    echo "GPU_TOKEN=$(openssl rand -hex 32)" > /app/.env
    echo "Generated new GPU_TOKEN"
fi

# Export token for healthcheck compatibility
export GPU_TOKEN=$(cat /app/.env | grep GPU_TOKEN | cut -d= -f2)

# Start the app
exec node dist/validator.js