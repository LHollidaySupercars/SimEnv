%% debug_speed_trap_match.m
% Diagnoses lap-matching in smp_match_speed_trap step-by-step.
% Edit the CONFIGURATION section below, then run section-by-section (Ctrl+Enter).

%% ── CONFIGURATION ────────────────────────────────────────────────────────────
cache_dir       = 'E:\2026\04_RUA\_TeamData';
timing_base_dir = 'E:\2026\99_seasonTiming';
event           = 'RUA';
session         = 'R11';      % MoTeC cache session name
timing_session  = '';          % timing CSV session name — leave '' to match session above; set e.g. 'QR11' if PDF was extracted with a different label
report_type     = 'pit_speed';   % 'top_speed' | 'pit_speed'
SKIP_PIT_LAP    = false;         % true = exclude pit speed traps from matching
car_filter      = '88';          % '' = all cars, or e.g. '88' to narrow down
speed_channel   = 'Ground_Speed';
TEAM_FILTER     = {'T8R'};

% Recompile config — only used in the RECOMPILE section below
FORCE_RECOMPILE  = true;               % set true to force even if cache exists
TRACE_CARS_KEEP  = {'88', '888'};       % cars to keep traces for (others stripped to save RAM)
CHANNELS_FILE    = 'C:\SimEnv\dataAcquisition\Motec_MP\channels\channels.xlsx';
EVENT_ALIAS      = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\eventAlias.xlsx';
DRIVER_ALIAS     = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\driverAlias.xlsx';
SEASON_FILE      = 'C:\SimEnv\trackDB\seasonOverview.xlsx';

%% ── RECOMPILE (optional) ─────────────────────────────────────────────────────
% Run this section to do a full recompile using the current lap_slicer,
% strip traces for cars outside TRACE_CARS_KEEP, then save — keeps the .mat lean.
% Skip this section if the cache already exists and you just want to debug.

if ~exist('cache_dir', 'var')
    error('Run the CONFIGURATION section first (Ctrl+Enter on that cell).');
end

fprintf('\n=== RECOMPILE: %s | %s ===\n', event, session);

cache_file = fullfile(cache_dir, ['smp_cache_' session '.mat']);
if ~FORCE_RECOMPILE && isfile(cache_file)
    fprintf('  Cache file exists — skipping recompile.\n');
    fprintf('  Set FORCE_RECOMPILE = true to override.\n');
else
    fprintf('  Loading config files...\n');
    season_s               = smp_season_load(SEASON_FILE);
    [channels_s, ch_rules] = smp_channel_config_load(CHANNELS_FILE);
    alias_s                = smp_alias_load(EVENT_ALIAS);
    driver_map_s           = smp_driver_alias_load(DRIVER_ALIAS);

    c_opts = struct();
    c_opts.mode              = 'stream';
    c_opts.verbose           = true;
    c_opts.saveCache         = false;   % save manually after trace trim
    c_opts.save_mode         = 'session';
    c_opts.session_filter    = {session};
    c_opts.uniqueFingerprint = true;
    c_opts.channel_rules     = ch_rules;
    c_opts.detect_pitlane    = true;
    c_opts.all_laps          = true;   % store all lap types (not just flying) for speed trap correlation
    c_opts.max_traces        = Inf;    % no cap on number of laps stored

    fprintf('  Compiling (uses current lap_slicer on disk)...\n');
    cache = smp_compile_event(cache_dir,TEAM_FILTER, channels_s, season_s, driver_map_s, alias_s, c_opts);
    fprintf('  Compile complete — %d manifest rows.\n', height(cache.manifest));

    % ── Strip traces for cars not in TRACE_CARS_KEEP ─────────────────────────
    fprintf('  Trimming traces to cars: %s\n', strjoin(TRACE_CARS_KEEP, ', '));
    mf_all     = cache.manifest;
    mf_car_all = strtrim(string(mf_all.CarNumber));
    mf_gk_all  = string(mf_all.GroupKey);

    keep_mask = false(height(mf_all), 1);
    for ki = 1:numel(TRACE_CARS_KEEP)
        keep_mask = keep_mask | strcmpi(mf_car_all, TRACE_CARS_KEEP{ki});
    end
    keep_gks = unique(mf_gk_all(keep_mask));
    drop_gks = unique(mf_gk_all(~keep_mask));

    for di = 1:numel(drop_gks)
        gk = char(drop_gks(di));
        if isfield(cache.traces, gk)
            cache.traces = rmfield(cache.traces, gk);
        end
    end
    fprintf('  Kept %d group keys, dropped %d.\n', numel(keep_gks), numel(drop_gks));

    fprintf('  Saving...\n');
    smp_cache_save(cache_dir, cache, 'session', alias_s);
    fprintf('  Saved.\n');
