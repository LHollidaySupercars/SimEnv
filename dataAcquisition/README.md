# dataAcquisition

Motorsport data acquisition and analysis pipeline for the Australian Supercars Championship (V8SC / Gen3). This project takes raw MoTeC `.ld` binary data logger files from multiple manufacturers (Ford, GM, Toyota), compiles them into a structured cache, analyses per-lap performance, and pushes results to a cloud database powering a real-time Pit Wall web dashboard.

---

## Sub-systems

### `Motec_MP/` — MoTeC Binary I/O Layer

Custom, licence-free `.ld` file reader and writer built by reverse-engineering the MoTeC binary format. No MoTeC i2 API licence required.

**Key files:**
- `motec_ld_reader.m` — Core binary channel reader. Handles float16, int16, int32 data types; walks the channel linked list; normalises distance channels.
- `motec_ld_writer.m` — Writes modified data back to `.ld` format with byte-exact fidelity.
- `motec_ld_info.m` — Extracts driver/vehicle/venue/session from fixed header offsets.
- `motec_ld_inspect.m`, `motec_ld_probe.m`, `motec_ld_trace.m` — Debug tools used during format reverse-engineering.
- `channelAdd/ld_add_channel.m` — Appends new virtual channels into the `.ld` linked list.
- `smp_discover_aliases.m` — Scans all `.ld` files to harvest unique raw driver/venue/session strings for populating alias config.
- `smp_recompute_vch.m` / `smp_recompute_vch_worker.m` — Recompute virtual channel statistics (serial and parallel).

**Configuration data:**
- `alias/` — `driverAlias.xlsx`, `eventAlias.xlsx` — canonical name→alias mappings and team colours.
- `channels/` — `channels.xlsx` master channel list (set `check=1` to extract a channel).
- `filterRequest/` — Filter request config Excel.
- `plottingRequest/` — Excel-driven plot configuration files for each report type (Devo, PerformanceReport, PostSessionReport, SystemsReport, etc.).

**Filtering:**
- `motecFiltering/smp_filter.m` — Filters the full multi-team SMP struct by event/session/driver/manufacturer.
- `motecFiltering/smp_alias_load.m` — Loads `eventAlias.xlsx` (EVENT/VENUE/SESSION sheets).

**Plotting and reporting:**
- `plot/smp_plot.m` — Core plot function.
- `plot/smp_plot_from_config.m` — Renders all plots defined in a `plottingRequest` Excel config.
- `plot/smp_generate_pptx_report.m` — Generates a branded PowerPoint report from config.
- `plot/smp_read_excel.m` — Reads pre-processed race data Excel sheets.
- `plot/pptx/` — COM-based PowerPoint helpers (`smp_open_pptx.m`, `smp_insert_figure.m`, `smp_save_close_pptx.m`).
- `plot/templates/` — Branded PowerPoint template (`SuperCars_PPT.pptx`).
- `plot/output/` — Generated `.pptx` / `.pdf` reports (gitignored).

---

### `parseEventData/` — Event Compilation and Analysis Pipeline

The analytical core. Processes loaded channel data from all teams into per-lap statistics, manages a disk-based cache, and handles pit stop detection.

**Compilation pipeline (in order):**
```
smp_scan_folders → smp_append_stints → motec_ld_reader → smp_custom_channels
→ smp_gated_channels → smp_data_filter → lap_slicer → distance_interp
→ lap_stats → smp_cache_save
```

**Key files:**
- `lap_slicer.m` — Cuts continuous channel data into per-lap structs.
- `lap_stats.m` — Computes per-lap statistics: min, max, mean, median, std, and more.
- `smp_custom_channels.m` — Computes derived/virtual channels post-read.
- `smp_gated_channels.m` — Injects Excel-defined conditional (gated) channels.
- `distance_interp.m` — Resamples all channels onto a common distance axis.
- `smp_filter_cache.m` — Filters compiled cache by event/session/team/manufacturer.
- `smp_pitstop_detect.m` — Detects pit stops from air jack and TPMS channels.
- `smp_pitstop_report.m` / `smp_stops_to_pitdata.m` — Pit stop figure generation.

