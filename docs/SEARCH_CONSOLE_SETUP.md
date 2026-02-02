# Google Search Console Setup Guide: VorzimmerDrache

This guide provides step-by-step instructions for configuring Google Search Console (GSC) for the VorzimmerDrache landing page to monitor search performance and improve SEO.

## 1. Prerequisites

Before starting, ensure you have:
- **Google Account:** Access to a Google account to manage the property.
- **Domain Access:** Ability to modify the codebase or DNS settings for `vorzimmerdrache.pages.dev`.
- **Live URL:** The site is currently accessible at [https://9369c8cb.vorzimmerdrache.pages.dev](https://9369c8cb.vorzimmerdrache.pages.dev) (and eventually the main production domain).

## 2. Step-by-Step Setup

### Step 2.1: Add Property
1. Go to the [Google Search Console](https://search.google.com/search-console/about).
2. Click the property selector (top left) and choose **"Add property"**.
3. **Choose Property Type:**
   - **URL prefix (Recommended for Cloudflare Pages):** Enter `https://vorzimmerdrache.pages.dev/`.
   - *Note: Domain verification requires DNS changes which might be slower to propagate.*

### Step 2.2: Verification Methods
Google needs to verify that you own the site.

**Recommended: HTML Tag Verification**
1. In GSC, select **HTML tag** under "Other verification methods".
2. Copy the `<meta name="google-site-verification" content="..." />` tag.
3. Open `/landing-page/index.html` in your editor.
4. Paste the tag inside the `<head>` section.
5. Deploy the changes to Cloudflare Pages.
6. Return to GSC and click **Verify**.

**Alternative: Google Analytics**
- If Google Analytics (GA4) is already installed on the page, GSC can verify ownership automatically if you use the same Google account.

## 3. Configuration

### Step 3.1: Submit Sitemap
1. In the GSC sidebar, go to **Indexing > Sitemaps**.
2. Under "Add a new sitemap", enter `sitemap.xml`.
3. Click **Submit**.
4. *Verify that the status turns to "Success".*

### Step 3.2: Set Preferred Domain
Google now handles "www vs non-www" automatically via canonical tags. Ensure `index.html` contains:
`<link rel="canonical" href="https://vorzimmerdrache.pages.dev/" />`

### Step 3.3: Target Country
1. GSC uses the language of the content and backlinks to determine target audience.
2. Since the content is in German, Google will naturally prioritize Germany.
3. Ensure the `<html>` tag in `index.html` has `lang="de"`.

## 4. Monitoring Checklist

Regularly check these reports in the GSC sidebar:
- **Performance:** Monitor Clicks, Impressions, CTR, and Average Position. Look for keywords where the site is appearing.
- **Indexing (Coverage):** Ensure your main pages are indexed. Address any "Excluded" pages that should be live.
- **Experience:**
  - **Core Web Vitals:** Check LCP, FID/INP, and CLS scores.
  - **Mobile Usability:** Ensure there are no "Text too small" or "Clickable elements too close" errors.
- **Security & Manual Actions:** Verify the site is "clean" and not penalized.

## 5. SEO Actions

- **Request Indexing:** After major updates, go to the "URL inspection" tool, paste the URL, and click **Request Indexing**.
- **Email Alerts:** Ensure notifications are enabled (default) to receive alerts for new issues or spikes in errors.
- **Crawl Errors:** Monitor "Indexing" reports for 404s or server errors that might block Googlebot.

## 6. Troubleshooting

### URL Not Indexed
- **Symptom:** "URL is not on Google" in Inspection Tool.
- **Fix:** 
  1. Check if `robots.txt` is blocking the page (should not exist or should allow all).
  2. Ensure no `<meta name="robots" content="noindex">` exists.
  3. Use "Request Indexing".

### Verification Failed
- **Symptom:** GSC cannot find the HTML tag.
- **Fix:** Verify the site is deployed and the tag is visible in the page source (`Ctrl+U` in browser). Check for caching issues on Cloudflare.

---
*Created on: 2026-02-02*