end

%% ── 1. LOAD CACHE ────────────────────────────────────────────────────────────
fprintf('\n=== STEP 1: Load cache ===\n');
if ~exist('cache', 'var') || isempty(cache)
    fprintf('  cache not in workspace — loading via smp_cache_load...\n');
    cache = smp_cache_load(cache_dir, {session});
else
    fprintf('  cache already in workspace — skipping load.\n');
end
fprintf('  manifest rows : %d\n', height(cache.manifest));
fprintf('  group keys    : %d\n', numel(fieldnames(cache.traces)));

% Resolve effective timing session label
if isempty(timing_session)
    timing_session = session;
end

%% ── 2. RESOLVE TIMING CSV ────────────────────────────────────────────────────
fprintf('\n=== STEP 2: Resolve timing CSV ===\n');
fprintf('  cache session   : %s\n', session);
fprintf('  timing session  : %s\n', timing_session);
if strcmp(report_type, 'pit_speed')
    kph_col  = 's1_kph';
    type_sub = 'pit_speed';
    suffix   = '_speed_trap.csv';
else
    kph_col  = 'kph';
    type_sub = 'top_speed';
    suffix   = '_topspeed.csv';
end

d = dir(fullfile(timing_base_dir, ['*_' upper(event)]));
d = d([d.isdir]);
if isempty(d)
    error('No folder matching *_%s under %s', upper(event), timing_base_dir);
end
master_csv = fullfile(timing_base_dir, d(1).name, type_sub, [timing_session suffix]);
fprintf('  CSV path      : %s\n', master_csv);
if ~isfile(master_csv)
    error('CSV not found: %s', master_csv);
end

%% ── 2b. PIT SPEED CSV INSPECTION ─────────────────────────────────────────────
fprintf('\n=== STEP 2b: Pit speed CSV inspection ===\n');
d_pit2b = dir(fullfile(timing_base_dir, ['*_' upper(event)]));
d_pit2b = d_pit2b([d_pit2b.isdir]);
pit_csv_path = '';
if ~isempty(d_pit2b)
    pit_speed_dir_2b = fullfile(timing_base_dir, d_pit2b(1).name, 'pit_speed');
    % Try exact timing_session name first, then glob for any CSV containing session
    candidate_2b = fullfile(pit_speed_dir_2b, [timing_session '_speed_trap.csv']);
    if isfile(candidate_2b)
        pit_csv_path = candidate_2b;
    else
        % Fallback: find a file whose name contains session (e.g. QR11 when timing_session=Q11)
        glob_2b = dir(fullfile(pit_speed_dir_2b, '*_speed_trap.csv'));
        for gi2b = 1:numel(glob_2b)
            if contains(glob_2b(gi2b).name, session, 'IgnoreCase', true)
                pit_csv_path = fullfile(pit_speed_dir_2b, glob_2b(gi2b).name);
                fprintf('  *** filename fallback: using %s\n', glob_2b(gi2b).name);
                break;
            end
        end
    end
end
fprintf('  pit CSV : %s\n', pit_csv_path);
if ~isempty(pit_csv_path) && isfile(pit_csv_path)
    T_pit2b = readtable(pit_csv_path, 'Delimiter', ',', 'TextType', 'string');
    if ismember('parse_error', T_pit2b.Properties.VariableNames)
        T_pit2b = T_pit2b(~strcmpi(string(T_pit2b.parse_error), 'true'), :);
    end
    % Resolve session name inside CSV (may differ from timing_session)
    pit2b_ses = timing_session;
    if ismember('session', T_pit2b.Properties.VariableNames)
        csv_ses_u2b = unique(string(T_pit2b.session));
        if ~any(strcmpi(csv_ses_u2b, timing_session))
            for asi2b = 1:numel(csv_ses_u2b)
                if contains(csv_ses_u2b(asi2b), session, 'IgnoreCase', true) || ...
                   contains(session, csv_ses_u2b(asi2b), 'IgnoreCase', true)
                    pit2b_ses = char(csv_ses_u2b(asi2b));
                    fprintf('  *** session in CSV: ''%s'' (auto-matched from ''%s'')\n', pit2b_ses, session);
                    break;
                end
            end
        end
    end
    T_pit2b = T_pit2b(strcmpi(string(T_pit2b.session), pit2b_ses), :);
    fprintf('  rows (timing session %s) : %d\n', pit2b_ses, height(T_pit2b));
    pvars_2b   = T_pit2b.Properties.VariableNames;
    pit_kph_2b = pvars_2b(~cellfun(@isempty, regexp(pvars_2b, '^s\d+_kph$')));
    fprintf('  pit trap columns  : %s\n', strjoin(pit_kph_2b, ', '));
    if height(T_pit2b) > 0
        T_pit2b.car = strtrim(string(T_pit2b.car));
        pit_cars_2b = unique(T_pit2b.car);
        for pc2b = 1:numel(pit_cars_2b)
            c2b    = pit_cars_2b(pc2b);
            laps2b = T_pit2b.lap(T_pit2b.car == c2b);
            if ~isnumeric(laps2b), laps2b = str2double(string(laps2b)); end
            laps2b = sort(laps2b);
            fprintf('    car %-5s : %d entries, laps %g–%g\n', ...
                c2b, numel(laps2b), min(laps2b), max(laps2b));
        end
    end
