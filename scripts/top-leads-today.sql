SELECT
  l.id,
  l.name,
  l.phone,
  l.email,
  l.address_city,
  l.address_state,
  l.roof_area_sqm,
  ls.lead_score,
  ls.priority,
  ls.score_category,
  ls.breakdown,
  l.estimated_kwp,
  l.estimated_annual_kwh,
  l.status,
  l.created_at,
  EXTRACT(EPOCH FROM (NOW() - l.created_at)) / 60 AS minutes_ago
FROM leads l
LEFT JOIN lead_scores ls ON l.id = ls.lead_id
WHERE l.status IN ('new', 'qualified')
  AND l.created_at >= CURRENT_DATE
  AND (ls.lead_score IS NOT NULL OR l.roof_area_sqm IS NOT NULL)
ORDER BY
  COALESCE(ls.lead_score, 0) DESC,
  l.created_at DESC
LIMIT 10;
