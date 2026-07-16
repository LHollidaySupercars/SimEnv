# validation

Tyre model validation data and analysis. Contains Calspan flat-belt tyre rig test data and scripts that characterise rolling radius behaviour as a function of vertical load, wheel speed (centrifugal growth), and tyre pressure.

---

## Contents

| File / Folder | Purpose |
|---|---|
| `tyreGrowthFzVsRL.csv` | Calspan tyre rig data: rolling radius (`RL`) vs vertical load (`FZ`), wheel speed (`N`), ground velocity (`V`), and tyre pressure (`P`). Primary data source for all rolling radius studies. |
| `tyreStudies/rollingRadiusStudy.m` | Combined rolling radius analysis — fits polynomial models (`polyfit`) to the CSV data across three effects (Fz, wheel speed, pressure) and compares model predictions against scatter data. Also includes track-side debug plots comparing virtual channel rolling radius to raw wheel speed and force channels. |

---

## Rolling Radius Study

The study in `rollingRadiusStudy.m` characterises how rolling radius changes with:

1. **Vertical load (FZ)** — Linear fit of RL vs FZ.
2. **Wheel speed (N)** — Centrifugal growth: linear fit of RL vs RPM.
3. **Tyre pressure (P)** — Linear fit of RL vs pressure at fixed load bins.

A combined predictive model is assembled:
```
RL_predicted = RL0 - k_speed * vWheel - k_load * (0.5 * rho * vWheel^2 * Cl * balance)
```

Scatter plots with pressure or vertical force as the colour axis reveal the relative contribution of each effect.

---

## Data Source

The CSV data (`tyreGrowthFzVsRL.csv`) comes from Calspan tyre rig testing. Key columns:

| Column | Description |
|---|---|
| `RL` | Rolling radius (mm) |
| `FZ` | Vertical load (N, negative = compression) |
| `N` | Wheel speed (RPM) |
| `V` | Ground belt velocity (km/h) |
| `P` | Tyre inflation pressure (Psi) |
| `IA` | Inclination angle (deg) |
| `SA` | Slip angle (deg) |
