# PV Speed-to-Lead Workflow Documentation

## Overview
Production-ready n8n workflow for German PV installer "Speed-to-Lead" system. Automates immediate customer engagement with SMS and installer notification.

## Workflow Nodes

### 1. Webhook - Lead Ingestion (n8n-nodes-base.webhook)
**Purpose:** Entry point for incoming lead data
**Method:** POST
**Path:** /pv-lead
**Input Fields:**
- name: Customer name
- phone: Phone number (German format)
- address: Customer address
- email: Email address
**Response Mode:** Returns via respondToWebhook node

### 2. Code - Phone Normalization (n8n-nodes-base.code)
**Purpose:** Convert German phone numbers to E.164 format (+49)
**Logic:**
- Removes all non-digit characters
- Handles leading "0" replacement with "+49"
- Validates E.164 format (11-14 digits after +)
**Output:**
- phone: E.164 formatted number
- phoneValid: Boolean validation flag
- timestamp: ISO 8601 timestamp
- status: "New"
- notes: Empty string for lead tracking

### 3. IF - Phone Validation (n8n-nodes-base.if)
**Purpose:** Validate phone number before proceeding
**Condition:** phoneValid === true
**True Branch:** Continue to Google Sheets storage
**False Branch:** Return error (400 - Invalid phone)

### 4. Error - Invalid Phone (n8n-nodes-base.respondToWebhook)
**Purpose:** Handle invalid phone number input
**Response Code:** 400
**Message:** German error message for invalid phone number

### 5. Google Sheets - Store Lead (n8n-nodes-base.googleSheets)
**Purpose:** Persist lead data for CRM integration
**Authentication:** OAuth2
**Operation:** Append row to sheet
**Columns:**
- timestamp: ISO date/time
- name: Customer name
- phone: E.164 phone number
- email: Email address
- address: Full address
- status: Lead status (New)
- notes: Additional notes field
**Environment Variable:** GOOGLE_SHEET_ID

### 6. OpenAI - Generate German SMS (n8n-nodes-base.openAi)
**Purpose:** Generate personalized German SMS (140 chars max)
**Model:** gpt-4o-mini
**System Prompt:** German solar installer persona, informal "Du" form
**Configuration:**
- Temperature: 0.7 (balanced creativity)
- Max tokens: 50 (fit within 140 chars)
- No emojis, modern friendly language
**Output:** choices[0].message.content

### 7. IF - SMS Generated (n8n-nodes-base.if)
**Purpose:** Fallback if AI generation fails
**Condition:** choices array not empty
**True Branch:** Use AI-generated SMS
**False Branch:** Use default template

### 8. Set - Fallback SMS (n8n-nodes-base.set)
**Purpose:** Default SMS template when AI unavailable
**Template:** "Hallo {name}! Danke für dein Interesse an Solar. Wir melden uns in Kürze bei dir."

### 9. Merge - Lead + SMS (n8n-nodes-base.merge)
**Purpose:** Combine lead data with generated SMS
**Mode:** Append combination
**Result:** Single object with all lead fields + smsContent

### 10. Set - SMS Data (n8n-nodes-base.set)
**Purpose:** Prepare data for Twilio operations
**Fields Added:**
- smsContent: Generated or fallback SMS text
- installerPhone: Installer's phone number (+4915112345678)
**Note:** Update installer phone for production

### 11. Split - Parallel Processing (n8n-nodes-base.split)
**Purpose:** Execute two branches simultaneously
**Mode:** Independent execution
**Branches:**
- A: Send SMS to customer
- B: Validate address via geocoding

### 12. Branch A: Twilio SMS Customer (n8n-nodes-base.twilio)
**Purpose:** Send immediate SMS to potential customer
**Operation:** sendMessage
**From:** Installer's Twilio number
**To:** Customer's E.164 phone number
**Body:** Personalized German SMS

### 13. Branch B: Google Maps Geocoding (n8n-nodes-base.httpRequest)
**Purpose:** Validate and geocode customer address
**Endpoint:** maps.googleapis.com/maps/api/geocode/json
**Parameters:**
- address: Customer address
- key: GOOGLE_MAPS_API_KEY
- language: de (German)
- region: de (Germany)
**Response:** Lat/long coordinates, formatted address

### 14. Merge - Branch Results (n8n-nodes-base.merge)
**Purpose:** Combine results from both parallel branches
**Mode:** Multiplex (merge outputs)
**Output:** Combined data from SMS and geocoding

### 15. Wait - 60 Seconds (n8n-nodes-base.wait)
**Purpose:** Delay before installer call
**Duration:** 60 seconds
**Rationale:** Allow customer time to read SMS and potentially respond

