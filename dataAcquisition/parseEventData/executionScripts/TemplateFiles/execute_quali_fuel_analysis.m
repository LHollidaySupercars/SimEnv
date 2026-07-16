%% =========================================================
%  EXECUTE_QUALI_FUEL_ANALYSIS
%  =========================================================
%  Run quali_fuel_analysis across qualifying runs from a
%  compiled cache. Produces per-car fuel effect regression
%  and tyre pressure plots.
%
%  WORKFLOW:
%    Step 1  — Edit SECTION 1 (paths) and SECTION 2 (event config)
%    Step 2  — Run SECTION 4 to compile / load cache
%    Step 3  — Run SECTION 5 to execute the analysis
%              Results land in the 'results' struct keyed by car number
% =========================================================

clear; clc; close all;

%% =========================================================
%  SECTION 1: PATHS
% =========================================================

TOP_LEVEL_DIR     = 'E:\2025\04_TAS\_TeamData';

CHANNELS_FILE     = 'C:\SimEnv\dataAcquisition\Motec_MP\channels\channels.xlsx';
EVENT_ALIAS_FILE  = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\eventAlias.xlsx';
DRIVER_ALIAS_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\driverAlias.xlsx';
SEASON_FILE       = 'C:\SimEnv\trackDB\seasonOverview.xlsx';

%% =========================================================
%  SECTION 2: EVENT CONFIG
%  SESSION_FILTER should contain all qualifying session
%  labels that exist in your cache (check manifest with
%  unique(cache.manifest.Session) if unsure).
% =========================================================

TRACK          = 'TAS';
EVENT_CODE     = '04_TAS';   % event folder name for LiftAndCoast, e.g. '04_TAS'
YEAR           = 2026;
TEAM_FILTER    = {};          % {} = all teams, e.g. {'T8R', 'WAU'}
SESSION_FILTER = {'Q13'};     % qualifying session label(s) to analyse

% BR2 beacon mode — passed to lap_slicer and LiftAndCoast.
%   'standard'  — original 999→996 transition protocol (most events)
%   'TAS2025'   — different beacon transitions used at TAS in 2025
%   ''          — force fallback to Lap_Number channel (Mode C, no beacon)
BR2_PROTOCOL   = 'TAS2025';

% lap_slicer opts — passed to every lap_slicer call in Section 5.
% BR2 channel is auto-detected when present; br2_protocol controls how
% beacon transitions are interpreted (see br2_protocol_get.m for options).
lap_slicer_opts = struct();
lap_slicer_opts.br2_channel  = 'BR2_Beacon_Number';   % '' to force Mode C
lap_slicer_opts.br2_protocol = BR2_PROTOCOL;

% Set true to show the blocking pop-up; false = command-window output only.
SHOW_REPORT = true;

%% =========================================================
%  SECTION 3: COMPILE OPTIONS
% =========================================================

compile_opts.mode           = 'stream';
compile_opts.track          = TRACK;
compile_opts.dist_n_points  = 1000;
compile_opts.dist_channel   = 'Odometer';
compile_opts.verbose        = true;
compile_opts.saveCache      = true;
compile_opts.save_mode      = 'session';
compile_opts.session_filter = SESSION_FILTER;

%% =========================================================
%  SECTION 4: LOAD CONFIG + CACHE
%  Option A: compile (processes new/changed .ld files)
%  Option B: load only (no new files — just reload cache)
%  Comment/uncomment the relevant block.
% =========================================================

season                     = smp_season_load(SEASON_FILE);
[channels, channel_rules]  = smp_channel_config_load(CHANNELS_FILE);
alias                      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map                 = smp_driver_alias_load(DRIVER_ALIAS_FILE);
compile_opts.channel_rules = channel_rules;

% --- Option A: compile ---
cache = smp_compile_event(TOP_LEVEL_DIR, TEAM_FILTER, channels, ...
                          season, driver_map, alias, compile_opts);

% --- Option B: load only ---
% cache = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

%% =========================================================
%  SECTION 5: QUALIFYING FUEL ANALYSIS
%  Groups manifest rows by (CarNumber + Driver + Session),
%  loads all stints per group, concatenates with
%  concat_sessions, slices laps, and calls quali_fuel_analysis.
% =========================================================

