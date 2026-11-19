# Phase 17 — WHOOP Recovery & Strain Screens Forensic Audit

**Classification:** `VERIFIED_BINARY` + `VERIFIED_SCREENSHOT`  
**Binary Modules:** `CycleRecovery`, `CycleStrain`, `StrainCoachView`, `WhoopHistoricalTrends`

---

## 1. Recovery Detail Screen

### 1.1 Hero Section
- **Recovery Score Gauge:** Large 140 pt circular gauge (`#00E676` Green, `#FFDE00` Yellow, or `#FF3B30` Red).
- **Center Value:** `DINPro-Bold` 48 pt with `%` symbol.
- **Status Subtitle:**
  - `67% – 100%`: `"RECOVERED"`, `"Your body is primed to take on high strain."`
  - `34% – 66%`: `"ADEQUATE"`, `"Your body is maintaining baseline performance."`
  - `1% – 33%`: `"REST & RECOVER"`, `"Your body is fatigued; prioritize rest and sleep."`

### 1.2 Contributing Factors Matrix
Card container `#1D2429` with 4 comparative horizontal rows:
1. **Heart Rate Variability:** Current ms vs 30-day baseline range (`[ 36 ms ]` vs `32–48 ms`).
2. **Resting Heart Rate:** Current bpm vs 30-day baseline range (`[ 54 bpm ]` vs `49–55 bpm`).
3. **Sleep Performance:** Last night's sleep score (`[ 82% ]`).
4. **Respiratory Rate:** Current rpm vs 30-day baseline range (`[ 18.2 rpm ]` vs `17.5–18.8 rpm`).

---

## 2. Strain Detail Screen

### 2.1 Hero Section
- **Day Strain Gauge:** Large 140 pt circular gauge in electric cobalt blue (`#0091FF`).
- **Center Value:** `DINPro-Bold` 48 pt (e.g. `12.4`). Logarithmic scale `0.0 – 21.0`.

### 2.2 Optimal Strain Coach (`StrainCoachView`)
- **Optimal Target Tunnel:**
  - Graph showing cumulative strain curve vs targeted strain corridor (shaded light blue band).
  - Target Corridor derived dynamically from morning recovery score:
    - High Recovery (>66%): Target 14.0 – 18.0 (Overreaching / Building Fitness).
    - Medium Recovery (34–66%): Target 10.0 – 14.0 (Maintaining Fitness).
    - Low Recovery (<34%): Target 0.0 – 10.0 (Restorative).

### 2.3 HR Zones Histogram
Stacked horizontal bars representing duration spent in each HR zone:
- Zone 5 (90–100%): Crimson `#EB5757`
- Zone 4 (80–90%): Orange `#F2994A`
- Zone 3 (70–80%): Vivid Blue `#00B2FE`
- Zone 2 (60–70%): Azure `#2D9CDB`
- Zone 1 (50–60%): Slate Blue `#337099`
- Total Active Calories vs Total Day Calories (`DINPro-Medium` 20 pt).
