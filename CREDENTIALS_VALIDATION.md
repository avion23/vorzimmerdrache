# Google Sheets Credentials Validation Report

## ✅ VALIDATION PASSED

All Google Sheets nodes in `workflows/sms-opt-in.json` are correctly configured.

---

## Configuration Summary

### Nodes Analyzed
**Total Google Sheets nodes**: 7

**Operations used**:
- `update` (6 nodes)
- `lookup` (1 node)

---

## ✅ Spreadsheet ID Configuration

**Status**: ✅ **ALL CORRECT**

**Spreadsheet ID**: `1U73YUGk_GBWsAnM5LPjXpCT8bTXHYScuPoLumNdnfUY`

**All 7 nodes have correct structure**:
```json
{
  "sheetId": {
    "__rl": true,
    "mode": "url",
    "value": "1U73YUGk_GBWsAnM5LPjXpCT8bTXHYScuPoLumNdnfUY"
  }
}
```

**Verification**:
- ✅ `__rl: true` (Resource Locator format)
- ✅ `mode: "url"` (URL-based selection)
- ✅ `value` contains correct Spreadsheet ID
- ✅ Compatible with typeVersion 4

---

## ✅ Credentials Configuration

**Status**: ✅ **ALL CORRECT**

**Credential name**: `Google Sheets account`

**All 7 nodes have correct structure**:
```json
{
  "credentials": {
    "googleApi": {
      "id": "googleApi",
      "name": "Google Sheets account"
    }
  }
}
```

**Verification**:
- ✅ Credential type: `googleApi` (correct for Google Sheets OAuth2)
- ✅ Credential name: `Google Sheets account` (exact match required)
- ✅ All nodes reference same credential (consistent)

---

## Node Details

### 1. Google Sheets - Update Opt-In
- **Operation**: `update`
- **Spreadsheet ID**: ✅ Configured
- **Credentials**: ✅ Configured
- **TypeVersion**: 4

### 2. Google Sheets - Update Opt-Out
- **Operation**: `update`
- **Spreadsheet ID**: ✅ Configured
- **Credentials**: ✅ Configured
- **TypeVersion**: 4

### 3. Google Sheets - Lookup User
- **Operation**: `lookup`
- **Spreadsheet ID**: ✅ Configured
- **Credentials**: ✅ Configured
- **TypeVersion**: 4
- **Additional params**: `lookupColumn`, `lookupValue`

### 4. Google Sheets - Set Awaiting PLZ
- **Operation**: `update`
- **Spreadsheet ID**: ✅ Configured
- **Credentials**: ✅ Configured
- **TypeVersion**: 4

### 5. Google Sheets - Set Awaiting kWh
- **Operation**: `update`
- **Spreadsheet ID**: ✅ Configured
- **Credentials**: ✅ Configured
- **TypeVersion**: 4

### 6. Google Sheets - Set Awaiting Photo
- **Operation**: `update`
- **Spreadsheet ID**: ✅ Configured
- **Credentials**: ✅ Configured
- **TypeVersion**: 4

### 7. Google Sheets - Set Qualified Complete
- **Operation**: `update`
- **Spreadsheet ID**: ✅ Configured
- **Credentials**: ✅ Configured
- **TypeVersion**: 4

---

## What You Need to Do in n8n

### 1. Create the Credential (CRITICAL)

In n8n UI → **Settings → Credentials → Add Credential**:

**Type**: Google Sheets OAuth2 API

**Name**: `Google Sheets account` ⚠️ **EXACT NAME REQUIRED!**

**Configuration**:
- Click "Connect my account"
- Sign in with Google account that has access to the spreadsheet
- Grant permissions
- Save

### 2. Verify Spreadsheet Access

The spreadsheet `1U73YUGk_GBWsAnM5LPjXpCT8bTXHYScuPoLumNdnfUY` must be:

✅ **Shared** with the Google account you use for OAuth, OR
✅ **Owned** by the Google account you use for OAuth

**To verify access**:
1. Open: https://docs.google.com/spreadsheets/d/1U73YUGk_GBWsAnM5LPjXpCT8bTXHYScuPoLumNdnfUY/edit
2. Check you can view/edit
3. If not: Click "Share" → Add your OAuth Google account with "Editor" access

### 3. Expected Sheet Structure

The Google Sheet should have these columns for the workflows to work:

**Required columns**:
- `Phone` (for lookup)
- `OptIn_Status`
- `OptOut_Date`
- `conversation_state`
- `plz` (postal code)
- `kwh` (electricity consumption)

**Optional but recommended**:
- `Name`
- `Email`
- `Created_Date`
- `Last_Updated`

---

## Testing Checklist

After importing workflows and configuring credentials:

### Pre-Activation Tests

- [ ] Open each workflow in n8n
- [ ] Verify all Google Sheets nodes show green check (no red errors)
- [ ] Check credential dropdown shows "Google Sheets account"
- [ ] Save each workflow

### Post-Activation Tests

- [ ] Activate workflows one by one
- [ ] Test webhook manually:
  ```bash
  curl -X POST https://instance1.duckdns.org/webhook/sms-response \
    -d "From=+4915112345678&Body=ja"
  ```
- [ ] Check "Executions" tab for successful runs
- [ ] Verify data appears in Google Sheet

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| "Invalid credentials" | Wrong credential name | Must be exactly `Google Sheets account` |
| "Spreadsheet not found" | No access | Share spreadsheet with OAuth account |
| "Invalid value" | Wrong spreadsheet ID | Verify ID in URL matches workflow |
| Red error badge on node | Credential not selected | Open node → Select credential → Save |

---

## Validation Tools Used

✅ Manual jq inspection
✅ Structure verification (Resource Locator format)
✅ Credential name consistency check
✅ Spreadsheet ID presence verification
✅ TypeVersion compatibility check

---

## Conclusion

**All Google Sheets nodes are correctly configured** in the workflow JSON files.

**Next steps**:
1. Import workflows to n8n UI
2. Create "Google Sheets account" credential with OAuth
3. Verify spreadsheet access
4. Activate workflows
5. Test end-to-end

**No changes needed to workflow files** - they're ready to import as-is!

---

**Generated**: 2026-02-03
**Workflows validated**: sms-opt-in.json (7 nodes)
**Status**: ✅ READY FOR IMPORT
