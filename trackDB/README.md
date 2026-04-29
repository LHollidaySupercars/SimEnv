# trackDB

Track and season reference database. Provides per-circuit lap time windows used throughout the SMP pipeline to filter out installation laps, in-laps, out-laps, and safety car laps.

---

## Contents

| File | Purpose |
|---|---|
| `seasonOverview.xlsx` | Maps circuit acronyms (e.g., `SMP`, `AGP`, `BAT`) to valid lap time windows (`MinLT` / `MaxLT` in seconds). One row per round. |

---

## How It's Used

`dataAcquisition/parseEventData/smp_season_load.m` reads `seasonOverview.xlsx` into a MATLAB table. `smp_season_get.m` looks up the min/max lap time bounds for a given circuit acronym. The lap slicer and stat compiler use these bounds to discard non-representative laps.

```matlab
season = smp_season_load('C:\SimEnv\trackDB\seasonOverview.xlsx');
[minLT, maxLT] = smp_season_get(season, 'AGP');
```

---

## 2026 Supercars Calendar

The 14 rounds currently configured:

| Acronym | Circuit |
|---|---|
| SMP | Sydney Motorsport Park |
| AGP | Australian Grand Prix (Albert Park) |
| TAU | Taupo |
| RUA | Cranbourne / Casey Fields |
| TAS | Symmons Plains (Tasmania) |
| PER | Perth |
| DAR | Darwin |
| TSV | Townsville |
| QLR | Queensland Raceway |
| BND | The Bend Motorsport Park |
| BAT | Bathurst |
| SUR | Gold Coast |
| SAN | Sandown |
| ADL | Adelaide |

---

## Adding a New Round

Add a row to `seasonOverview.xlsx` with the circuit acronym and appropriate `MinLT`/`MaxLT` values (in seconds). Values are typically set conservatively to include all green-flag racing laps.
