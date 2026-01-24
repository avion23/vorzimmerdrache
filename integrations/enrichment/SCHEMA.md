# Enrichment Data Schema

## Input Schema

```json
{
  "id": "string (optional)",
  "name": "string (optional)",
  "email": "string (optional)",
  "phone": "string (optional)",
  "address": "string (required)",
  "street": "string (optional, alt to address)",
  "postalCode": "string (optional, alt to address)",
  "city": "string (optional, alt to address)",
  "leadSource": "string (optional)"
}
```

## Enriched Lead Schema

```json
{
  "id": "string",
  "name": "string",
  "email": "string",
  "phone": "string",
  "address": {
    "original": "string",
    "validated": "string",
    "coordinates": {
      "lat": "number",
      "lng": "number"
    },
    "components": {
      "streetNumber": "string",
      "street": "string",
      "postalCode": "string",
      "city": "string",
      "district": "string",
      "state": "string",
      "country": "string",
      "countryCode": "string"
    },
    "valid": "boolean",
    "error": "string (optional)"
  },
  "solar": {
    "roofArea": "number (m²)",
    "panelCount": "number",
    "estimatedKwhPerYear": "number",
    "estimatedCapacityKw": "number",
    "orientation": "south|southwest|southeast|west|east|north|unknown",
    "roofType": "flat|pitched|unknown",
    "dataSource": "google-solar-api|osm-heuristic",
    "confidence": "high|medium|low"
  },
  "system": {
    "estimatedCostEUR": "number",
    "costPerKwh": "number"
  },
  "qualification": {
    "score": "number (0-10)",
    "category": "excellent|good|moderate|poor",
    "priority": "P0 - Critical|P1 - High|P2 - Medium|P3 - Low",
    "recommendation": "string"
  },
  "regional": {
    "state": "string",
    "solarIrradiance": "number (kWh/m²/year)",
    "regionalBonus": "number (multiplier)"
  },
  "enrichedAt": "ISO8601 timestamp"
}
```

## Geocode Response Schema

```json
{
  "success": "boolean",
  "address": "string",
  "components": {
    "streetNumber": "string",
    "street": "string",
    "postalCode": "string",
    "city": "string",
    "district": "string",
    "state": "string",
    "country": "string",
    "countryCode": "string"
  },
  "coordinates": {
    "lat": "number",
    "lng": "number"
  },
  "locationType": "ROOFTOP|RANGE_INTERPOLATED|GEOMETRIC_CENTER|APPROXIMATE",
  "placeId": "string",
  "viewport": "object",
  "types": ["array"],
  "error": "string (optional)"
}
```

## Solar Estimate Schema

```json
{
  "source": "google-solar-api|osm-heuristic",
  "roofArea": "number (m²)",
  "maxSunlitRoofArea": "number (m²)",
  "maxArrayPanelsCount": "number",
  "maxArrayAreaMeters2": "number (m²)",
  "maxArrayCapacityWatts": "number (W)",
  "maxArrayEnergyProductionKwh": "number (kWh/year)",
  "panelOrientation": "string",
  "roofType": "flat|pitched|unknown",
  "confidence": "high|medium|low"
}
```

## Scoring Schema

```json
{
  "totalScore": "number (0-10)",
  "breakdown": {
    "addressValid": "number (0-10)",
    "roofSize": "number (0-10)",
    "regionalFactor": "number (0-10)",
    "orientation": "number (0-10)",
    "roofType": "number (0-10)"
  },
  "category": "excellent|good|moderate|poor",
  "recommendation": "string",
  "priority": "P0 - Critical|P1 - High|P2 - Medium|P3 - Low"
}
```

## Enrichment Flow

1. **Input Validation**
   - Validate address presence and format
   - Return error if invalid

2. **Geocoding (Google Maps API)**
   - Send address to Geocoding API
   - Parse response for coordinates and components
   - Validate country is Germany (DE)
   - Handle rate limiting (50 req/sec)

3. **Solar Potential Estimation**
   - Try Google Solar API first (if available)
   - Fallback to OSM heuristic:
     - Estimate roof area from building size
     - Estimate orientation based on latitude
     - Estimate roof type from postal code region
   - Calculate potential energy production

4. **Qualification Scoring**
   - Score components:
     - Address validity (weight: 3.0)
     - Roof size (weight: 2.5)
     - Regional solar factor (weight: 2.0)
     - Orientation (weight: 1.5)
     - Roof type (weight: 1.0)
   - Normalize to 0-10 scale
   - Determine category and priority

5. **Regional Data Lookup**
   - Match state to regional solar data
   - Get irradiance values
   - Apply regional bonus multiplier

6. **System Cost Estimation**
   - Base cost: 400W panel × 1.4 EUR/W
   - Apply regional bonus
   - Calculate cost per kWh

7. **Output**
   - Combine all enriched data
   - Add timestamp
   - Return structured result

## API Rate Limits

- **Google Geocoding API**: 50 requests/second (QPS)
- **Google Solar API**: 1 request/second (QPS)
- **Batch processing**: Configurable batch size and delay

## Error Handling

- Invalid address format → 0 score, error message
- Geocoding failure → 0 score, preserve original address
- Non-German address → Error, no enrichment
- Solar API failure → Use heuristic fallback
- Missing regional data → Use defaults

## Environment Variables

```
GOOGLE_MAPS_API_KEY=your_geocoding_api_key
GOOGLE_SOLAR_API_KEY=your_solar_api_key
GOOGLE_SHEET_ID=your_sheet_id
```

## Google Sheets Columns

| Column | Field | Description |
|--------|-------|-------------|
| A | id | Lead ID |
| B | name | Customer name |
| C | email | Email address |
| D | phone | Phone number |
| E | originalAddress | Original input address |
| F | validatedAddress | Google validated address |
| G | score | Qualification score (0-10) |
| H | category | Score category |
| I | roofArea | Estimated roof area (m²) |
| J | estimatedKwh | Annual production (kWh) |
| K | costEUR | System cost estimate |
| L | state | German state |
| M | priority | Lead priority |
| N | enrichedAt | Enrichment timestamp |
