# Phase 17 — WHOOP Community Screens Forensic Audit

**Classification:** `VERIFIED_BINARY` + `VERIFIED_ASSET`  
**Binary Modules:** `WhoopCommunity`, `WhoopCommunity_WhoopCommunity.bundle`

---

## 1. Community Landing Page Architecture

The Community tab provides team competition, leaderboards, and shared goals:

```
+-------------------------------------------------------------+
| COMMUNITY                                          [+ Team] |
+-------------------------------------------------------------+
| [MY TEAMS (3)]                   [DISCOVER]                 |
+-------------------------------------------------------------+
|   +-----------------------------------------------------+   |
|   | EARLY RISERS RUN CLUB                 Rank: #4 / 28 |   |
|   | Avg Strain: 12.4 | Avg Sleep: 82%                   |   |
|   +-----------------------------------------------------+   |
|   | CROSSFIT CENTURY                     Rank: #12 / 64 |   |
|   | Leader: Alex M. (Strain 18.2)                       |   |
|   +-----------------------------------------------------+   |
+-------------------------------------------------------------+
```

---

## 2. Team Leaderboard Screen

- **Leaderboard Categories (Segmented Control):**
  - `"Strain"`
  - `"Recovery"`
  - `"Sleep Performance"`
- **Time Periods:** `"Today"`, `"This Week"`, `"This Month"`.
- **Row Anatomy:**
  - Rank badge: `#1`, `#2`, `#3` highlighted with Gold (`#FFD700`), Silver (`#C0C0C0`), Bronze (`#CD7F32`) pills.
  - Member Avatar: 32 pt circle.
  - Member Name: `ProximaNova-Semibold` 14 pt.
  - Score Display: `DINPro-Bold` 16 pt.

---

## 3. STRAP Local Community Parity

For STRAP:
- Since STRAP is local-first, the Community tab can support:
  - Local family/peer sync via Bluetooth or local network export/import.
  - Historical personal streak leaderboard.
  - Clear indicator that cloud team synchronization is reserved for WHOOP servers.