else
    fprintf('  *** pit CSV not found\n');
    pit_csv_path = '';
end

%% ── 3. LOAD & FILTER CSV ─────────────────────────────────────────────────────
fprintf('\n=== STEP 3: Load and filter CSV ===\n');
T = readtable(master_csv, 'Delimiter', ',', 'TextType', 'string');
fprintf('  raw rows      : %d\n', height(T));
fprintf('  filtering on  : event=''%s''  timing_session=''%s''\n', event, timing_session);
if height(T) > 0 && ismember('session', T.Properties.VariableNames)
    raw_ses_vals = unique(string(T.session));
    fprintf('  session values in CSV : %s\n', strjoin(raw_ses_vals, ', '));
end

if ismember('parse_error', T.Properties.VariableNames)
    T = T(~strcmpi(string(T.parse_error), 'true'), :);
    fprintf('  after error strip: %d\n', height(T));
end

T = T(strcmpi(string(T.event), event), :);
T = T(strcmpi(string(T.session), timing_session), :);
fprintf('  after filter  : %d rows (event=%s, timing_session=%s)\n', height(T), event, timing_session);

if height(T) == 0 && ismember('session', T.Properties.VariableNames) || ...
   (height(T) == 0 && exist('T', 'var'))
    % Auto-fallback: find a CSV session that contains session as a substring
    T_raw2 = readtable(master_csv, 'Delimiter', ',', 'TextType', 'string');
    if ismember('parse_error', T_raw2.Properties.VariableNames)
        T_raw2 = T_raw2(~strcmpi(string(T_raw2.parse_error), 'true'), :);
    end
    T_raw2 = T_raw2(strcmpi(string(T_raw2.event), event), :);
    if ismember('session', T_raw2.Properties.VariableNames) && height(T_raw2) > 0
        csv_ses_vals = unique(string(T_raw2.session));
        % Try: CSV session contains timing_session (e.g. 'QR11' contains 'Q11')
        %   or timing_session contains CSV session
        auto_match = '';
        for asi = 1:numel(csv_ses_vals)
            sv = csv_ses_vals(asi);
            if contains(sv, timing_session, 'IgnoreCase', true) || ...
               contains(timing_session, sv, 'IgnoreCase', true)
                auto_match = char(sv);
                break;
            end
        end
        if ~isempty(auto_match)
            fprintf('  *** auto-matched timing_session ''%s'' → CSV session ''%s''\n', ...
                timing_session, auto_match);
            fprintf('      Set timing_session = ''%s'' in CONFIGURATION to suppress this message.\n', auto_match);
            timing_session = auto_match;
            T = T_raw2(strcmpi(string(T_raw2.session), timing_session), :);
            fprintf('  after auto-fallback filter : %d rows\n', height(T));
        else
            combo = unique(strcat(string(T_raw2.event), '/', string(T_raw2.session)));
            fprintf('  *** no rows match — event/session values present in CSV:\n');
            for ci2 = 1:numel(combo)
                fprintf('        %s\n', combo(ci2));
            end
        end
    end
end

T.car = strtrim(string(T.car));
if ~isnumeric(T.lap),          T.lap          = str2double(string(T.lap));          end
if ismember(kph_col, T.Properties.VariableNames) && ~isnumeric(T.(kph_col))
    T.(kph_col) = str2double(string(T.(kph_col)));
end

if ~isempty(car_filter)
    T = T(strcmp(T.car, car_filter), :);
    fprintf('  after car filter (%s): %d rows\n', car_filter, height(T));
end

if height(T) == 0
    error('No CSV rows remain after filtering — check event/session values printed above.');
end

%% ── 4. INSPECT MANIFEST ──────────────────────────────────────────────────────
fprintf('\n=== STEP 4: Manifest entries for session ''%s'' ===\n', session);
mf     = cache.manifest;
mf_car = strtrim(string(mf.CarNumber));
mf_ses = string(mf.Session);
mf_gk  = string(mf.GroupKey);

