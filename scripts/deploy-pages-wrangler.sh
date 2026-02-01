#!/bin/bash

# Deploy landing-page to Cloudflare Pages using wrangler
# Usage: ./deploy-pages-wrangler.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Check required environment variables
if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
    echo "Error: CLOUDFLARE_API_TOKEN environment variable not set"
    echo "Set it with: export CLOUDFLARE_API_TOKEN=your_token_here"
    echo "Get your token at: https://dash.cloudflare.com/profile/api-tokens"
    exit 1
fi

# Deploy using wrangler with explicit environment variable
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" npx wrangler pages deploy landing-page --project-name=vorzimmerdrache

echo "Deployment successful!"
echo "Check at: https://dash.cloudflare.com/pages"
