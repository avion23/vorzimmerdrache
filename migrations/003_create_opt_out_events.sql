CREATE TABLE IF NOT EXISTS opt_out_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID REFERENCES leads(id) ON DELETE SET NULL,
  channel VARCHAR(20) NOT NULL,
  keyword_used VARCHAR(50) NOT NULL,
  timestamp TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_opt_out_events_lead_id ON opt_out_events(lead_id);
CREATE INDEX IF NOT EXISTS idx_opt_out_events_timestamp ON opt_out_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_opt_out_events_channel ON opt_out_events(channel);

COMMENT ON TABLE opt_out_events IS 'Audit trail for opt-out events (German GDPR compliance)';
COMMENT ON COLUMN opt_out_events.channel IS 'whatsapp, sms, or other channel';
COMMENT ON COLUMN opt_out_events.keyword_used IS 'The exact keyword that triggered opt-out (e.g., STOP, ABMELDEN)';