fprintf('\n=== Qualifying Fuel Analysis — %s %s ===\n\n', TRACK, strjoin(SESSION_FILTER, '/'));

% Filter manifest to qualifying rows
mf          = cache.manifest;
sess_labels = string(mf.Session);
sess_match  = false(height(mf), 1);
for s = 1:numel(SESSION_FILTER)
    sess_match = sess_match | strcmpi(sess_labels, SESSION_FILTER{s});
end
mf_quali = mf(sess_match, :);

if height(mf_quali) == 0
    fprintf('[!] No rows found in manifest for session(s): %s\n', strjoin(SESSION_FILTER, ', '));
    fprintf('    Available sessions: %s\n', strjoin(unique(sess_labels), ', '));
    return
end

% ---- Group manifest rows by (CarNumber + Driver + Session) ----
% This replicates smp_append_stints grouping without re-scanning disk.
car_col    = strtrim(string(mf_quali.CarNumber));
driver_col = strtrim(string(mf_quali.Driver));
sess_col   = strtrim(string(mf_quali.Session));
group_keys = car_col + "_" + driver_col + "_" + sess_col;
unique_grp = unique(group_keys, 'stable');

fprintf('Found %d group(s) to analyse (%d manifest row(s) total).\n\n', ...
    numel(unique_grp), height(mf_quali));

% concat_sessions options — drop duplicate/superset stints automatically
concat_opts.uniqueFingerprint = true;

% Pre-allocate output containers
results   = struct();
summaries = table();

for g = 1:numel(unique_grp)
    grp_mask = strcmp(group_keys, unique_grp{g});
    grp_rows = mf_quali(grp_mask, :);

    % Sort largest file first so concat_sessions sees the combined/superset
    % file as the reference (R) before evaluating smaller stints as duplicates.
    grp_rows = sortrows(grp_rows, 'FileSize', 'descend');

    driver = strtrim(char(string(grp_rows.Driver(1))));
    car    = strtrim(char(string(grp_rows.CarNumber(1))));
    sess   = strtrim(char(string(grp_rows.Session(1))));
    n_stints = height(grp_rows);

    fprintf('[%d/%d]  Car %s  |  %s  |  %s  (%d stint(s))\n', ...
        g, numel(unique_grp), car, driver, sess, n_stints);

    % Load all stints for this group
    % Pass {} as second arg so all channels (incl. GPS_Time) are available
    % for concat_sessions fingerprint duplicate detection.
    all_sess = cell(n_stints, 1);
    load_ok  = true;
    for si = 1:n_stints
        fpath = char(grp_rows.Path(si));
        [~, fn, ext] = fileparts(fpath);
        fprintf('  Stint %d: %s%s\n', si, fn, ext);
        try
            all_sess{si} = motec_ld_reader(fpath, {});
        catch ME
            fprintf('  [ERROR] Load failed: %s\n', ME.message);
            load_ok = false;
        end
    end
    if ~load_ok, fprintf('\n'); continue; end

    % Concatenate stints — handles multi-file outings; drops duplicates
    if n_stints > 1
        try
            session = concat_sessions(all_sess, concat_opts);
            fprintf('  Stints concatenated.\n');
        catch ME
            fprintf('  [ERROR] concat_sessions failed: %s\n', ME.message);
            fprintf('\n'); continue
        end
    else
        session = all_sess{1};
    end

    % Slice laps using BR2-aware opts
    laps = lap_slicer(session, lap_slicer_opts);

    n_flying = sum(strcmp({laps.lap_type}, 'flying'));
    fprintf('  Laps sliced: %d total,  %d flying\n', numel(laps), n_flying);

    if n_flying == 0
        fprintf('  [SKIP] No flying laps — skipping.\n\n');
        continue
    end

    % Run analysis (suppress per-car plots — combined plot drawn in Section 8)
    try
        [result, summary, tbl] = quali_fuel_analysis(laps, session, struct('plot', false));
    catch ME
        fprintf('  [ERROR] quali_fuel_analysis failed: %s\n', ME.message);
        fprintf('\n'); continue
    end

    % Store results
    car_key = matlab.lang.makeValidName(sprintf('Car%s_%s', car, driver));
    results.(car_key).result  = result;
    results.(car_key).summary = summary;
    results.(car_key).tbl     = tbl;
    results.(car_key).driver  = driver;
    results.(car_key).car     = car;
    results.(car_key).session = sess;

    % Accumulate summary row
    new_row = table( ...
        string(car), string(driver), string(sess), ...
        summary.n_flying_laps, summary.n_tyre_changes, ...
        'VariableNames', {'Car','Driver','Session','FlyingLaps','TyreChanges'});
    summaries = [summaries; new_row]; %#ok<AGROW>

    fprintf('  Flying laps: %d   Tyre changes: %d\n\n', ...
        summary.n_flying_laps, summary.n_tyre_changes);
