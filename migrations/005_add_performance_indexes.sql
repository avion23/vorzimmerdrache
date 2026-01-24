-- Performance Indexes Migration
-- Target: Optimize queries on the critical path (inbound call → WhatsApp → Telegram < 3s)

-- Composite index for phone + status lookups (used in CRM lookups)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_phone_status
  ON leads(phone, status)
  WHERE opted_out = FALSE;

-- Index for prioritized leads queries (lead scoring workflow)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_priority_created
  ON leads(priority DESC, created_at DESC)
  WHERE status IN ('new', 'qualified');

-- Index for address-based searches (geocoding results)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_address_components
  ON leads(address_postal_code, address_city, address_street)
  WHERE address_postal_code IS NOT NULL;

-- Index for recent lead filtering (speed-to-lead)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_recent_new
  ON leads(created_at DESC)
  WHERE status = 'new' AND opted_out = FALSE;

-- Index for GDPR cleanup queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_gdpr_cleanup
  ON leads(gdpr_delete_at)
  WHERE gdpr_delete_at IS NOT NULL;

-- Index for source-based analytics
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_source_created
  ON leads(source, created_at DESC);

-- Index for opt-out events lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_opt_out_events_phone_time
  ON opt_out_events(phone, created_at DESC);

-- Index for consent log queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_consent_logs_phone_time
  ON consent_logs(phone, created_at DESC);

-- Enable query performance monitoring (requires pg_stat_statements)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Partial index for active leads (reduces index size)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_active_status
  ON leads(status, priority DESC)
  WHERE opted_out = FALSE AND gdpr_delete_at IS NULL;

-- Index for lead score queries (if using lead_scoring table)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_lead_scoring_score_desc
  ON lead_scoring(total_score DESC, updated_at DESC);

-- Covering index for common lead retrieval queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_covering_lookup
  ON leads(phone) INCLUDE (name, status, email, address_raw);

COMMENT ON INDEX idx_leads_phone_status IS 'Optimizes CRM phone lookups with active status filter';
COMMENT ON INDEX idx_leads_priority_created IS 'Optimizes lead prioritization and scoring queries';
COMMENT ON INDEX idx_leads_address_components IS 'Optimizes geocoded address searches';
COMMENT ON INDEX idx_leads_recent_new IS 'Optimizes speed-to-lead new lead retrieval';
COMMENT ON INDEX idx_leads_active_status IS 'Small index for active lead filtering';
COMMENT ON INDEX idx_leads_covering_lookup IS 'Covering index for phone lookups (no table access needed)';
