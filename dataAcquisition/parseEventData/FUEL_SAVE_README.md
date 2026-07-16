# Fuel-Saving Coasting Analysis
## Quick Start Guide

### Overview
This suite of MATLAB functions simulates fuel-saving strategies by analyzing qualifying lap data. It detects throttle-brake segments, tests multiple coasting start points, and quantifies the fuel-time trade-off.

**Workflow:**
1. Load fastest lap from session cache
2. Auto-detect or load throttle-brake segments
3. Test multiple coasting distances per segment
4. Simulate linear deceleration with constant fuel burn
5. Report fuel saved vs time penalty for each variant
6. Generate visualization plots and strategy Excel file

---

## Usage

### Minimal (Auto-everything)
```matlab
[variants, segments, output_dir] = smp_fuel_save_coasting();
```
- Auto-finds cache, selects global fastest lap, auto-detects segments
- User edits Excel template for segment enable/disable
- Results in `./fuel_save_output/`

### With Custom Parameters
```matlab
[variants, segments, output_dir] = smp_fuel_save_coasting(...
    'cache_file', './smp_cache.mat', ...
    'driver_tla', 'JAC', ...
    'accel', -0.8, ...
    'fuel_rate', 0.015, ...
    'output_dir', './fuel_save_q1');
```

### All Parameters
```matlab
[variants, segments, output_dir] = smp_fuel_save_coasting(...
    'cache_file', path_to_cache, ...      % Path to smp_cache.mat
    'driver_tla', 'ABC', ...               % Driver code (empty = global fastest)
    'config_file', path_to_excel, ...      % Excel config (auto-gen if empty)
    'accel', -0.5, ...                     % Deceleration magnitude (m/s²)
    'fuel_rate', 0.01, ...                 % Fuel consumption (kg/s)
    'output_dir', './fuel_save_output', ...% Output directory
    'auto_detect', true);                  % Auto-detect segments
```

---

## Excel Configuration

### Auto-Generated Template (`smp_fuel_save_config.xlsx`)
The function generates a template with:

| Column | Description | Default |
|--------|-------------|---------|
| Segment_ID | Index | Auto |
| Segment_Name | Name (e.g., "Turn 1") | Auto |
| Distance_Start_m | Segment start (m) | Auto-detected |
| Distance_End_m | Segment end (m) | Auto-detected |
| Brake_Marker_m | Brake application point (m) | Auto-detected |
| Enable_Fuel_Save | 0=skip, 1=test | 1 (enabled) |
| Coasting_Distance_Max_m | Max coasting distance before brake (m) | -200 |
| Coasting_Steps | Number of coasting points to test | 10 |

### Editing the Config
1. Function generates template
2. **User edits:**
   - Set `Enable_Fuel_Save = 0` to skip a segment
   - Adjust `Coasting_Distance_Max_m` (e.g., -100, -300)
   - Adjust `Coasting_Steps` (e.g., 5, 20)
3. Save and close Excel
4. Press Enter in MATLAB to continue

### Example: Custom Coasting Range
```
Coasting_Distance_Max_m = -200
Coasting_Steps = 10
```
→ Tests coasting at: -20m, -40m, -60m, ..., -200m (10 points)

---

## Outputs

### 1. Strategy Excel (`smp_fuel_save_strategy.xlsx`)
Per-variant summary:

| Column | Meaning |
|--------|---------|
| Segment_ID | Segment index |
| Segment_Name | Segment name |
| Coasting_Distance_m | Coasting start (m before brake marker) |
| Fuel_Saved_kg | Fuel conserved in this variant (kg) |
| Time_Penalty_sec | Time lost vs original lap (sec) |
| Fuel_per_Time_Ratio | Fuel saved per second lost (kg/sec) |
| Status | 'success' or error message |

**Interpretation:**
- `Fuel_per_Time_Ratio > 0`: Saves fuel at cost of time
- Sort by this ratio to find best fuel efficiency
- Combine best ratios from different segments for overall strategy

### 2. Plots

#### Speed Traces by Segment
- Each subplot = one segment
- Black line: original qualifying lap
- Colored lines: coasting variants
- Red dashed: brake marker

**What to look for:**
- Speed reduction while coasting (expected)
- Speed rejoining original trace (intersection point)
- Steeper deceleration = longer coasting distance

