%% debug_speed_trap_match.m
% Diagnoses lap-matching in smp_match_speed_trap step-by-step.
% Edit the CONFIGURATION section below, then run section-by-section (Ctrl+Enter).

%% ── CONFIGURATION ────────────────────────────────────────────────────────────
cache_dir       = 'E:\2026\04_RUA\_TeamData';
timing_base_dir = 'E:\2026\99_seasonTiming';
event           = 'RUA';
session         = 'Q11';
report_type     = 'top_speed';   % 'top_speed' | 'pit_speed'
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

%% ── 2. RESOLVE TIMING CSV ────────────────────────────────────────────────────
fprintf('\n=== STEP 2: Resolve timing CSV ===\n');
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
master_csv = fullfile(timing_base_dir, d(1).name, type_sub, [session suffix]);
fprintf('  CSV path      : %s\n', master_csv);
if ~isfile(master_csv)
    error('CSV not found: %s', master_csv);
end

%% ── 3. LOAD & FILTER CSV ─────────────────────────────────────────────────────
fprintf('\n=== STEP 3: Load and filter CSV ===\n');
T = readtable(master_csv, 'Delimiter', ',', 'TextType', 'string');
fprintf('  raw rows      : %d\n', height(T));

if ismember('parse_error', T.Properties.VariableNames)
    T = T(~strcmpi(string(T.parse_error), 'true'), :);
    fprintf('  after error strip: %d\n', height(T));
end

T = T(strcmpi(string(T.event), event), :);
T = T(strcmpi(string(T.session), session), :);
fprintf('  after filter  : %d rows (event=%s, session=%s)\n', height(T), event, session);

T.car = strtrim(string(T.car));
if ~isnumeric(T.lap),          T.lap          = str2double(string(T.lap));          end
if ~isnumeric(T.(kph_col)),    T.(kph_col)    = str2double(string(T.(kph_col)));    end

if ~isempty(car_filter)
    T = T(strcmp(T.car, car_filter), :);
    fprintf('  after car filter (%s): %d rows\n', car_filter, height(T));
end

if height(T) == 0
    error('No CSV rows remain after filtering.');
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
        fprintf('    lap %2d  type: %s\n', lap_nums(li), types{li});
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
opts = struct();
opts.event           = event;
opts.session         = session;
opts.report_type     = report_type;
opts.timing_base_dir = timing_base_dir;
opts.speed_channel   = speed_channel;
opts.master_csv      = master_csv;

T_match = smp_match_speed_trap(cache, opts);

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

% Summary stats for matched rows in display set
T_ok = T_display(T_display.matched, :);
if height(T_ok) > 0
    fprintf('\n  Matched rows — delta_kph stats:\n');
    fprintf('    mean  : %.2f\n', mean(T_ok.delta_kph,   'omitnan'));
    fprintf('    std   : %.2f\n', std(T_ok.delta_kph,    'omitnan'));
    fprintf('    min   : %.2f\n', min(T_ok.delta_kph,    [], 'omitnan'));
    fprintf('    max   : %.2f\n', max(T_ok.delta_kph,    [], 'omitnan'));
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
    for ci = 1:n_cars
        car_str = cars_all(ci);
        mask    = T_ok.car == car_str;
        if ~any(mask), continue; end
        scatter(ax1, T_ok.timing_kph(mask), T_ok.motec_kph(mask), 50, ...
            cmap(ci,:), 'filled', 'DisplayName', char(car_str));
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
        mask    = T_ok.car == car_str;
        if ~any(mask), continue; end
        plot(ax2, T_ok.lap(mask), T_ok.delta_kph(mask), 'o-', ...
            'Color', cmap(ci,:), 'DisplayName', char(car_str), ...
            'MarkerFaceColor', cmap(ci,:));
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
