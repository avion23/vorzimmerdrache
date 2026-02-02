# A/B Test Plan: Hero Section Messaging

## Goal
Determine which messaging strategy (Problem-focused vs. Benefit-focused) results in higher conversion rates for PV installers.

## Variants

### Variant A: Problem-Focused (Voss Style)
- **File**: `/landing-page/ab-test/variant-a.html`
- **Headline**: "Wie viele BAFA-Anträge sind Ihnen diesen Monat durch die Lappen gegangen?"
- **Lead**: Focuses on the frustration of missed calls, late-night phone work, and lost revenue. Validates the user's struggle ("Not your fault").
- **Psychology**: Loss aversion and empathy.

### Variant B: Benefit-Focused (Solution Style)
- **File**: `/landing-page/ab-test/variant-b.html`
- **Headline**: "Nie wieder Aufträge verlieren - während Sie auf dem Dach sind"
- **Lead**: Focuses on control, growth, and freedom. Highlights professional handling and WhatsApp summaries.
- **Psychology**: Empowerment and aspiration.

## Hypothesis
**Variant A will perform better.**
*Reasoning*: Handwerkers/Installers are currently in a high-stress environment with massive demand. The specific mention of "BAFA-Anträge" hits a precise pain point that signals "we understand your specific industry," creating higher trust and immediate relevance compared to a general benefit statement.

## Success Metrics
1. **Conversion Rate (Primary)**: Percentage of visitors who submit the contact form.
2. **CTR (Secondary)**: Percentage of visitors who click on any "Jetzt testen" or "Jetzt starten" button.
3. **Engagement**: Average time on page and scroll depth.

## Test Logistics
- **Duration**: 14 days (2 weeks) to account for weekly business cycles.
- **Traffic Split**: 50/50 randomized distribution.
- **Minimum Sample Size**: 500 visitors per variant (aiming for statistical significance).

## Implementation Options

### 1. Cloudflare Workers (Recommended)
Use a Worker to intercept requests to `index.html` and serve one of the two variants based on a cookie or random assignment. This prevents "flicker" (layout shift) and is extremely fast.

### 2. Google Optimize / VWO
Inject a script that swaps the headline and lead text dynamically. Easier to set up but can cause a slight delay in rendering the variant.

### 3. Server-Side Split
If the site is served via a backend (e.g., Node.js/Python), handle the split at the controller level and track the variant ID in the session.

---
**Prepared by**: Antigravity AI
**Date**: 2026-02-02
