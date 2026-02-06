# Race Condition Protection Implementation

## Problem
The original workflow used Google Sheets as a real-time state database. When two SMS arrived simultaneously:
1. SMS 1 reads state "empty"
2. SMS 2 reads state "empty" (before SMS 1 writes)
3. SMS 1 writes state "awaiting_plz"
4. SMS 2 overwrites with state "awaiting_plz"

This caused lost updates and inconsistent conversation states.

## Solution Implemented

### 1. MessageSid Deduplication (sms-opt-in.json)
Added extraction of Twilio's `MessageSid` in the "Code - Parse SMS" node:
- Each SMS has a unique MessageSid
- Check if this MessageSid was already processed
- Skip duplicate processing

### 2. Timestamp-Based Race Detection
Added `processingTimestamp` to track when SMS was received:
- If last update was < 5 seconds ago, flag as potential race condition
- Allows for retry logic or manual review

### 3. Updated State Extraction Node
Renamed "Code - Extract State" to "Code - Extract State + Deduplication":
- Checks for duplicate MessageSid
- Checks for rapid successive updates (potential race)
- Returns flags for workflow routing

## Required Google Sheets Schema Updates

Add these columns to your Google Sheet:

| Column Name | Purpose |
|-------------|---------|
| `last_message_sid` | Stores the last processed Twilio MessageSid |
| `last_processed_at` | ISO timestamp of last update |

## Remaining Work (Manual Steps)

1. **Add IF Node for Duplicate Check**
   - After "Code - Extract State + Deduplication"
   - Check: `isDuplicate = true` OR `isPotentialRace = true`
   - If true: Send response and exit
   - If false: Continue to "Switch - State Router"

2. **Update Google Sheets Nodes**
   All update nodes must include:
   ```json
   "last_message_sid": "={{ $json.messageSid }}"
   "last_processed_at": "={{ $json.processingTimestamp }}"
   ```

3. **Add Duplicate Response Node**
   - Respond with: "Nachricht wird bereits verarbeitet."
   - HTTP 200 (to prevent Twilio retries)

## Files Modified

- `backend/workflows/sms-opt-in.json`:
  - Updated "Code - Parse SMS" to extract MessageSid and timestamp
  - Renamed and updated "Code - Extract State" to include deduplication logic

## Validation Already Exists

The review incorrectly stated "no strict validation". The workflow already has:
- **PLZ**: `/^\d{5}$/` - strict 5-digit validation
- **kWh**: `!isNaN(numValue) && numValue > 0` - positive number validation  
- **Photo**: `numMedia > 0` - requires at least one media attachment

## Alternative: SQLite State Management

For stronger consistency guarantees, consider:
1. Using n8n's built-in SQLite for state storage
2. Or implementing a Redis cache layer
3. Or using Google Sheets only as a log, not as state storage

However, for an MVP with low concurrent usage, the MessageSid deduplication + timestamp approach is sufficient.