**Cache management:**
- `smp_cache_load.m`, `smp_cache_save.m`, `smp_cache_add.m`, `smp_cache_remove.m`, `smp_cache_diff.m`, `smp_cache_empty.m`
- Supports `'legacy'` (one `.mat`) and `'session'` (one `.mat` per session) save modes.

**Season configuration:**
- `smp_season_load.m` — Loads `trackDB/seasonOverview.xlsx` for per-track lap time windows.
- `smp_season_get.m` — Retrieves min/max lap time for a given track acronym.

**Entry points:**
- `executionScripts/execute_main_report.m` — Unified entry: handles serial/parallel compilation, plotting, and upload in one script.
- `executionScripts/execute_main_report_parallel.m` — Pure parallel variant.
- `executionScripts/execute_main_report_serial.m` — Pure serial variant.

---

### `serverInteraction/` — Database Upload and Pit Wall Dashboard

Handles all data egress from MATLAB and runs the web-facing real-time Pit Wall display. The system has evolved through three backend generations; the current production backend is Azure SQL + Azure Functions.

**Current production flow:**
```
smp_launch.m → smp_cache_load → smp_flatten_stats → smp_push_to_sql
    → Azure SQL (dbo.lap_stats)
    → Azure Function (function_getLapStats)
    → dashboard/smp_data.js
    → dashboard/smp_charts.js
```

**Key files:**
- `smp_launch.m` — Unified launcher: connects to PocketBase (local), or Azure SQL (local/Entra ID MFA).
- `smp_flatten_stats.m` — Converts the compiled cache struct to a flat MATLAB table for DB insert.
- `smp_push_to_sql.m` — Batched JDBC `PreparedStatement` inserts to Azure SQL.
- `smp_sql_connect.m` — JDBC connection factory (Azure SQL / local SQL Express).
- `smp_data_filter.m` — Sets out-of-range / sentinel samples to NaN before upload.
- `smp_generate_config.m` — Reads `V8SC_PitWall_plot_organizer.xlsx` and auto-generates `dashboard/smp_config.js`.

**Pit Wall web dashboard (`dashboard/`):**
- `index.html` — Single-page app shell.
- `smp_auth.js` — Entra ID MSAL browser authentication.
- `smp_data.js` — Progressive data loading from Azure Function API.
- `smp_charts.js` — Chart.js rendering engine.
- `smp_config.js` — Auto-generated app and plot configuration (do not hand-edit; regenerate via `smp_generate_config.m`).

**Azure Function (`function_getLapStats/`):**
- Node.js HTTP-triggered Azure Function that queries `dbo.lap_stats` and returns JSON.
- Triggered at `GET /api/getLapStats`.
- Dependencies: `mssql` npm package.

**SQL project (`SQL_server/V8_SC_Pitwall/`):**
- SQL Server Database Project (`.sqlproj`) defining the `dbo.lap_stats` table schema and related objects.

**Infrastructure:**
- `sqljdbc/enu/` — Microsoft JDBC driver JARs and MSAL auth DLL (for MATLAB→Azure SQL connection).

---

## Typical Workflow

1. **Session data arrives** — `.ld` files dropped into team folders (`NN_TEAMNAME/`).
2. **Compile** — Run `execute_main_report.m`. Scans folders → loads channels → slices laps → computes stats → saves to cache.
3. **Plot** — Generates Excel-configured PPTX reports via `Motec_MP/plot/`.
4. **Upload** — `smp_launch.m` flattens the cache and pushes lap stats rows to Azure SQL.
5. **Pit Wall** — Engineers open `dashboard/index.html`; the SPA authenticates via Entra ID, calls the Azure Function, and renders live charts.