end

%% =========================================================
%  SECTION 6: SUMMARY TABLE
% =========================================================

fprintf('\n=== Summary ===\n');
if ~isempty(summaries)
    disp(summaries);
else
    fprintf('No results to display.\n');
end

%% =========================================================
%  SECTION 7: RESULTS POP-UP
%  Blocking figure — one tab per car with lap table and
%  tyre pressure axes; combined all-cars tab appended.
%  Close the figure or press Enter to continue.
% =========================================================

car_keys = fieldnames(results);
n_cars   = numel(car_keys);
if n_cars == 0
    fprintf('No results to display.\n');
    return
end

% Also print to command window for reference
for ci = 1:n_cars
    key = car_keys{ci};
    fprintf('\n--- Car %s  |  %s  |  %s ---\n', ...
        results.(key).car, results.(key).driver, results.(key).session);
    disp(results.(key).tbl);
end

report_title = sprintf('%s  %s', TRACK, strjoin(SESSION_FILTER, '/'));
if SHOW_REPORT
    quali_show_report(results, report_title);
end

%% =========================================================
%  SECTION 7b: CSV EXPORT — all laps, all drivers
%  Writes one CSV per session to TOP_LEVEL_DIR named:
%    quali_fuel_<TRACK>_<SESSION>.csv
% =========================================================

if n_cars > 0
    for s = 1:numel(SESSION_FILTER)
        sess_label = SESSION_FILTER{s};
        all_rows   = table();

        for ci = 1:n_cars
            key = car_keys{ci};
            if ~strcmpi(results.(key).session, sess_label), continue; end

            t = results.(key).tbl;
            n_rows = height(t);

            Car    = repmat(string(results.(key).car),    n_rows, 1);
            Driver = repmat(string(results.(key).driver), n_rows, 1);
            Sess   = repmat(string(sess_label),           n_rows, 1);

            t_export = removevars(t, 'LapTime');   % keep LapTime_s (seconds) only
            all_rows = [all_rows; [table(Car, Driver, Sess), t_export]]; %#ok<AGROW>
        end

        if isempty(all_rows)
            fprintf('[CSV] No rows for session %s — skipped.\n', sess_label);
            continue
        end

        csv_name = sprintf('quali_fuel_%s_%s.csv', TRACK, sess_label);
        csv_path = fullfile(TOP_LEVEL_DIR, csv_name);
        writetable(all_rows, csv_path);
        fprintf('[CSV] Exported %d row(s) → %s\n', height(all_rows), csv_path);
    end
end

%% =========================================================
%  SECTION 8: LIFT-AND-COAST (qualifying session)
%  Runs LiftAndCoast for the qualifying session to identify
%  coasting opportunities on the flying lap.
%
%  Set DRIVER_TLA to focus on one driver, or '' for the
%  global fastest lap in the session.
%
%  Uses the same BR2_PROTOCOL set in Section 2.
% =========================================================

DRIVER_TLA = '';   % e.g. 'JAC', or '' for global fastest

for s = 1:numel(SESSION_FILTER)
    fprintf('\n=== LiftAndCoast: %s  %s ===\n', EVENT_CODE, SESSION_FILTER{s});
    try
        LiftAndCoast(EVENT_CODE, ...
            'year',         YEAR, ...
            'session_id',   SESSION_FILTER{s}, ...
            'driver_tla',   DRIVER_TLA, ...
            'br2_protocol', BR2_PROTOCOL, ...
            'compile',      false, ...
            'rerun',        false, ...
            'visible',      true);
    catch ME
        fprintf('  [ERROR] LiftAndCoast failed for %s: %s\n', SESSION_FILTER{s}, ME.message);
    end
end
