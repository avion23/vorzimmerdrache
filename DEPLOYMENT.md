# Cloudflare Pages Deployment Guide

## Method 1: GitHub Actions (Recommended, Automated)

### Setup

1. **Create Cloudflare API Token:**
   - Go to: https://dash.cloudflare.com/profile/api-tokens
   - Click "Create Token"
   - Use "Edit Cloudflare Workers" template
   - Required permissions:
     - Account > Cloudflare Pages > Edit
   - Set zone resources to "Include > All zones"

2. **Add GitHub Secrets:**
   ```bash
   # In your GitHub repo settings, add these secrets:
   # Settings > Secrets and variables > Actions > New repository secret

   CLOUDFLARE_API_TOKEN = <your-token-from-step-1>
   CLOUDFLARE_ACCOUNT_ID = <your-account-id>
   ```

3. **Find your Account ID:**
   - Go to: https://dash.cloudflare.com
   - Click "Workers & Pages"
   - Copy from URL or "Get your API token" section

4. **Push to deploy:**
   ```bash
   # Any push to main branch with landing-page changes triggers deployment
   git add landing-page/
   git commit -m "Update landing page"
   git push origin main
   ```

5. **Manual trigger:**
   - Go to: https://github.com/avion23/vorzimmerdrache/actions
   - Select "Deploy to Cloudflare Pages"
   - Click "Run workflow"

---

## Method 2: Direct API Deployment

### Quick Start

```bash
# Set environment variables
export CLOUDFLARE_API_TOKEN="your_token_here"
export CLOUDFLARE_ACCOUNT_ID="your_account_id_here"

# Run the deployment script
./scripts/deploy-pages-api.sh
```

### Get Credentials

- **API Token:** https://dash.cloudflare.com/profile/api-tokens
  - Create token with "Account > Cloudflare Pages > Edit" permission

- **Account ID:** https://dash.cloudflare.com
  - URL path: `/pages/view/<account-id>`
  - Or: Workers & Pages > Overview

---

## Method 3: Wrangler CLI Deployment

### Quick Start

```bash
# Set environment variable (must be exported, not just set)
export CLOUDFLARE_API_TOKEN="your_token_here"

# Run the deployment script
./scripts/deploy-pages-wrangler.sh
```

### Why This Works

The script explicitly passes `CLOUDFLARE_API_TOKEN` to npx wrangler:
```bash
CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" npx wrangler pages deploy ...
```

This ensures the token is available in the subprocess environment.

---

## Method 4: Manual Dashboard Upload

### Steps

1. **Create deployment package:**
   ```bash
   cd /Users/avion/Documents.nosync/projects/vorzimmerdrache/landing-page
   zip -r ../landing-page.zip .
   ```

2. **Upload via Cloudflare Dashboard:**
   - Go to: https://dash.cloudflare.com
   - Navigate to: Workers & Pages
   - Click: "Create application" > "Pages" > "Upload assets"
   - Drag and drop `landing-page.zip`
   - Enter project name: `vorzimmerdrache`
   - Click "Deploy site"

3. **For updates:**
   - Go to: https://dash.cloudflare.com > Workers & Pages > vorzimmerdrache
   - Click: "Create deployment" > "Upload assets"
   - Upload new zip file

---

## Environment Variables Reference

Add to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
# Cloudflare Pages Deployment
export CLOUDFLARE_API_TOKEN="your_api_token_here"
export CLOUDFLARE_ACCOUNT_ID="your_account_id_here"
```

Or use a `.env` file (don't commit this):
```bash
# .env.local
CLOUDFLARE_API_TOKEN=your_api_token_here
CLOUDFLARE_ACCOUNT_ID=your_account_id_here
```

---

## Verification

After deployment, verify at:
- **Dashboard:** https://dash.cloudflare.com/<account-id>/pages/view/vorzimmerdrache
- **Live URL:** https://vorzimmerdrache.pages.dev (or your custom domain)

---

## Troubleshooting

### "API token invalid"
- Verify token has "Cloudflare Pages > Edit" permission
- Check token hasn't expired
- Ensure you're using the correct account ID

### "Project not found"
- First deployment requires creating the project
- Use wrangler: `npx wrangler pages project create vorzimmerdrache`
- Or upload via dashboard once to initialize

### "Environment variable not set"
- Ensure variables are **exported**, not just set
- Use: `export CLOUDFLARE_API_TOKEN=...` (not just `CLOUDFLARE_API_TOKEN=...`)
- Check with: `echo $CLOUDFLARE_API_TOKEN`

### GitHub Actions fails
- Verify secrets are set in repo settings
- Check workflow logs for specific error
- Ensure token has correct permissions
