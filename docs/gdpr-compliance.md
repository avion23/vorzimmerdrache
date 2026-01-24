# GDPR Compliance

## Overview

This platform processes personal data including phone numbers, installation requests, and customer information. This document outlines GDPR compliance measures and data protection practices.

## Legal Basis for Processing

**Article 6(1)(f) GDPR - Legitimate Interests:**
- Processing installation requests for operational purposes
- Communicating with customers about their requests
- Providing status updates and notifications

**Article 6(1)(b) GDPR - Contract:**
- Fulfilling installation contracts
- Processing necessary contact information
- Managing scheduling and service delivery

**Article 6(1)(a) GDPR - Consent:**
- Optional marketing communications
- Data sharing with third parties (if applicable)

## Data Inventory

### Personal Data Collected

| Data Type | Source | Purpose | Retention | Storage Location |
|-----------|--------|---------|-----------|------------------|
| Phone Numbers | WhatsApp/Twilio | Customer communication | 3 years post-contract | PostgreSQL, Google Sheets |
| Names | Customer input | Identification | 3 years post-contract | Google Sheets |
| Addresses | Customer input | Installation location | 3 years post-contract | Google Sheets |
| Installation Dates | Scheduling system | Service delivery | 3 years post-contract | PostgreSQL, Google Sheets |
| Communication History | WhatsApp logs | Support, status updates | 3 years post-contract | PostgreSQL |
| Metadata (timestamps) | System logs | Auditing, troubleshooting | 1 year | PostgreSQL |

### Data Flow

```
Customer → WhatsApp/Twilio → n8n → Google Sheets
                ↓
            PostgreSQL (execution logs)
```

## Data Subject Rights

### Right to Information (Article 13-14 GDPR)

**Provided at Data Collection:**
- Identity and contact details
- Purpose of processing
- Legal basis
- Data retention period
- Right to lodge complaint
- Right to access, rectify, erase

**Implementation:**
- WhatsApp bot message: "Your data is processed for installation requests. View privacy policy at [URL]"
- Web form: Include privacy notice

### Right of Access (Article 15 GDPR)

**Process:**
1. Customer requests data access
2. Verify identity (phone number verification via WhatsApp)
3. Compile all personal data within 30 days
4. Provide in machine-readable format (JSON/CSV)

**Implementation:**
```javascript
// n8n workflow for DSAR
{
  "trigger": "webhook",
  "action": "Query Google Sheets by phone",
  "response": "Return customer data"
}
```

### Right to Rectification (Article 16 GDPR)

**Process:**
- Customer requests correction
- Verify identity
- Update in Google Sheets
- Confirm update to customer

**Implementation:**
- WhatsApp command: `/update <field> <value>`
- Manual update via n8n dashboard

### Right to Erasure (Right to be Forgotten) (Article 17 GDPR)

**Conditions:**
- Contract fulfilled and retention period expired
- Data no longer necessary for original purpose
- Customer withdraws consent (where applicable)
- Data processed unlawfully

**Process:**
1. Customer requests deletion
2. Verify identity
3. Anonymize/remove from Google Sheets (keep legal requirement records)
4. Remove from PostgreSQL logs
5. Confirm deletion

**Implementation:**
```javascript
// n8n workflow for deletion
{
  "trigger": "webhook",
  "action": "Anonymize in Google Sheets",
  "action": "Delete from PostgreSQL",
  "response": "Data deleted"
}
```

**Note:** Some data must be retained for legal/tax purposes (e.g., invoices).

### Right to Restrict Processing (Article 18 GDPR)

**Process:**
- Pause processing (except storage)
- Mark records as restricted
- Notify when restriction lifted

**Implementation:**
- Google Sheets column: `processing_status = 'restricted'`
- n8n workflow: Skip restricted records

### Right to Data Portability (Article 20 GDPR)

**Process:**
1. Customer requests data export
2. Verify identity
3. Export in structured format (JSON/CSV)
4. Provide via secure link or WhatsApp

### Right to Object (Article 21 GDPR)

**Process:**
- Customer objects to processing
- Verify identity
- Stop processing unless compelling legitimate grounds
- Document objection

## Data Retention Policy

### Retention Periods