ses_mask = strcmpi(mf_ses, session);
mf_sub   = mf(ses_mask, :);
fprintf('  manifest rows in session: %d\n', height(mf_sub));
if height(mf_sub) > 0
    disp(mf_sub(:, intersect({'CarNumber','Driver','Session','GroupKey'}, ...
                              mf_sub.Properties.VariableNames)));
end

%% ── 5. MANIFEST MATCH PER CSV ROW ────────────────────────────────────────────
fprintf('\n=== STEP 5: Manifest lookup per CSV row ===\n');
csv_cars = unique(T.car);
for ci = 1:numel(csv_cars)
    car_str  = csv_cars(ci);
    car_mask = strcmpi(mf_car, car_str);
    gks      = unique(mf_gk(car_mask & ses_mask));
    fprintf('  car %-5s → %d group key(s): %s\n', ...
        car_str, numel(gks), strjoin(gks, ', '));
    if numel(gks) == 0
        fprintf('    *** NO MANIFEST MATCH — car string mismatch? CSV has ''%s'', manifest has: %s\n', ...
            car_str, strjoin(unique(mf_car(ses_mask)), ', '));
    end
end

%% ── 6. LAP NUMBER INSPECTION ─────────────────────────────────────────────────
fprintf('\n=== STEP 6: Lap numbers in traces vs CSV ===\n');
csv_cars = unique(T.car);
for ci = 1:numel(csv_cars)
    car_str  = csv_cars(ci);
    car_mask = strcmpi(mf_car, car_str);
    gks      = unique(mf_gk(car_mask & ses_mask));
    csv_laps = sort(T.lap(T.car == car_str))';

    fprintf('\n  Car %s\n', car_str);
    fprintf('    CSV laps : %s\n', num2str(csv_laps));

    for gi = 1:numel(gks)
        gk = char(gks(gi));
        if ~isfield(cache.traces, gk)
            fprintf('    [%s] *** group key not found in traces\n', gk);
            continue;
        end
        tr       = cache.traces.(gk);
        tr_laps  = sort(tr.lap_numbers);
        in_both  = intersect(csv_laps, tr_laps);
        only_csv = setdiff(csv_laps, tr_laps);
        fprintf('    [%s]\n', gk);
        fprintf('      trace laps  : %s\n', num2str(tr_laps));
        fprintf('      matched     : %s\n', num2str(in_both));
        if ~isempty(only_csv)
            fprintf('      CSV-only (unmatched): %s\n', num2str(only_csv));
        end
    end
end

%% ── 6b. LAP TYPES IN TRACES ──────────────────────────────────────────────────
fprintf('\n=== STEP 6b: Lap types stored in traces ===\n');
all_gk_names = fieldnames(cache.traces);
for gi = 1:numel(all_gk_names)
    gk = all_gk_names{gi};
    tr = cache.traces.(gk);
    if ~isfield(tr, 'lap_numbers'), continue; end
    lap_nums = tr.lap_numbers;
    n_laps   = numel(lap_nums);
    if isfield(tr, 'lap_types') && numel(tr.lap_types) == n_laps
        types = tr.lap_types;
    elseif isfield(tr, 'lap_types')
        types = repmat({'(none)'}, 1, n_laps);
        fprintf('  [%s]  *** lap_types length mismatch: %d laps vs %d types\n', ...
            gk, n_laps, numel(tr.lap_types));
    else
        types = repmat({'(none)'}, 1, n_laps);
        fprintf('  [%s]  *** lap_types field MISSING\n', gk);
    end
    fprintf('  [%s]\n', gk);
    for li = 1:n_laps
        if isfield(tr, 'lap_times') && numel(tr.lap_times) == n_laps
            fprintf('    lap %2d  type: %-10s  time: %.3f s\n', lap_nums(li), types{li}, tr.lap_times(li));
        else
            fprintf('    lap %2d  type: %s\n', lap_nums(li), types{li});
        end
    end
    % ── inlap → pitlap pairing ────────────────────────────────────────────
    [sorted_lnums_6b, srt_6b] = sort(lap_nums(:));
    sorted_types_6b = types(srt_6b);
    fprintf('    -- inlap→pitlap pairs --\n');
    found_pair_6b = false;
    for li = 1:numel(sorted_lnums_6b)
        if strcmpi(sorted_types_6b{li}, 'inlap')
            found_pair_6b = true;
            next_pit_6b = [];
            for lj = li+1:numel(sorted_lnums_6b)
                if strcmpi(sorted_types_6b{lj}, 'pitlap')
                    next_pit_6b = sorted_lnums_6b(lj);
                    break;
                end
            end
            if ~isempty(next_pit_6b)
                fprintf('    inlap lap %2d → pitlap lap %2d\n', sorted_lnums_6b(li), next_pit_6b);
            else
                fprintf('    inlap lap %2d → *** no following pitlap\n', sorted_lnums_6b(li));
            end
        end
    end
    if ~found_pair_6b
        fprintf('    (no inlaps found)\n');
    end