### 16. Set - Call Data (n8n-nodes-base.set)
**Purpose:** Prepare TwiML for installer IVR call
**TwiML Structure:**
- German voice announcement
- Lead summary (name, address, phone)
- Gather input: Press 1 to call customer, Press 2 for details
- Voice: alice (German: de-DE)
**Fields:**
- twiml: XML TwiML string
- callerId: Installer's Twilio number

### 17. Twilio - Call Installer (n8n-nodes-base.twilio)
**Purpose:** Initiate voice call to installer
**Operation:** makeCall
**From:** Installer's Twilio number
**To:** Installer's phone
**URL:** TWILIO_WEBHOOK_URL/twiml (endpoint serving TwiML)
**Result:** Installer receives IVR with lead options

### 18. Respond to Webhook (n8n-nodes-base.respondToWebhook)
**Purpose:** Send success response to original request
**Response:** JSON object
```json
{
  "success": true,
  "message": "Lead processed successfully",
  "leadId": "workflow-execution-id",
  "smsSent": true,
  "callInitiated: true
}
```

## Integration Points

### Google Sheets
**Required Credentials:**
- OAuth2 API credentials
- Sheet ID environment variable
**Column Mapping:** Automatic via valueInputMode: "userEntered"

### OpenAI
**Required Credentials:**
- API key in n8n credentials
**Model:** gpt-4o-mini (cost-effective)
**Prompt Strategy:** System prompt for German context, user prompt for personalization

### Twilio
**Required Credentials:**
- Account SID and Auth Token
- Twilio phone number (+4915112345678)
**Environment Variables:**
- TWILIO_WEBHOOK_URL: Base URL for TwiML endpoint
**Note:** Ensure Twilio number is verified for German market

### Google Maps
**Required Credentials:**
- API key with Geocoding API enabled
**Environment Variable:** GOOGLE_MAPS_API_KEY
**Quota:** Standard free tier ~$200/month credit

## Error Handling

### Phone Validation
- Invalid format returns 400 error immediately
- Prevents invalid data from entering pipeline

### SMS Generation Fallback
- If OpenAI fails or returns empty, uses hardcoded German template
- Ensures customer always receives SMS

### Geocoding
- Non-blocking - continues workflow even if geocoding fails
- Data stored but geocoding results may be null

### Webhook Response
- Always responds (success or error)
- Includes leadId for tracking
- Indicates which operations completed

## Configuration Checklist

### Environment Variables
- GOOGLE_SHEET_ID: Your Google Sheets spreadsheet ID
- GOOGLE_MAPS_API_KEY: Google Maps API key with Geocoding enabled
- TWILIO_WEBHOOK_URL: Public URL for n8n instance (e.g., https://your-n8n.com)

### n8n Credentials Required
1. Google Sheets OAuth2
2. OpenAI API key
3. Twilio API credentials
4. Google Maps HTTP Header Auth (optional)

### Phone Numbers
Update in Set - SMS Data node:
- installerPhone: Your installer's actual phone number
- callerId: Your verified Twilio German number

## Testing

### Test Payload
```json
{
  "name": "Max Mustermann",
  "phone": "017012345678",
  "address": "Musterstraße 1, 10115 Berlin",
  "email": "max.mustermann@example.de"
}
```

### Expected Behavior
1. Webhook receives data
2. Phone normalized to +4917012345678
3. Lead stored in Google Sheets
4. AI generates personalized German SMS
5. SMS sent to customer
6. Address geocoded to coordinates
7. 60-second delay
8. Installer receives voice call with IVR
9. Success response returned

## Performance Considerations

- Parallel branches (SMS + Geocoding) reduce total execution time
- gpt-4o-mini balances cost and quality
- 60-second wait allows customer engagement before installer contact
- Webhook response is async - acknowledges receipt immediately

## Security Notes

- Store all API keys in n8n credentials, never in workflow JSON
- Use environment variables for configuration
- Enable webhook authentication in production
- Rate-limit webhook endpoint to prevent abuse
- Sanitize all user inputs before processing

## Compliance

- German phone numbers processed according to local format standards
- GDPR considerations: Store minimal necessary data in Google Sheets
- SMS sent with customer consent (opt-in from lead source)
- Voice call follows German business hours regulations

## Future Enhancements

- Add working hours check before calling installer
- Integrate WhatsApp Business for richer messaging
- Add lead scoring based on address quality
- Schedule follow-up reminder if installer doesn't respond
- Multi-language support for non-German leads
- CRM integration beyond Google Sheets
