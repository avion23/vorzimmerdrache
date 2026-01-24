CREATE TABLE IF NOT EXISTS enrichment_data (
  lead_id UUID PRIMARY KEY REFERENCES leads(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  address_validated BOOLEAN DEFAULT FALSE,
  address_formatted TEXT,
  address_city TEXT,
  address_state TEXT,
  address_country TEXT DEFAULT 'Germany',
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  location_type VARCHAR(50),

  roof_area_sqm DECIMAL(10, 2),
  roof_type VARCHAR(50),
  panel_orientation VARCHAR(50),
  max_panels INTEGER,
  estimated_capacity_kw DECIMAL(6, 2),
  estimated_annual_kwh INTEGER,
  solar_irradiance DECIMAL(6, 2),

  data_source JSONB,
  confidence VARCHAR(20),

  notes TEXT
);

CREATE TABLE IF NOT EXISTS lead_scores (
  lead_id UUID PRIMARY KEY REFERENCES leads(id) ON DELETE CASCADE,
  lead_score INTEGER NOT NULL CHECK (lead_score >= 0 AND lead_score <= 100),
  priority VARCHAR(20) NOT NULL CHECK (priority IN ('critical', 'high', 'medium', 'low')),
  score_category VARCHAR(20) NOT NULL CHECK (score_category IN ('hot-lead', 'qualified', 'warm-lead', 'cold-lead')),
  breakdown JSONB NOT NULL,
  calculated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_enrichment_lead_id ON enrichment_data(lead_id);
CREATE INDEX IF NOT EXISTS idx_enrichment_state ON enrichment_data(address_state);
CREATE INDEX IF NOT EXISTS idx_enrichment_roof_area ON enrichment_data(roof_area_sqm);

CREATE INDEX IF NOT EXISTS idx_lead_scores_score ON lead_scores(lead_score DESC);
CREATE INDEX IF NOT EXISTS idx_lead_scores_priority ON lead_scores(priority);
CREATE INDEX IF NOT EXISTS idx_lead_scores_category ON lead_scores(score_category);

CREATE TRIGGER update_enrichment_updated_at
  BEFORE UPDATE ON enrichment_data
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE enrichment_data IS 'Enriched lead data from external APIs (geocoding, solar estimates)';
COMMENT ON TABLE lead_scores IS 'Lead scoring results for prioritization';
COMMENT ON COLUMN lead_scores.breakdown IS 'JSON with individual factor scores: location, roofSize, urgency, contactQuality, responseTime, budget';
