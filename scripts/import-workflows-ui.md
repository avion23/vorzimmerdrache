# Import Workflows via n8n UI (Older Versions)

## ✅ Workflows Ready to Import

All 4 workflows have Google Sheets Spreadsheet ID configured:
- ✅ `sms-opt-in.json` (37KB) - Complex 3-question SMS opt-in flow
- ✅ `roof-mode.json` (22KB) - Incoming call handler
- ✅ `timeout-handler.json` (7KB) - Timeout management
- ✅ `website-form-handler.json` (6.2KB) - Web form processing

## 📥 Step-by-Step Import

### 1. Open n8n UI

```
https://instance1.duckdns.org
```

### 2. Login/Create Account

- If first time: Create owner account
- Email: (deine Email aus der .env Datei)
- Password: (your choice)

### 3. Import Each Workflow

For **EACH** of the 4 workflows:

#### A. Start Import
1. Click **"Workflows"** in left sidebar
2. Click **"+ Add workflow"** (top right)
3. Click **"..."** menu (three dots) → **"Import from File"**

#### B. Select File
Navigate to:
```
/Users/avion/Documents.nosync/projects/meisteranruf/backend/workflows/
```

Import in this order:
1. **sms-opt-in.json** FIRST (most complex)
2. roof-mode.json
3. timeout-handler.json
4. website-form-handler.json

#### C. After Import
- You'll see the workflow canvas
- **DO NOT ACTIVATE YET** (credentials needed first)
- Click **"Save"** (top right)
- Repeat for remaining workflows

### 4. Configure Credentials

After importing all 4 workflows, set up credentials:

#### A. Google Sheets OAuth2

1. Click **Settings** (bottom left) → **Credentials**
2. Click **"Add Credential"**
3. Search: **"Google Sheets"**
4. Select: **"Google Sheets OAuth2 API"**
5. Fill in:
   - **Name**: `Google Sheets account` (EXACT NAME!)
   - Click **"Connect my account"**
   - Follow OAuth flow
   - Grant permissions
   - Click **"Save"**

#### B. Twilio API

1. Add Credential → Search **"Twilio"**
2. Select: **"Twilio API"**
3. Fill in:
   - **Name**: `Twilio API` (EXACT NAME!)
   - **Account SID**: `$TWILIO_ACCOUNT_SID` (aus .env)
   - **Auth Token**: `$TWILIO_AUTH_TOKEN` (aus .env)
   - Click **"Save"**

#### C. Telegram (Optional)

1. Add Credential → Search **"Telegram"**
2. Or use HTTP Request nodes with:
    - **Bot Token**: `$TELEGRAM_BOT_TOKEN` (aus .env)
    - **Chat ID**: `$TELEGRAM_CHAT_ID` (aus .env)

### 5. Verify Credentials in Workflows

For each workflow:

1. Open workflow
2. Check nodes with **credential icons**:
   - Google Sheets nodes → Should show "Google Sheets account"
   - Twilio nodes → Should show "Twilio API"
3. If **red error badge** appears:
   - Click the node
   - Select credential from dropdown
   - Click **"Save"**

### 6. Activate Workflows

**IMPORTANT**: Activate in this order:

1. **timeout-handler** (simplest, test activation)
2. **website-form-handler**
3. **roof-mode**
4. **sms-opt-in** (most complex, activate last)

For each:
1. Open workflow
2. Toggle **"Active"** switch (top right)
3. Confirm no errors
4. **Wait 5 seconds** between activations

### 7. Verify Webhooks Registered

After activation, check webhook paths are working:

```bash
# Test SMS opt-in webhook
curl -X POST https://instance1.duckdns.org/webhook-test/sms-response \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data "test=true"

# Should return 200 or execute workflow
```

### 8. Configure Twilio

In Twilio Console: https://console.twilio.com

1. Navigate to: **Phone Numbers** → Your number (aus .env: `$TWILIO_PHONE_NUMBER`)
2. Under **Voice & Fax**:
   - **A CALL COMES IN**: Webhook
   - URL: `https://instance1.duckdns.org/webhook/incoming-call`
   - HTTP: POST
3. Under **Messaging**:
   - **A MESSAGE COMES IN**: Webhook
   - URL: `https://instance1.duckdns.org/webhook/sms-response`
   - HTTP: POST
4. Click **"Save"**

## 🧪 Testing

### Test SMS Opt-In

```bash
curl -X POST https://instance1.duckdns.org/webhook/sms-response \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "X-Twilio-Signature: test" \
  --data "From=%2B4915112345678&Body=ja"
```

**Expected**: Workflow executes, responds with success message

### Test Roof Mode

Call the Twilio number: `+19135654323`

**Expected**:
- Immediate voice response
- SMS sent to caller
- Telegram notification received

### Check Execution History

In n8n:
1. Click **"Executions"** (left sidebar)
2. View recent executions
3. Check for errors (red badges)
4. Click execution to see detailed flow

## 🐛 Troubleshooting

### Workflow shows errors after import

**Issue**: Credentials not linked
**Fix**:
1. Open workflow
2. Click each red-badge node
3. Select credential from dropdown
4. Save workflow

### Activation fails

**Issue**: Webhook path already registered
**Fix**:
1. Deactivate ALL workflows
2. Wait 10 seconds
3. Activate one at a time

### Google Sheets "Invalid credentials"

**Issue**: OAuth token expired or wrong account
**Fix**:
1. Delete credential
2. Re-create with fresh OAuth flow
3. Use account that has access to spreadsheet

### Twilio webhook returns 404

**Issue**: Workflow not activated
**Fix**:
1. Check workflow is Active (green toggle)
2. Check webhook node has correct path
3. Restart n8n: `sudo docker restart vorzimmerdrache-n8n-1`

### Webhook timeout

**Issue**: Workflow taking too long
**Fix**:
1. Check execution logs
2. Optimize Code nodes
3. Add "Respond to Webhook" nodes earlier in flow

## ✅ Success Checklist

- [ ] All 4 workflows imported
- [ ] Google Sheets credential configured (OAuth successful)
- [ ] Twilio credential configured
- [ ] All workflows activated (green toggle)
- [ ] No red error badges on nodes
- [ ] Twilio webhooks configured
- [ ] Test SMS opt-in successful
- [ ] Test voice call successful
- [ ] Executions showing in history

## 📞 Next Steps

Once all workflows are active:

1. **Share Google Sheet** with service account (if using Service Account auth)
2. **Test real calls** to verify end-to-end flow
3. **Monitor executions** for first few hours
4. **Check Telegram** for notifications
5. **Review logs**: `sudo docker logs vorzimmerdrache-n8n-1`

## 🆘 Need Help?

If stuck:
1. Check n8n execution logs (UI → Executions)
2. Check Docker logs: `sudo docker logs vorzimmerdrache-n8n-1 --tail=100`
3. Check workflow validation: Open workflow → Look for red badges
4. Restart n8n: `sudo docker restart vorzimmerdrache-n8n-1`
