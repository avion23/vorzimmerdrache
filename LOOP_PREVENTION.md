# Loop Prevention Features

## Overview

To prevent the Vorzimmerdrache system from accidentally triggering itself (e.g., when the craftsman calls back a customer who also has the system), we've implemented two key protection mechanisms:

1. **Blacklist Function** - Block specific phone numbers
2. **Cooldown Period** - Limit SMS sends for repeated calls

---

## 1. Blacklist Function

### Purpose
Prevent the workflow from triggering when the craftsman calls from his own numbers.

### How It Works
- Checks if the caller's number is in a blacklist
- If blacklisted: Immediately hangs up without sending SMS
- If not blacklisted: Continues with normal workflow

### Configuration

**Environment Variable:** `BLACKLISTED_NUMBERS`

**Format:** Comma-separated list of phone numbers (E.164 format)

**Example:**
```bash
BLACKLISTED_NUMBERS=+491711234567,+49301234567,+4917654321
```

**Default Blacklisted Numbers:**
- `+491711234567` - Example: craftsman's mobile
- `+49301234567` - Example: craftsman's landline

**To Add Your Numbers:**
1. Edit `.env` file
2. Add your numbers to `BLACKLISTED_NUMBERS`
3. Restart n8n: `docker compose restart n8n`

---

## 2. Cooldown Period

### Purpose
Prevent multiple SMS sends (and associated costs) when the same customer calls repeatedly within a short time window.

### How It Works
- Tracks calls from each phone number
- **Cooldown window:** 5 minutes
- **Logic:**
  - First call within 5 minutes: Send SMS + Play voice message
  - Subsequent calls within 5 minutes: Play voice message only (no SMS)
  - After 5 minutes: Reset and allow SMS again

### Example Scenario

| Time | Call # | Action | SMS Sent? |
|------|--------|--------|-----------|
| 10:00 | 1st | SMS + Voice | ✅ Yes |
| 10:02 | 2nd | Voice only | ❌ No |
| 10:04 | 3rd | Voice only | ❌ No |
| 10:06 | 4th | SMS + Voice | ✅ Yes (cooldown expired) |

### Cost Savings
Without cooldown: 4 calls = 4 SMS = ~$0.20
With cooldown: 4 calls = 1 SMS = ~$0.05
**Savings: 75% on repeated calls**

---

## 3. Updated Workflow

The Roof-Mode workflow now includes:

1. **Parse Call** - Normalize phone number
2. **Check Blacklist** - Skip if blacklisted
3. **Check Cooldown** - Track call frequency
4. **IF - Should Send SMS** - Conditional SMS sending
5. **Log Call** - Record in Google Sheets
6. **Send SMS** - Only if not in cooldown
7. **TwiML Response** - Voice message (always)

### Workflow Diagram

```
Incoming Call
     ↓
Parse Call (normalize number)
     ↓
Check Blacklist
     ↓
[Blacklisted?] → YES → Hangup
     ↓ NO
Check Cooldown
     ↓
[Should Send SMS?] → YES → Log Call → Send SMS → Voice Response
     ↓ NO                           ↓
     └──────────────────────────────┘
                    ↓
            Voice Response Only
```

---

## 4. Configuration Files

### Updated Files

1. **`.env`** - Added `BLACKLISTED_NUMBERS`
2. **`docker-compose.yml`** - Added env var to n8n service
3. **`workflows/roof-mode-with-protection.json`** - New workflow with protection

### Deployment

```bash
# 1. Update configuration
scp .env docker-compose.yml ralf_waldukat@instance1.duckdns.org:/home/ralf_waldukat/vorzimmerdrache/

# 2. Restart n8n
ssh ralf_waldukat@instance1.duckdns.org "cd /home/ralf_waldukat/vorzimmerdrache && docker compose restart n8n"

# 3. Import new workflow via n8n UI or CLI
```

---

## 5. Testing

### Test Blacklist
```bash
curl -X POST https://instance1.duckdns.org/webhook/incoming-call \
  -d "From=+491711234567" \
  -d "To=+19135654323"
# Expected: Hangup immediately, no SMS
```

### Test Cooldown
```bash
# First call - should send SMS
curl -X POST https://instance1.duckdns.org/webhook/incoming-call \
  -d "From=+491999888777" \
  -d "To=+19135654323"

# Second call within 5 minutes - no SMS
curl -X POST https://instance1.duckdns.org/webhook/incoming-call \
  -d "From=+491999888777" \
  -d "To=+19135654323"
```

---

## 6. Monitoring

### Check Cooldown State
The cooldown tracking is stored in workflow static data. To view:
1. Go to n8n UI
2. Open Roof-Mode workflow
3. Check execution data for `callTracking` object

### Google Sheets Logging
The Call_Log sheet now includes:
- `phone` - Caller number
- `timestamp` - Call time
- `status` - Call status (missed)
- `sms_sent` - Whether SMS was sent (true/false)

---

## 7. Troubleshooting

### Issue: Blacklist not working
**Solution:** Check `BLACKLISTED_NUMBERS` format (must be E.164 with + prefix)

### Issue: Cooldown too short/long
**Solution:** Edit `Check Cooldown` node in workflow, change `cooldownMinutes` variable

### Issue: SMS not sending at all
**Solution:** Check Twilio credentials and `TWILIO_PHONE_NUMBER` env var

---

## 8. Future Enhancements

Possible improvements:
- **Dynamic blacklist** - Manage via web UI
- **SMS quota** - Daily/weekly limits per number
- **Smart cooldown** - Adaptive based on customer behavior
- **Analytics** - Track cost savings from cooldown

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-01  
**Author:** opencode
