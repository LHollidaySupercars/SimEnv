# vehicleModel

Vehicle simulation model for the Supercars Gen3 platform, organised by subsystem component. Implements suspension kinematics, tyre force models, and aerodynamic map fitting from first principles.

---

## Structure

```
vehicleModel/
├── toeSolver_implicit.mlx          — Implicit toe solving live script
└── components/
    ├── kinematic/                  — Suspension kinematics (double A-arm, Gen3 hardpoints)
    ├── tyre/                       — Calspan tyre data + Pacejka Magic Formula
    ├── aerodynamics/               — Aero map data + polynomial fitting
    ├── braking/                    — (placeholder, not yet implemented)
    └── powertrain/                 — (placeholder, not yet implemented)
```

---

## `components/kinematic/`

Full double A-arm suspension kinematics from first principles using 3D sphere-intersection geometry. No lookup tables — all kinematics are solved analytically.

**Core solvers:**
- `solveWheelCamber.m` — Solves camber angle as a function of wheel travel by intersecting spheres at upper/lower ball joints.
- `solveWheelToe.m` — Solves toe angle as a function of wheel travel and steering rack displacement.
- `solveDamperTravel.m` — Converts wheel travel to damper travel via motion ratio geometry.
- `calculateRollCenter.m` — Computes roll centre height and its derivative vs wheel travel.
- `calculateAntiGeometry.m` — Computes anti-lift and anti-squat percentages from hardpoint geometry.

**Setup tools:**
- `calculateInitialToeOffset.m`, `applyToeOffsetCorrection.m` — Compute and correct toe offset at static ride height.
- `camberOffset.m`, `clevisOffset.m`, `clevisPOSOffset.m`, `getOffset.m` — Offset correction utilities for shim and clevis adjustments.
- `DOE_Kinematics.m` — Design of Experiments: enumerates all combinations of shim × ball joint × bolt lengths to survey the achievable camber/toe setup space.

**Gen3 vehicle parameters:**
- `GEN3/GEN3_KinematicParameters.m` — Hardpoint coordinates for the Gen3 Ford/GM/Toyota platform.

**Examples and live scripts:**
- `kinematicCamberToeExample.mlx` / `.m` — Worked example: sweep wheel travel and plot camber/toe curves.
- `kinSweep_Script.m`, `kinematicSweep.m` — Full suspension sweep scripts.
- `kinematicPlot.m`, `kinematicPlot_script.m` — Visualise kinematic results.
- `suspensionKinematics.mlx` — Integrated live script documentation.

**Geometry helpers:**
- `solveContactPatch.m` (`offsetInPerpendicularPlane`) — 3D geometry helper: finds the offset point in a plane perpendicular to a given vector. Used by the kinematic solvers.
- `threeSphereDisplacement.m`, `threeSphereUpperAArm.m` — Sphere-intersection routines for A-arm geometry.
- `circleFromTwoSpheres.m` — Computes the intersection circle of two spheres.

---

## `components/tyre/`

Calspan flat-belt tyre rig test data and Pacejka Magic Formula (MF) implementations for the Gen3 tyre (ID: A_1792, 2017 data).

**Data files:**
- `calspanData_2017_separated.mat`, `calspan_run.mat`, `calspan_run2017_9_2.mat` — Processed Calspan rig data.
- `Cornering Data Files/` — 43 raw cornering test runs (`runNN.dat`).
- `Braking Data Files/` — 25 raw braking test runs (`runNN.dat`).

**Pacejka implementations (`pacejkaFormula/`):**
- `MF_basic.m` — Basic Magic Formula lateral force (Fy) without camber.
- `MF_camber.m` — MF lateral force with camber effect.
- `MF_lateral_camber.m` — Combined lateral + camber formulation.
- `MF_aligning_moment_basic.m` — Aligning moment (Mz) formula.
- `MF_FullSet.m` — Full combined MF set (Fx, Fy, Mz).

**Analysis tools:**
- `pacjekaFormula.m` — Loads `.mat` data and generates force coverage plots for all runs. (Note: typo in filename — `pacjeka` vs `pacejka`.)
- `filterTestType.m` — Filters Calspan test runs by type (cornering / braking / combined).
- `tyreDataViewer.m` — Interactive MATLAB GUI for browsing Calspan run data with Pacejka model overlay.

---

## `components/aerodynamics/`

Aero map data and polynomial surface fitting for the Gen3 platform. Produces MoTeC math channel expressions from manufacturer parity aero maps.

**Data files:**
- `PARITY_AERO_MAPS.xlsx` — Gen3 parity aero maps for Ford, GM, and Toyota.
- `W14_AeroMaps_2026.xlsx` — 2026 season updated aero maps.
- `data_post__SUPERCARS_251208.xlsx` — Post-processing aero data.

**Scripts:**
- `visualize.m` — Side-by-side aero map comparison plots between manufacturers.
- `produceAeroFit.m` — Fits polynomial surfaces `Cz/Cx = f(FRH, RRH, Roll, Yaw)` and exports MoTeC math function expressions.
- `downforceMapping.m` — Polynomial surface fitting of aero maps from `PARITY_AERO_MAPS.xlsx`; produces MoTeC-compatible math channel strings for downforce and drag.

---

## `components/braking/` and `components/powertrain/`

Placeholder folders for future subsystem implementations. Currently empty.

---

## Adding a New Subsystem

1. Create a subfolder under `components/` with a descriptive name.
2. Follow the pattern established by `kinematic/`: separate solver functions from example/script files.
3. Store vehicle-specific parameters in a dedicated `GEN3_XXXParameters.m` file.