| Data Type | Retention Period | Rationale |
|-----------|------------------|-----------|
| Customer Contact Info | 3 years post-contract | Warranty, legal requirements |
| Installation Records | 3 years post-contract | Tax, warranty, legal |
| Communication Logs | 3 years post-contract | Dispute resolution |
| Execution Logs (n8n) | 1 year | Technical troubleshooting |
| Error Logs | 6 months | System optimization |
| Anonymized Analytics | Indefinite | Business intelligence |

### Automated Data Deletion

**n8n Workflow (Scheduled Daily):**
```javascript
// Delete records older than 3 years
const cutoffDate = new Date();
cutoffDate.setFullYear(cutoffDate.getFullYear() - 3);

// Query Google Sheets
// Anonymize records older than cutoff
// Keep only: ID, dates, amounts (legal minimum)
```

**PostgreSQL Cleanup:**
```sql
-- Delete execution logs older than 1 year
DELETE FROM execution_entity
WHERE finishedAt < NOW() - INTERVAL '1 year';

-- Delete error logs older than 6 months
DELETE FROM workflow_statistics
WHERE createdAt < NOW() - INTERVAL '6 months';
```

## Data Minimization

### Principles

1. **Collect only necessary data**
   - Phone number: Required for communication
   - Address: Required for installation
   - Email: Optional (not collected unless provided)

2. **Use pseudonymization**
   - Hash phone numbers in logs
   - Use customer IDs instead of full names

3. **Avoid data hoarding**
   - Delete old logs automatically
   - Regular review of data fields

### Implementation

```javascript
// n8n node: Hash sensitive data
const crypto = require('crypto');
const hash = crypto.createHash('sha256').update(phoneNumber).digest('hex');
```

## Security Measures

### Technical Safeguards

