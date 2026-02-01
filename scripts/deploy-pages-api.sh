#!/bin/bash

# Deploy landing-page to Cloudflare Pages via direct API
# Usage: ./deploy-pages-api.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANDING_PAGE_DIR="$REPO_ROOT/landing-page"

# Check required environment variables
if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
    echo "Error: CLOUDFLARE_API_TOKEN environment variable not set"
    echo "Get your token at: https://dash.cloudflare.com/profile/api-tokens"
    echo "Required permissions: Account - Cloudflare Pages - Edit"
    exit 1
fi

if [[ -z "$CLOUDFLARE_ACCOUNT_ID" ]]; then
    echo "Error: CLOUDFLARE_ACCOUNT_ID environment variable not set"
    echo "Find your Account ID in the URL when logged into Cloudflare dashboard"
    echo "or at: https://dash.cloudflare.com -> Workers & Pages -> Overview"
    exit 1
fi

PROJECT_NAME="vorzimmerdrache"
API_BASE="https://api.cloudflare.com/client/v4"

echo "Creating deployment for project: $PROJECT_NAME"

# Create a temporary directory for the upload
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy files to temp directory
cp -r "$LANDING_PAGE_DIR"/* "$TEMP_DIR/"

# Create the upload
echo "Uploading files..."
DEPLOYMENT_RESPONSE=$(curl -s -X POST "$API_BASE/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$PROJECT_NAME/deployments" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"branch\": \"main\",
        \"commit_hash\": \"manual\",
        \"commit_message\": \"Manual deployment via API\"
    }" 2>&1)

if echo "$DEPLOYMENT_RESPONSE" | grep -q '"success":false'; then
    echo "Error creating deployment:"
    echo "$DEPLOYMENT_RESPONSE"
    exit 1
fi

# Extract upload URL from response
UPLOAD_URL=$(echo "$DEPLOYMENT_RESPONSE" | grep -o '"upload_url":"[^"]*"' | cut -d'"' -f4)

if [[ -z "$UPLOAD_URL" ]]; then
    echo "Error: Could not extract upload URL from response"
    echo "$DEPLOYMENT_RESPONSE"
    exit 1
fi

echo "Uploading files to: $UPLOAD_URL"

# Create and upload the zip file
ZIP_FILE="$TEMP_DIR/deployment.zip"
cd "$TEMP_DIR"
zip -r "$ZIP_FILE" . > /dev/null

UPLOAD_RESPONSE=$(curl -s -X PUT "$UPLOAD_URL" \
    -H "Content-Type: application/zip" \
    --data-binary "@$ZIP_FILE" 2>&1)

if echo "$UPLOAD_RESPONSE" | grep -q '"success":false'; then
    echo "Error uploading files:"
    echo "$UPLOAD_RESPONSE"
    exit 1
fi

echo "Deployment successful!"
echo "Check status at: https://dash.cloudflare.com/$CLOUDFLARE_ACCOUNT_ID/pages/view/$PROJECT_NAME"