end

%% ── 7. CHANNEL PRESENCE CHECK ────────────────────────────────────────────────
fprintf('\n=== STEP 7: Channel ''%s'' present in traces? ===\n', speed_channel);
ch_valid = matlab.lang.makeValidName(speed_channel);
gk_names = fieldnames(cache.traces);
n_with    = 0;
n_without = 0;
for gi = 1:numel(gk_names)
    gk = gk_names{gi};
    tr = cache.traces.(gk);
    if isfield(tr, ch_valid)
        n_with = n_with + 1;
    else
        n_without = n_without + 1;
        fprintf('  MISSING in [%s]\n', gk);
    end
end
fprintf('  present in %d / %d group keys\n', n_with, n_with + n_without);

%% ── 8. FULL MATCH ────────────────────────────────────────────────────────────
fprintf('\n=== STEP 8: Run smp_match_speed_trap ===\n');

% ── Resolve top_speed CSV (always needed for combined output) ─────────────
d8 = dir(fullfile(timing_base_dir, ['*_' upper(event)]));
d8 = d8([d8.isdir]);
if isempty(d8)
    error('No folder matching *_%s under %s', upper(event), timing_base_dir);
end
topspeed_csv_8 = fullfile(timing_base_dir, d8(1).name, 'top_speed', [timing_session '_topspeed.csv']);
if ~isfile(topspeed_csv_8)
    fprintf('  *** top_speed CSV not found: %s\n', topspeed_csv_8);
    topspeed_csv_8 = '';
else
    fprintf('  top_speed CSV : %s\n', topspeed_csv_8);
end

opts_base = struct();
opts_base.event           = event;
opts_base.session         = timing_session;
opts_base.report_type     = 'both';
opts_base.timing_base_dir = timing_base_dir;
opts_base.speed_channel   = speed_channel;
opts_base.skip_pit_lap    = SKIP_PIT_LAP;
if ~isempty(topspeed_csv_8)
    opts_base.master_csv  = topspeed_csv_8;
end

if SKIP_PIT_LAP
    fprintf('  SKIP_PIT_LAP = true — pit speed trap rows excluded\n');
    T_match = smp_match_speed_trap(cache, opts_base);
    T_match.trap_col = repmat("top_speed", height(T_match), 1);
else
    % ── Use pit_csv_path resolved in section 2b (resolve here if skipped) ──
    if ~exist('pit_csv_path', 'var') || isempty(pit_csv_path)
        pit_speed_dir_8 = fullfile(timing_base_dir, d8(1).name, 'pit_speed');
        candidate_8 = fullfile(pit_speed_dir_8, [timing_session '_speed_trap.csv']);
        if isfile(candidate_8)
            pit_csv_path = candidate_8;
        else
            glob_8 = dir(fullfile(pit_speed_dir_8, '*_speed_trap.csv'));
            pit_csv_path = '';
            for gi8 = 1:numel(glob_8)
                if contains(glob_8(gi8).name, session, 'IgnoreCase', true)
                    pit_csv_path = fullfile(pit_speed_dir_8, glob_8(gi8).name);
                    break;
                end
            end
        end
    end
    fprintf('  pit_speed CSV : %s\n', pit_csv_path);
    pit_trap_cols_8 = {};
    if ~isempty(pit_csv_path) && isfile(pit_csv_path)
        T_pit8 = readtable(pit_csv_path, 'Delimiter', ',', 'TextType', 'string');
        % session value in pit CSV may differ — auto-match
        if ismember('session', T_pit8.Properties.VariableNames)
            csv_ses_8 = unique(string(T_pit8.session));
            pit_ses_8 = timing_session;
            if ~any(strcmpi(csv_ses_8, timing_session))
                for asi8 = 1:numel(csv_ses_8)
                    if contains(csv_ses_8(asi8), session, 'IgnoreCase', true) || ...
                       contains(session, csv_ses_8(asi8), 'IgnoreCase', true)
                        pit_ses_8 = char(csv_ses_8(asi8));
                        break;
                    end
                end
            end
            T_pit8 = T_pit8(strcmpi(string(T_pit8.session), pit_ses_8), :);
        end
        pvars8 = T_pit8.Properties.VariableNames;
        pit_trap_cols_8 = pvars8(~cellfun(@isempty, regexp(pvars8, '^s\d+_kph$')));
        if isempty(pit_trap_cols_8)
            pit_trap_cols_8 = pvars8(~cellfun(@isempty, regexpi(pvars8, 'kph')));
        end
        fprintf('  pit trap columns : %s\n', strjoin(pit_trap_cols_8, ', '));
        opts_base.master_pit_csv = pit_csv_path;
    else
        fprintf('  *** pit_speed CSV NOT FOUND — top_speed only\n');
    end

    % ── First call: both (top_speed + first pit trap) ─────────────────────
    T_parts = {};
    opts1 = opts_base;
    if ~isempty(pit_trap_cols_8)
        opts1.pit_trap_col = pit_trap_cols_8{1};
        opts1.pit_trap_n   = 1;
    end
    T1 = smp_match_speed_trap(cache, opts1);
    T1.trap_col = strings(height(T1), 1);
    is_pit1 = strcmp(string(T1.trap_type), 'pit_speed');
    T1.trap_col(~is_pit1) = "top_speed";
    if ~isempty(pit_trap_cols_8)
        T1.trap_col(is_pit1) = string(pit_trap_cols_8{1});
    else
        T1.trap_col(is_pit1) = "pit_speed";
    end
    T_parts{end+1} = T1;
    n_top = sum(~is_pit1); n_pit = sum(is_pit1);
    fprintf('  [top_speed] %d rows, %d matched\n', n_top, sum(T1.matched(~is_pit1)));
    if ~isempty(pit_trap_cols_8)
        fprintf('  [%s]    %d rows, %d matched\n', pit_trap_cols_8{1}, n_pit, sum(T1.matched(is_pit1)));
    end

    % ── Additional pit trap columns (s2_kph, s3_kph, ...) ────────────────
    for tc8 = 2:numel(pit_trap_cols_8)
        opts_tc = opts_base;
        opts_tc.report_type  = 'pit_speed';
        opts_tc.pit_trap_col = pit_trap_cols_8{tc8};
        opts_tc.pit_trap_n   = tc8;
        T_tc = smp_match_speed_trap(cache, opts_tc);
        T_tc.trap_col = repmat(string(pit_trap_cols_8{tc8}), height(T_tc), 1);
        T_parts{end+1} = T_tc;
        fprintf('  [%s]    %d rows, %d matched\n', pit_trap_cols_8{tc8}, height(T_tc), sum(T_tc.matched));
    end

    T_match = vertcat(T_parts{:});
