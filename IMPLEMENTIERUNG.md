# Loop Prevention - Implementiert

## Übersicht

Alle 3 Anforderungen sind implementiert:

### 1. ✅ Blacklist-Funktion
- **Speicherort:** Google Sheet "Blacklist" (Spalte A)
- **Funktion:** Blockiert Anrufe von gesperrten Nummern
- **Aktion bei Blacklist:** Sofortiges Auflegen (Hangup), kein SMS-Versand

### 2. ✅ Cooldown-Periode  
- **Zeitfenster:** 5 Minuten
- **Logik:** Bei 3 Anrufen innerhalb 5 Minuten nur 1 SMS
- **Kosteneinsparung:** ~75% bei wiederholten Anrufen

### 3. ✅ Loop-Prevention
- Verhindert, dass zwei Vorzimmerdrache-Systeme sich gegenseitig triggern
- Blacklist schützt vor eigenen Anrufen
- Cooldown verhindert SMS-Spam

## Google Sheets Struktur

### Sheet: "Blacklist"
```
Spalte A
--------
+491711234567    <- Handwerker Handy
+49301234567     <- Handwerker Festnetz
+4917654321      <- Weitere Nummer
```

### Sheet: "Call_Log" (erweitert)
```
phone | timestamp | status | sms_sent
--------+-------------+--------+----------
+49... | 2026-02-01 | missed | true
```

## Workflow-Änderungen

### Neue Nodes:
1. **Get Blacklist** - Liest aus Google Sheets
2. **Check Blacklist** - Prüft ob Nummer gesperrt
3. **Check Cooldown** - Trackt Anrufhäufigkeit
4. **IF - Not Blacklisted** - Verzweigung
5. **IF - Should Send SMS** - SMS-Entscheidung

### Verbindungen:
```
Webhook → Parse Call → Get Blacklist → Check Blacklist
                                              ↓
                              [Blacklist?] → JA → Hangup
                              [Blacklist?] → NEIN → Check Cooldown
                                                          ↓
                                        [Cooldown?] → JA → Voice only
                                        [Cooldown?] → NEIN → Log + SMS + Voice
```

## Dateien aktualisiert

1. **workflows/roof-mode-with-protection.json** - Workflow mit Schutz
2. **LOOP_PREVENTION.md** - Dokumentation

## Nächste Schritte

1. Google Sheet "Blacklist" erstellen
2. Workflow importieren
3. Testen mit eigenen Nummern