1. **Encryption in Transit:**
   - TLS 1.3 for all connections (Traefik + Let's Encrypt)
   - HTTPS for webhooks
   - Encrypted WhatsApp connections (Waha)

2. **Encryption at Rest:**
   - PostgreSQL: Enable encryption (Hetzner disk encryption)
   - Google Sheets: Built-in Google encryption
   - n8n credentials: Encrypted using `N8N_ENCRYPTION_KEY`

3. **Access Control:**
   - Role-based access (admin, operator, viewer)
   - MFA recommended for admin accounts
   - SSH key authentication for Hetzner

4. **Audit Logging:**
   - All data access logged in n8n
   - Regular review of access logs
   - Alert on suspicious activity

### Organizational Measures

1. **Data Protection Officer (DPO):**
   - Designate responsible person
   - Document procedures
   - Handle DSAR requests

2. **Employee Training:**
   - GDPR awareness training
   - Data handling best practices
   - Incident response procedures

3. **Data Processing Agreement (DPA):**
   - Sign with all third-party services
   - Verify compliance:
     - Twilio: GDPR compliant (EU-US Privacy Shield successor)
     - Google Workspace: GDPR compliant
     - n8n Cloud: DPA available
     - Hetzner: GDPR compliant (German company)

## International Data Transfers

### Third-Party Services

| Service | Data Transferred | Location | Legal Basis |
|---------|-----------------|----------|-------------|
| Twilio | Phone numbers, messages | US | SCCs, EU-US Data Privacy Framework |
| Google Sheets | All customer data | EU/US | SCCs, EU-US Data Privacy Framework |
| n8n Cloud (optional) | Workflows, credentials | EU | GDPR compliant hosting |
| Hetzner | All data | Germany | EU (no transfer) |

### Data Privacy Framework

- Use European servers where possible (Hetzner)
- Ensure third parties have adequate safeguards
- Document transfer mechanisms
- Maintain SCCs (Standard Contractual Clauses)

## Breach Notification

### Detection and Response

1. **Immediate Actions (0-24 hours):**
   - Identify scope of breach
   - Contain the breach
   - Document incident

2. **Assessment (24-72 hours):**
   - Determine affected individuals
   - Assess risk to rights and freedoms
   - Prepare notification

3. **Notification (Within 72 hours):**
   - Notify supervisory authority (if high risk)
   - Notify affected individuals (if high risk)
   - Document all actions

### Incident Response Plan

```javascript
// n8n workflow for breach detection
{
  "trigger": "error_threshold",
  "condition": "error_rate > 10%",
  "action": "Notify admin via Telegram",
  "action": "Log incident to database"
}
```

### Communication Template

**Authority Notification:**
- Nature of breach
- Categories affected
- Number of individuals
- Consequences
- Measures taken
- Point of contact

**Individual Notification:**
- What happened
- What data was affected
- What we're doing
- What you can do
- Contact information

## Opt-Out Mechanism

### Communication Opt-Out

**WhatsApp:**
- Send: `/unsubscribe` or `STOP`
- Process:
  1. Add to suppression list
  2. Confirm via message
  3. No further marketing communications

**Implementation:**
```javascript
// n8n workflow for opt-out
{
  "trigger": "whatsapp message",
  "condition": "text === 'STOP'",
  "action": "Add to Google Sheets: phone_number, status = 'opted_out'",
  "action": "Reply: 'You have been opted out. Reply START to resubscribe.'",
  "action": "Log opt-out event"
}
```

### Marketing vs. Transactional

**Transactional (cannot opt-out):**
- Installation confirmations
- Status updates
- Delivery notifications

**Marketing (can opt-out):**
- Promotions
- Surveys
- Non-essential updates

**Resubscription:**
- Send: `/subscribe` or `START`
- Remove from suppression list
- Confirm via message

## Consent Management

### Explicit Consent Required For

- Marketing communications
- Data sharing with third parties (beyond necessary operations)
- Data processing beyond contract fulfillment

### Consent Implementation

**WhatsApp Opt-In:**
```
Welcome! By continuing, you agree to receive installation updates via WhatsApp.
To opt out, send STOP. Privacy Policy: [URL]
```

**n8n Webhook:**
- Capture consent timestamp
- Store in Google Sheets
- Link to consent version

## Data Protection Impact Assessment (DPIA)

### When Required

- High-risk processing
- Large-scale monitoring
- Processing special category data

### For This Platform

**Assessment:**
- Processing phone numbers and contact info
- Moderate risk
- No special category data
- Existing safeguards adequate

**Conclusion:**
- Full DPIA not required
- Documented in this GDPR compliance plan
- Regular review recommended

## Records of Processing Activities (ROPA)

### Template

| Processing Activity | Purpose | Categories | Recipients | Retention | Security |
|---------------------|---------|------------|------------|-----------|----------|
| Installation requests | Contract fulfillment | Phone, name, address | Staff, contractors | 3 years | Encryption, access control |
| WhatsApp communications | Service delivery | Phone numbers, messages | Twilio, WhatsApp | 3 years | TLS, pseudonymization |
| Status updates | Contract fulfillment | Installation data | Staff | 3 years | Encryption |
| Analytics | Business intelligence | Anonymized data | Internal | Indefinite | Aggregated only |

## Regular Review and Updates

### Review Schedule

- **Quarterly:** Review data retention, check logs for issues
- **Annually:** Full GDPR compliance audit, update documentation
- **On Changes:** When adding new features or data fields

### Version Control

- Store this document in Git
- Track changes with commit messages
- Review with DPO before major changes

## Training and Awareness

### Training Topics

1. GDPR fundamentals
2. Data handling procedures
3. Incident response
4. Customer interactions

### Materials

- Onboarding checklist
- Quick reference guide
- Incident response flowchart
- Regular updates via email/meetings

## External Resources

- **GDPR Text:** https://eur-lex.europa.eu/eli/reg/2016/679
- **EDPB Guidelines:** https://edpb.europa.eu
- **German DPA (BfDI):** https://www.bfdi.bund.de
- **Twilio GDPR:** https://www.twilio.com/legal/gdpr
- **Google GDPR:** https://cloud.google.com/security/gdpr

## Contact for Data Protection

**Data Protection Officer:**
- Name: [Your Name]
- Email: [dpo@yourdomain.com]
- Phone: [Your Phone]

**Supervisory Authority:**
- German: BfDI - Bundesbeauftragter für den Datenschutz und die Informationsfreiheit
- Website: https://www.bfdi.bund.de

---

**Last Updated:** 2025-01-24
**Next Review:** 2025-04-24