#### Fuel vs Time Trade-off
- Scatter plot: Time Penalty (x) vs Fuel Saved (y)
- Each point = one variant
- Color = segment
- Closer to origin = better trade-off

**What to look for:**
- Linear relationship (expected)
- Outliers indicate data issues
- Segment clustering shows which segments benefit most

#### Coasting Distance Sensitivity
- Per-segment curves: coasting distance (x) vs fuel (blue) / time (red)
- Dual-axis plot

**What to look for:**
- Diminishing returns (curve flattens)
- Optimal coasting distance (where trade-off best)
- Segment-specific behavior differences

---

## Data Requirements

### Required Channels
The lap must include:
- `Distance` (m) — cumulative distance from lap start
- `Ground_Speed` (km/h) — vehicle speed
- `Throttle_Pedal` (%) — throttle position
- `Brake_Pressure_Front` (bar) — braking force

### Cache Structure

The cache is created by `smp_compile_event.m` and stored as `smp_cache_*.mat` files. Understanding the structure is key to working with fuel-saving analysis.

**Top-Level Cache Structure:**
```matlab
cache.manifest      % [table] Metadata about all sessions/files
cache.stats         % [struct] Per-lap statistics aggregated
cache.traces        % [struct] Top-N fastest lap traces (sparse storage)
cache.channels      % [containers.Map] (only in bulk mode)
cache.info          % [containers.Map] (only in bulk mode)
cache.mode          % 'stream' (default) or 'bulk'
cache.save_mode     % 'session' (default) or 'legacy'
```

**Traces Structure (What We Use):**
```matlab
cache.traces.(group_key)
  ├─ .lap_times              [1 x n] lap times in seconds, sorted ascending
  ├─ .lap_numbers            [1 x n] lap IDs
  ├─ .n_traces               scalar, number of stored laps (typically 5)
  │
  ├─ .Ground_Speed           struct array, one element per lap
  │  ├─ (1).data             [m x 1] speed values (km/h) for lap 1
  │  ├─ (1).dist             [m x 1] distance axis (m) for lap 1
  │  ├─ (2).data             [m x 1] speed values for lap 2
  │  ├─ (2).dist             [m x 1] distance for lap 2
  │  └─ ... (repeats for each stored lap)
  │
  ├─ .Distance               struct array (similar structure)
  ├─ .Throttle_Pedal         struct array (similar structure)
  ├─ .Brake_Pressure_Front   struct array (similar structure)
  └─ ... (126+ channels available, only requested ones stored)
```

**Group Key Format:**
```matlab
group_key = 't8r_jackson_walls_q13_185'
             ├─ team acronym: 't8r' (Tauri Racing)
             ├─ driver: 'jackson_walls'
             ├─ session: 'q13' (Qualifying 1, Session 3)
             └─ track: '185' (track ID)
```

**Accessing Data:**
```matlab
% Get fastest lap for a group
group_key = 't8r_jackson_walls_q13_185';
lap_times = cache.traces.(group_key).lap_times;  % [81.92, 82.02, 82.46, 82.53]
best_time = lap_times(1);  % 81.92 seconds

% Get speed data for fastest lap
speed_data = cache.traces.(group_key).Ground_Speed(1).data;  % km/h values
distance_data = cache.traces.(group_key).Ground_Speed(1).dist;  % meters

% Access throttle for lap 2
throttle_lap2 = cache.traces.(group_key).Throttle_Pedal(2).data;  % % values
```

**Why This Structure?**
- Saves memory: only top-N laps kept (not all laps in session)
- Preserves distance axis: each lap may have different distance resolution
- Fast lookup: direct struct access, no table operations
- Sparse: only requested channels stored during compilation

**Cache Statistics Storage (Different From Traces):**
```matlab
cache.stats.(group_key).Ground_Speed
  ├─ .lap_numbers            [1 x n_laps]
  ├─ .lap_times              [1 x n_laps]
  ├─ .min, .max, .mean       [1 x n_laps] (statistics per lap)
  ├─ .median, .std, .var
  ├─ .range, .mean_non_zero
  └─ ... (computed by lap_stats.m)
```

The stats are used for performance trending; traces are used for detailed analysis like fuel saving.

---

## Accessing Your Cache Manually