end

n_matched   = sum(T_match.matched);
n_total     = height(T_match);
fprintf('  total rows : %d\n', n_total);
fprintf('  matched    : %d  (%.0f%%)\n', n_matched, 100*n_matched/max(n_total,1));
fprintf('  unmatched  : %d\n', n_total - n_matched);

%% ── 9. RESULTS TABLE ─────────────────────────────────────────────────────────
fprintf('\n=== STEP 9: Results ===\n');
if ~isempty(car_filter)
    T_display = T_match(strcmp(T_match.car, car_filter), :);
    fprintf('  (filtered to car %s — %d rows)\n', car_filter, height(T_display));
else
    T_display = T_match;
end
disp(T_display);

%% ── 9b. PIT SPEED SUMMARY TABLE ──────────────────────────────────────────────
fprintf('\n=== STEP 9b: Pit speed summary (one row per pit entry) ===\n');
T_pit_disp = T_display(strcmp(string(T_display.trap_type), 'pit_speed') & T_display.matched, :);
if height(T_pit_disp) == 0
    fprintf('  No matched pit_speed rows to summarise.\n');
else
    % Build compact summary: timing lap, timing kph, motec lap, motec inlap kph, delta, wheel speeds
    ws_cols_9b = T_pit_disp.Properties.VariableNames(...
        ~cellfun(@isempty, regexp(T_pit_disp.Properties.VariableNames, '^ws_')));
    has_ws = ~isempty(ws_cols_9b);

    fprintf('  %-6s  %-6s  %-10s  %-10s  %-10s  %-10s', ...
        'TLap', 'MLap', 'Timing_kph', 'Motec_kph', 'Delta_kph', 'LapType');
    if has_ws
        for wi9 = 1:numel(ws_cols_9b)
            lbl9 = strrep(ws_cols_9b{wi9}, 'ws_wheelspeed', 'WS_');
            lbl9 = strrep(lbl9, 'ws_wheel_speed_', 'WS_');
            fprintf('  %-8s', lbl9);
        end
    end
    fprintf('\n');

    for ri9 = 1:height(T_pit_disp)
        row9 = T_pit_disp(ri9, :);
        fprintf('  %-6g  %-6g  %-10.1f  %-10.1f  %-10.1f  %-10s', ...
            row9.lap, row9.motec_lap, row9.timing_kph, row9.motec_kph, row9.delta_kph, ...
            char(row9.motec_lap_type));
        if has_ws
            for wi9 = 1:numel(ws_cols_9b)
                fprintf('  %-8.1f', row9.(ws_cols_9b{wi9}));
            end
        end
        fprintf('\n');
    end
