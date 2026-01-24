CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Contact Info
  name VARCHAR(255) NOT NULL,
  phone VARCHAR(20) NOT NULL,
  email VARCHAR(255),

  -- Address (normalized)
  address_raw TEXT,
  address_street VARCHAR(255),
  address_city VARCHAR(100),
  address_postal_code VARCHAR(10),
  address_state VARCHAR(50),
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),

  -- Status
  status VARCHAR(50) DEFAULT 'new',
  priority INTEGER DEFAULT 0,

  -- Compliance
  opted_in BOOLEAN DEFAULT FALSE,
  opted_out BOOLEAN DEFAULT FALSE,
  opted_out_at TIMESTAMPTZ,

  -- Solar Specific
  roof_area_sqm INTEGER,
  estimated_kwp DECIMAL(5, 2),
  estimated_annual_kwh INTEGER,
  subsidy_eligible BOOLEAN,

  -- Metadata
  source VARCHAR(100),
  notes TEXT,
  assigned_to VARCHAR(100),

  -- GDPR
  gdpr_delete_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_leads_phone ON leads(phone);
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_created_at ON leads(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leads_email ON leads(email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_leads_gdpr_delete ON leads(gdpr_delete_at) WHERE gdpr_delete_at IS NOT NULL;

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_leads_updated_at
  BEFORE UPDATE ON leads
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TYPE lead_status AS ENUM (
  'new',
  'qualified',
  'contacted',
  'meeting',
  'offer',
  'won',
  'lost'
);

COMMENT ON TABLE leads IS 'CRM leads table migrated from Google Sheets';
COMMENT ON COLUMN leads.priority IS '0=normal, 1=high, 2=urgent';
COMMENT ON COLUMN leads.source IS 'website, phone, referral, etc.';
COMMENT ON COLUMN leads.gdpr_delete_at IS 'Auto-delete after 12 months (GDPR compliance)';
