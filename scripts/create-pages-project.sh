#!/bin/bash

# Create Cloudflare Pages project (one-time setup)
# Usage: ./create-pages-project.sh

set -e

# Check required environment variables
if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
    echo "Error: CLOUDFLARE_API_TOKEN environment variable not set"
    echo "Set it with: export CLOUDFLARE_API_TOKEN=your_token_here"
    exit 1
fi

# Create the project
echo "Creating Cloudflare Pages project: vorzimmerdrache"
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" npx wrangler pages project create vorzimmerdrache --production-branch=main

echo "Project created successfully!"
echo "You can now deploy using any of the deployment scripts."
