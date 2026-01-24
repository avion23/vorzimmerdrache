┌─────────────────────────────────────────────────────────────────────┐
│                     SOLAR LEAD ENRICHMENT FLOW                        │
└─────────────────────────────────────────────────────────────────────┘

Input Lead
    │
    ▼
┌─────────────────────┐
│  Validate Input    │◄─────────────────────┐
│  - Check address   │                      │
│  - Format check    │                      │
└─────────┬───────────┘                      │
          │                                  │
          ▼                                  │
    ┌─────────────────┐                      │
    │  Geocode API    │                      │
    │  (Google Maps) │                      │
    └────────┬────────┘                      │
             │                               │
             ├─────────────┬─────────────────┤
             │             │                 │
         Success        Failure             │
             │             │                 │
             ▼             ▼                 │
    ┌──────────────┐  ┌──────────────┐      │
    │ Parse Geo-   │  │ Handle Error │      │
    │ code Result  │  │ (Score = 0)  │      │
    └──────┬───────┘  └──────┬───────┘      │
           │                 │              │
           ▼                 │              │
    ┌──────────────┐          │              │
    │ Check Country│          │              │
    │ (Germany?)   │          │              │
    └──────┬───────┘          │              │
           │                 │              │
      ┌────┴────┐             │              │
      │         │             │              │
     Yes        No            │              │
      │         │             │              │
      ▼         ▼             │              │
┌──────────┐ ┌──────┐        │              │
│Solar API │ │Error │        │              │
└────┬─────┘ └──┬───┘        │              │
     │          │            │              │
     ├─────┬────┤            │              │
     │     │    │            │              │
  Success   Fallback         │              │
     │     │                │              │
     ▼     ▼                │              │
┌──────────────┐            │              │
│Parse Solar   │            │              │
│Data          │            │              │
└──────┬───────┘            │              │
       │                    │              │
       ▼                    │              │
┌──────────────────────────┐│              │
│ Calculate Qualification  ││              │
│ Score (0-10)             ││              │
│ ┌────────────────────┐   ││              │
│ │ • Address Valid    │   ││              │
│ │   (weight: 3.0)   │   ││              │
│ │ • Roof Size       │   ││              │
│ │   (weight: 2.5)   │   ││              │
│ │ • Regional Factor │   ││              │
│ │   (weight: 2.0)   │   ││              │
│ │ • Orientation     │   ││              │
│ │   (weight: 1.5)   │   ││              │
│ │ • Roof Type       │   ││              │
│ │   (weight: 1.0)   │   ││              │
│ └────────────────────┘   ││              │
└──────┬───────────────────┘│              │
       │                    │              │
       ▼                    │              │
┌──────────────────────────┐│              │
│ Regional Data Lookup     ││              │
│ • Solar Irradiance       ││              │
│ • Regional Bonus         ││              │
└──────┬───────────────────┘│              │
       │                    │              │
       ▼                    │              │
┌──────────────────────────┐│              │
│ System Cost Estimation   ││              │
│ • Base cost calculation  ││              │
│ • Regional multiplier   ││              │
└──────┬───────────────────┘│              │
       │                    │              │
       ▼                    │              │
┌──────────────────────────┐│              │
│ Enrich Lead Data         ││              │
│ • Combine all fields     ││              │
│ • Add timestamp          ││              │
└──────┬───────────────────┘│              │
       │                    │              │
       ▼                    │              │
┌──────────────────────────┐│              │
│ Update Google Sheets     ││              │
└──────┬───────────────────┘│              │
       │                    │              │
       └────────────────────┴──────────────┘
                │
                ▼
        ┌───────────────┐
        │ Format Output │
        └───────┬───────┘
                │
                ▼
        ┌───────────────┐
        │ Return Result │
        └───────────────┘

──────────────────────────────────────────────────────────────────────────
SCORING RANGES
──────────────────────────────────────────────────────────────────────────
Score 8-10: EXCELLENT (P0 - Critical)
  • Immediate contact
  • Highest potential ROI
  • Schedule consultation ASAP

Score 6-7:  GOOD (P1 - High)
  • High priority follow-up
  • Qualified lead
  • Add to pipeline

Score 4-5:  MODERATE (P2 - Medium)
  • Standard follow-up
  • May need site visit
  • Assess individually

Score 0-3:  POOR (P3 - Low)
  • Optional follow-up
  • Consider declining
  • Not suitable

──────────────────────────────────────────────────────────────────────────
REGIONAL SOLAR FACTORS (Germany)
──────────────────────────────────────────────────────────────────────────
Highest Potential (Score 9):
  • Baden-Württemberg  (1150 kWh/m²/yr)
  • Bayern             (1120 kWh/m²/yr)

High Potential (Score 8):
  • Rheinland-Pfalz    (1090 kWh/m²/yr)

Moderate Potential (Score 6-7):
  • Hessen             (1070 kWh/m²/yr)
  • Saarland           (1070 kWh/m²/yr)
  • Brandenburg        (1050 kWh/m²/yr)
  • Mecklenburg-Vorpommern (1040 kWh/m²/yr)
  • Thüringen          (1040 kWh/m²/yr)
  • Sachsen            (1030 kWh/m²/yr)
  • Sachsen-Anhalt     (1030 kWh/m²/yr)

Lower Potential (Score 5-6):
  • Nordrhein-Westfalen (1010 kWh/m²/yr)
  • Berlin             (1020 kWh/m²/yr)
  • Niedersachsen      (1000 kWh/m²/yr)

Lowest Potential (Score 5):
  • Hamburg            (990 kWh/m²/yr)
  • Schleswig-Holstein (990 kWh/m²/yr)
  • Bremen             (980 kWh/m²/yr)