Given your cache structure:
```matlab
% List all available groups/drivers
groups = fieldnames(cache.traces);
% Result: {'t8r_jackson_walls_q13_185', 't8r_broc_feeney_q13_185', 't8r_will_brown_q13_185'}

% Get fastest lap overall
for g = 1:length(groups)
    gk = groups{g};
    times = cache.traces.(gk).lap_times;
    fprintf('%s: fastest = %.2f sec\n', gk, min(times));
end

% Extract full lap data for analysis
gk = 't8r_jackson_walls_q13_185';  % Group/driver
speed = cache.traces.(gk).Ground_Speed(1).data;  % km/h
dist = cache.traces.(gk).Ground_Speed(1).dist;   % meters
throttle = cache.traces.(gk).Throttle_Pedal(1).data;  % %
brake = cache.traces.(gk).Brake_Pressure_Front(1).data;  % bar
```

---

## Physics Model

### Coasting Simulation
**Inputs:**
- Starting speed: v₀ (km/h)
- Deceleration: a (m/s²) [negative]
- Fuel consumption: ṁ (kg/s) [constant]

**Equations:**
- Speed: v(t) = v₀ + a·t  [m/s]
- Distance: d(t) = v₀·t + 0.5·a·t²  [m]
- Fuel: m_f = ṁ·t_coast  [kg]

**Stopping Condition:**
- Coasting ends when speed ≤ original lap speed (intersection)
- Then follows original lap exactly

### Example Scenario
- Brake marker: 1000m
- Coasting start: 950m (coasting_point = -50m)
- Initial speed: 100 km/h
- Deceleration: -0.5 m/s²
- Fuel rate: 0.01 kg/s
- Result: coasts to ~970m, saves ~0.04 kg, loses ~0.8 sec

---

## Customization

### Segment Detection Sensitivity
Edit `smp_detect_throttle_brake_phases.m`:
```matlab
% Find throttle release: threshold in %/s
throttle_release_idx = find(d_throttle < -5);  % Change -5 to adjust

% Find brake application: threshold in bar/s
brake_apply_idx = find(d_brake > 5);  % Change 5 to adjust
```

### Physics Parameters
Pass to main function:
```matlab
'accel', -0.8, ...         % Sharper deceleration
'fuel_rate', 0.02, ...     % Higher fuel consumption rate
```

### Segment Boundaries
Edit Excel template:
- `Distance_Start_m`, `Distance_End_m` define segment window
- Set to ±150m instead of ±100m for wider segments

---

## Example Workflow

```matlab
% 1. Run analysis with custom accel
[v, s, outdir] = smp_fuel_save_coasting('accel', -0.8, 'driver_tla', 'JAC');

% 2. Wait for Excel edit (user modifies config)

% 3. Review Excel results
table = readtable(fullfile(outdir, 'smp_fuel_save_strategy.xlsx'));
disp(table);

% 4. Visualize best trade-offs
best_variants = v([v.fuel_saved_kg] > 0.05);  % Fuel > 50g
disp(best_variants);
```

---

## Troubleshooting

### "Cannot find smp_cache.mat"
- Specify explicit path: `'cache_file', 'C:/path/to/cache.mat'`
- Ensure cache exists and is readable

### "Segment detection found 0 segments"
- Check if Throttle_Pedal and Brake_Pressure_Front channels exist
- Qualifying lap may not have typical braking profile
- Edit Excel manually instead of auto-detect

### "Intersection not found"
- Coasting deceleration too weak (accel too close to zero)
- Segment end reached before speed intersects
- Try increasing `accel` magnitude (more negative, e.g., -1.0)

### "Status: error" in Excel
- Check speed trace is reasonable (> 0 km/h)
- Verify coasting point is within segment bounds
- Increase output verbosity by editing main function

---

## Performance Notes

- Analysis typically runs in 10-30 sec (depends on segment count & coasting steps)
- Each variant simulation = ~100-1000 time steps
- Plots generated after analysis completes

---

## References

- **Throttle-brake transition detection**: Looks for sharp gradients in channels
- **Coasting physics**: Standard constant-acceleration kinematics
- **Trade-off analysis**: Fuel saved vs time lost per segment
- **Visualization**: MATLAB plotting with multi-segment subplots

---

## Author Notes

This tool answers: *"What is the fuel saving and time penalty for each coasting strategy?"*

Typical results:
- 0.05-0.2 kg fuel saved per segment coasting
- 0.5-2.0 sec time penalty per coasting segment
- 0.02-0.1 kg/sec trade-off ratio

Use strategy Excel to compare options and select overall pit stop strategy.