end
T_ok = T_display(T_display.matched, :);
if height(T_ok) > 0
    if ismember('trap_col', T_ok.Properties.VariableNames)
        trap_groups_9 = unique(T_ok.trap_col);
        for tgi9 = 1:numel(trap_groups_9)
            tg9  = trap_groups_9(tgi9);
            tgm9 = T_ok(T_ok.trap_col == tg9, :);
            fprintf('\n  [trap: %s]  %d matched rows — delta_kph:\n', tg9, height(tgm9));
            fprintf('    mean  : %.2f\n', mean(tgm9.delta_kph, 'omitnan'));
            fprintf('    std   : %.2f\n', std(tgm9.delta_kph,  'omitnan'));
            fprintf('    min   : %.2f\n', min(tgm9.delta_kph,  [], 'omitnan'));
            fprintf('    max   : %.2f\n', max(tgm9.delta_kph,  [], 'omitnan'));
        end
    else
        fprintf('\n  Matched rows — delta_kph stats:\n');
        fprintf('    mean  : %.2f\n', mean(T_ok.delta_kph,   'omitnan'));
        fprintf('    std   : %.2f\n', std(T_ok.delta_kph,    'omitnan'));
        fprintf('    min   : %.2f\n', min(T_ok.delta_kph,    [], 'omitnan'));
        fprintf('    max   : %.2f\n', max(T_ok.delta_kph,    [], 'omitnan'));
    end
end

%% ── 10. VISUALISATION ──────────────────────────────────────────────────────
if height(T_match) == 0
    fprintf('No data to plot.\n');
