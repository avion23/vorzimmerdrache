CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS consent_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  
  ip_address INET,
  user_agent TEXT,
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  
  consent_text TEXT NOT NULL,
  
  confirmed BOOLEAN DEFAULT FALSE,
  confirmed_at TIMESTAMPTZ,
  
  source VARCHAR(100) NOT NULL,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_consent_logs_lead_id ON consent_logs(lead_id);
CREATE INDEX idx_consent_logs_token ON consent_logs(id);
CREATE INDEX idx_consent_logs_confirmed ON consent_logs(confirmed);
CREATE INDEX idx_consent_logs_timestamp ON consent_logs(timestamp DESC);

CREATE UNIQUE INDEX idx_consent_logs_unique_pending ON consent_logs(lead_id) 
WHERE NOT confirmed AND timestamp > NOW() - INTERVAL '48 hours';

CREATE TRIGGER update_consent_logs_updated_at
  BEFORE UPDATE ON consent_logs
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE consent_logs IS 'GDPR-compliant double opt-in consent tracking for § 7 UWG compliance';
COMMENT ON COLUMN consent_logs.ip_address IS 'IP address at time of consent (required by German law)';
COMMENT ON COLUMN consent_logs.consent_text IS 'Exact consent text shown to user (required by German law)';
COMMENT ON COLUMN consent_logs.source IS 'Source of consent: website_form, phone_call, etc.';
COMMENT ON COLUMN consent_logs.confirmed IS 'True only after double opt-in confirmation';