else
    cars_all  = unique(T_match.car);
    n_cars    = numel(cars_all);
    cmap      = lines(n_cars);

    fig = figure('Name', 'Speed Trap Debug', 'NumberTitle', 'off', ...
                 'Position', [100 80 1200 800]);

    % ── Panel 1: timing vs MoTeC scatter (matched only) ──────────────────────
    ax1 = subplot(2, 2, 1);
    hold(ax1, 'on');
    T_ok = T_match(T_match.matched, :);
    trap_markers_10 = {'o', '^', 's', 'd', 'p'};
    has_tc_10 = ismember('trap_col', T_ok.Properties.VariableNames);
    trap_grps_10 = {};
    if has_tc_10, trap_grps_10 = cellstr(unique(T_ok.trap_col)); end
    for ci = 1:n_cars
        car_str = cars_all(ci);
        if has_tc_10
            for tgi = 1:numel(trap_grps_10)
                mask = T_ok.car == car_str & strcmp(cellstr(T_ok.trap_col), trap_grps_10{tgi});
                if ~any(mask), continue; end
                mkr10 = trap_markers_10{min(tgi, numel(trap_markers_10))};
                lbl10 = sprintf('%s [%s]', char(car_str), trap_grps_10{tgi});
                scatter(ax1, T_ok.timing_kph(mask), T_ok.motec_kph(mask), 50, ...
                    cmap(ci,:), mkr10, 'filled', 'DisplayName', lbl10);
            end
        else
            mask = T_ok.car == car_str;
            if ~any(mask), continue; end
            scatter(ax1, T_ok.timing_kph(mask), T_ok.motec_kph(mask), 50, ...
                cmap(ci,:), 'filled', 'DisplayName', char(car_str));
        end
    end
    % y = x reference
    ax1_lims = [min([ax1.XLim(1) ax1.YLim(1)]) max([ax1.XLim(2) ax1.YLim(2)])];
    plot(ax1, ax1_lims, ax1_lims, 'k--', 'HandleVisibility', 'off');
    xlabel(ax1, 'Timing kph'); ylabel(ax1, 'MoTeC kph');
    title(ax1, 'Timing vs MoTeC (matched)');
    legend(ax1, 'Location', 'northwest');
    grid(ax1, 'on'); axis(ax1, 'equal');

    % ── Panel 2: delta per lap, per car ──────────────────────────────────────
    ax2 = subplot(2, 2, 2);
    hold(ax2, 'on');
    for ci = 1:n_cars
        car_str = cars_all(ci);
        if has_tc_10
            for tgi = 1:numel(trap_grps_10)
                mask = T_ok.car == car_str & strcmp(cellstr(T_ok.trap_col), trap_grps_10{tgi});
                if ~any(mask), continue; end
                mkr10 = [trap_markers_10{min(tgi, numel(trap_markers_10))} '-'];
                lbl10 = sprintf('%s [%s]', char(car_str), trap_grps_10{tgi});
                plot(ax2, T_ok.lap(mask), T_ok.delta_kph(mask), mkr10, ...
                    'Color', cmap(ci,:), 'DisplayName', lbl10, ...
                    'MarkerFaceColor', cmap(ci,:));
            end
        else
            mask = T_ok.car == car_str;
            if ~any(mask), continue; end
            plot(ax2, T_ok.lap(mask), T_ok.delta_kph(mask), 'o-', ...
                'Color', cmap(ci,:), 'DisplayName', char(car_str), ...
                'MarkerFaceColor', cmap(ci,:));
        end
    end
    yline(ax2, 0, 'k--', 'HandleVisibility', 'off');
    xlabel(ax2, 'Lap'); ylabel(ax2, 'Δ kph (timing − MoTeC)');
    title(ax2, 'Delta per Lap');
    legend(ax2, 'Location', 'best');
    grid(ax2, 'on');

    % ── Panel 3: match rate per car (bar) ─────────────────────────────────────
    ax3 = subplot(2, 2, 3);
    match_rates = zeros(n_cars, 1);
    for ci = 1:n_cars
        car_str = cars_all(ci);
        mask_all = T_match.car == car_str;
        mask_ok  = T_match.car == car_str & T_match.matched;
        if any(mask_all)
            match_rates(ci) = 100 * sum(mask_ok) / sum(mask_all);
        end
    end
    b = bar(ax3, match_rates, 'FaceColor', 'flat');
    for ci = 1:n_cars, b.CData(ci,:) = cmap(ci,:); end
    set(ax3, 'XTickLabel', cellstr(cars_all), 'XTick', 1:n_cars);
    ylabel(ax3, 'Match rate (%)');
    title(ax3, 'Match Rate per Car');
    ylim(ax3, [0 105]);
    grid(ax3, 'on');
    % label bars
    for ci = 1:n_cars
        text(ax3, ci, match_rates(ci) + 2, sprintf('%.0f%%', match_rates(ci)), ...
            'HorizontalAlignment', 'center', 'FontSize', 8);
    end

    % ── Panel 4: unmatched laps table ─────────────────────────────────────────
    ax4 = subplot(2, 2, 4);
    axis(ax4, 'off');
    T_no = T_match(~T_match.matched, {'car','driver','lap','timing_kph'});
    if height(T_no) == 0
        text(0.5, 0.5, 'All laps matched!', 'Parent', ax4, ...
            'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', [0 0.6 0]);
    else
        T_no = sortrows(T_no, {'car','lap'});
        col_hdrs = {'Car','Driver','Lap','Timing kph'};
        tbl_data = [cellstr(T_no.car), cellstr(T_no.driver), ...
                    num2cell(T_no.lap), num2cell(round(T_no.timing_kph,1))];
        n_rows = min(height(T_no), 20);   % cap display at 20 rows
        uitable(fig, 'Data', tbl_data(1:n_rows,:), ...
            'ColumnName', col_hdrs, ...
            'Units', 'normalized', ...
            'Position', [ax4.Position(1) ax4.Position(2) ...
                         ax4.Position(3) ax4.Position(4)], ...
            'FontSize', 8);
        title_str = sprintf('Unmatched laps (%d', height(T_no));
        if height(T_no) > 20, title_str = [title_str ' — showing first 20']; end
        text(0.5, 1.02, [title_str ')'], 'Parent', ax4, ...
            'HorizontalAlignment', 'center', 'Units', 'normalized', 'FontSize', 9);
    end

    sgtitle(fig, sprintf('Speed Trap Debug — %s %s (%s)', event, session, report_type), ...
        'FontWeight', 'bold');
end

%% ── 11. SAVE CSV ─────────────────────────────────────────────────────────────
fprintf('\n=== STEP 11: Save CSV ===\n');
if ~exist('T_match', 'var') || isempty(T_match)
    fprintf('  No T_match — run step 8 first.\n');
else
    % Apply car_filter
    T_save = T_match;
    if ~isempty(car_filter)
        T_save = T_save(strcmp(string(T_save.car), car_filter), :);
        fprintf('  car filter applied: %d rows (car %s)\n', height(T_save), car_filter);
    end
    % Build filename: session + team + car (if filtered)
    team_tag = regexprep(strjoin(TEAM_FILTER, '_'), '[^\w]', '_');
    if ~isempty(car_filter)
        csv_fname = sprintf('%s_%s_car%s_speed_traps.csv', timing_session, team_tag, car_filter);
    else
        csv_fname = sprintf('%s_%s_speed_traps.csv', timing_session, team_tag);
    end
    csv_save_path = fullfile(cache_dir, csv_fname);
    writetable(T_save, csv_save_path);
    fprintf('  Saved %d rows to:\n  %s\n', height(T_save), csv_save_path);
end
