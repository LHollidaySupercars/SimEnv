%% =========================================================
%  EXECUTE_MAIN_REPORT_PARALLEL
%  =========================================================
%  Multi-worker compile + plot + PowerPoint export + SQL upload.
%
%  WORKFLOW:
%    Step 1  — Edit CONFIG sections (1–3)
%    Step 2  — Section 5 launches N_WORKERS MATLAB instances to compile
%              .ld files in parallel, polls until all finish, then merges
%    Step 3  — Plots are generated and exported to PPTX
%    Step 4  — Data is uploaded to the configured SQL target
%
%  SQL TARGETS (TARGET):
%    'pocketbase'   — local PocketBase instance
%    'azure_local'  — local SQL Server Express  (motorsport_local db)
%    'azure_online' — Motorsport Azure SQL       (Entra ID / browser MFA)
%
%  Set RUN_UPLOAD = false to skip the upload step entirely.
% =========================================================

clear; clc; close all;
t_script = tic;

%% =========================================================
%  SECTION 1: PATHS
% =========================================================

TOP_LEVEL_DIR     = 'E:\2026\04_RUA\_TeamData';

CHANNELS_FILE     = 'C:\SimEnv\dataAcquisition\Motec_MP\channels\channels.xlsx';
EVENT_ALIAS_FILE  = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\eventAlias.xlsx';
DRIVER_ALIAS_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\alias\driverAlias.xlsx';
PLOT_CONFIG_FILES  = {'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest\plottingRequest_SystemsReport.xlsx',...
                      'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest\plottingRequest_PerformanceReport.xlsx'};
SEASON_FILE       = 'C:\SimEnv\trackDB\seasonOverview.xlsx';

PPTX_TEMPLATE     = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\templates\SuperCars_PPT.pptx';
OUTPUT_DIR        = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\output';
OUTPUT_FILENAME   = 'TAU_Report';


%% =========================================================
%  SECTION 2: EVENT CONFIG
% =========================================================

TRACK                 = 'TAU';
EVENT_NAME            = 'TAU';
TEAM_FILTER           = {};           % {} = all teams, e.g. {'T8R', 'WAU'}
SESSION_FILTER        = {'F01', 'F02', 'Q08', 'Q09', 'R08', 'R09'};
CREATE_PITSTOP_REPORT = false;
workshop              = false;        % true = no session filter on stint grouping

%% =========================================================
%  SECTION 3: PROCESSING + UPLOAD OPTIONS
% =========================================================

N_WORKERS       = 4;
TMP_DIR         = fullfile(tempdir, 'smp_parallel');
POLL_INTERVAL_S = 3;
TIMEOUT_S       = 3600;

TARGET     = 'azure_online';   % 'pocketbase' | 'azure_local' | 'azure_online'
RUN_UPLOAD = true;             % false = skip flatten + upload
BATCH_SIZE = 200;
OVERWRITE  = true;

compile_opts.mode           = 'stream';
compile_opts.track          = TRACK;
compile_opts.max_traces     = 4;
compile_opts.dist_n_points  = 1000;
compile_opts.dist_channel   = 'Odometer';
compile_opts.verbose        = true;
compile_opts.date_from      = datetime(2026, 4, 10);
compile_opts.save_mode      = 'session';
compile_opts.session_filter = SESSION_FILTER;

plot_opts.fig_width     = 1200;
plot_opts.fig_height    = 650;
plot_opts.font_size     = 11;
plot_opts.n_laps_avg    = 3;
plot_opts.verbose       = true;
plot_opts.venue         = TRACK;

%% =========================================================
%  SECTION 4: LOAD CONFIG FILES
% =========================================================
fprintf('=== Parallel Report — %s ===\n\n', TRACK);

season                     = smp_season_load(SEASON_FILE);
[channels, channel_rules]  = smp_channel_config_load(CHANNELS_FILE);
alias                      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map                 = smp_driver_alias_load(DRIVER_ALIAS_FILE);
cfg                        = smp_colours();
compile_opts.channel_rules = channel_rules;

%% =========================================================
%  SECTION 5: PARALLEL COMPILE
% =========================================================

% ---- Prep tmp dir ----
if ~exist(TMP_DIR, 'dir'), mkdir(TMP_DIR); end
delete(fullfile(TMP_DIR, 'partial_*.mat'));
delete(fullfile(TMP_DIR, 'done_*.flag'));
delete(fullfile(TMP_DIR, 'chunk_*.mat'));
delete(fullfile(TMP_DIR, 'worker_cfg.mat'));

fprintf('============================================\n');
fprintf('  Parallel Compile\n');
fprintf('  Workers : %d\n', N_WORKERS);
fprintf('  TMP     : %s\n', TMP_DIR);
fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
fprintf('============================================\n\n');

% ---- Scan and diff ----
scan_all = smp_scan_folders(TOP_LEVEL_DIR);
if ~isempty(TEAM_FILTER)
    keep     = ismember({scan_all.acronym}, TEAM_FILTER);
    scan_all = scan_all(keep);
end

cache = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

% Migrate old cache structure if needed
if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
if ~isfield(cache, 'traces'), cache.traces = struct(); end
if ~isfield(cache, 'mode'),   cache.mode   = 'stream'; end
if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
    cache.manifest.GroupKey = repmat({''}, height(cache.manifest), 1);
end

% Apply date_from filter
if isfield(compile_opts, 'date_from') && ~isempty(compile_opts.date_from)
    date_from_dn = datenum(compile_opts.date_from);
    for i = 1:numel(scan_all)
        files = scan_all(i).files;
        keep  = false(1, numel(files));
        for j = 1:numel(files)
            d    = dir(files{j});
            keep(j) = ~isempty(d) && d(1).datenum >= date_from_dn;
        end
        scan_all(i).files = files(keep);
    end
    scan_all = scan_all(arrayfun(@(t) ~isempty(t.files), scan_all));
end

[to_load, cache] = smp_cache_diff(cache, scan_all);

if isempty(to_load)
    fprintf('All files up to date — nothing to compile.\n\n');
else
    fprintf('%d file(s) to process.\n', numel(to_load));

    if workshop
        groups = smp_append_stints(to_load, driver_map, alias);
    else
        groups = smp_append_stints(to_load, driver_map, alias, SESSION_FILTER);
    end
    n_groups = numel(groups);
    fprintf('%d group(s) across %d worker(s).\n\n', n_groups, N_WORKERS);

    % ---- Split groups across workers ----
    chunk_size = ceil(n_groups / N_WORKERS);
    for w = 1:N_WORKERS
        i_start = (w-1)*chunk_size + 1;
        i_end   = min(w*chunk_size, n_groups);
        if i_start > n_groups
            worker_groups = groups([]); %#ok<NASGU>
            fprintf('Worker %d: no groups assigned\n', w);
        else
            worker_groups = groups(i_start:i_end); %#ok<NASGU>
            fprintf('Worker %d: groups %d-%d  (%d group(s))\n', ...
                w, i_start, i_end, i_end - i_start + 1);
        end
        save(fullfile(TMP_DIR, sprintf('chunk_%d.mat', w)), 'worker_groups');
    end

    % ---- Save shared worker config ----
    [min_lt, max_lt]               = smp_season_get(season, TRACK);
    worker_cfg.test_mode           = false;
    worker_cfg.channels_to_extract = channels;
    worker_cfg.channel_rules       = channel_rules;
    worker_cfg.driver_map          = driver_map;
    worker_cfg.alias               = alias;
    worker_cfg.season              = season;
    worker_cfg.top_level_dir       = TOP_LEVEL_DIR;
    worker_cfg.min_lt              = min_lt;
    worker_cfg.max_lt              = max_lt;
    save(fullfile(TMP_DIR, 'worker_cfg.mat'), 'worker_cfg');
    fprintf('\n');

    % ---- Launch workers ----
    fprintf('Launching %d compile worker(s)...\n', N_WORKERS);
    matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');
    for w = 1:N_WORKERS
        sys_cmd = sprintf('start "SMP Worker %d" cmd /k ""%s" -batch "smp_compile_worker(%d, ''%s'')"', ...
            w, matlab_exe, w, strrep(TMP_DIR, '\', '\\'));
        system(sys_cmd);
        fprintf('  Worker %d launched\n', w);
        pause(1.5);
    end

    % ---- Poll until all workers finish ----
    fprintf('\nWaiting for workers...\n\n');
    t_poll     = tic;
    last_count = -1;
    while true
        done_flags = dir(fullfile(TMP_DIR, 'done_*.flag'));
        n_done     = numel(done_flags);
        if n_done ~= last_count
            fprintf('[%s]  %d / %d worker(s) done\n', datestr(now,'HH:MM:SS'), n_done, N_WORKERS);
            last_count = n_done;
        end
        if n_done >= N_WORKERS
            fprintf('\nAll workers finished.\n\n');
            break;
        end
        if toc(t_poll) > TIMEOUT_S
            error('Timeout after %ds — check worker windows for errors.', TIMEOUT_S);
        end
        pause(POLL_INTERVAL_S);
    end

    % ---- Merge partial caches ----
    fprintf('Merging results...\n');
    for w = 1:N_WORKERS
        partial_file = fullfile(TMP_DIR, sprintf('partial_%d.mat', w));
        if ~exist(partial_file, 'file')
            fprintf('  [WARN] Worker %d produced no output — skipping.\n', w);
            continue;
        end
        loaded = load(partial_file, 'partial_cache');
        pc     = loaded.partial_cache;

        if isempty(cache.manifest)
            cache.manifest = pc.manifest;
        else
            cache.manifest = [cache.manifest; pc.manifest];
        end
        keys_st = fieldnames(pc.stats);
        for k = 1:numel(keys_st)
            cache.stats.(keys_st{k}) = pc.stats.(keys_st{k});
        end
        keys_tr = fieldnames(pc.traces);
        for k = 1:numel(keys_tr)
            cache.traces.(keys_tr{k}) = pc.traces.(keys_tr{k});
        end
        fprintf('  Worker %d — %d manifest rows, %d stats, %d traces merged\n', ...
            w, height(pc.manifest), numel(keys_st), numel(keys_tr));
    end

    % Deduplicate manifest
    [~, unique_idx] = unique(cache.manifest.Path, 'stable');
    cache.manifest  = cache.manifest(unique_idx, :);
    fprintf('Manifest deduplicated: %d unique rows.\n', numel(unique_idx));
end

%% =========================================================
%  SECTION 6: FILTER CACHE TO SESSION(S) OF INTEREST
% =========================================================

SMP_filtered = smp_filter_cache(cache, alias, 'Session', SESSION_FILTER);
smp_filter_summary(SMP_filtered);

%% =========================================================
%  SECTION 7: PITSTOP REPORT (optional)
% =========================================================
if CREATE_PITSTOP_REPORT
    stops   = smp_pitstop_detect(SMP_filtered);
    pitData = smp_stops_to_pitdata(stops, SMP_filtered, driver_map);
    figs    = plotPitStops(pitData, 'Cfg', cfg, 'DriverMap', driver_map);
end

%% =========================================================
%  SECTION 8: PLOTS + POWERPOINT (per config file)
% =========================================================

if iscell(SESSION_FILTER)
    session_str = strjoin(SESSION_FILTER, '_');
else
    session_str = SESSION_FILTER;
end
team_str    = strjoin(TEAM_FILTER, '_');
base_report_name = sprintf('%s_%s_%s_%d', TRACK, team_str, session_str, year(datetime('now')));

for k = 1:numel(PLOT_CONFIG_FILES)
    fprintf('\n=== Report %d/%d: %s ===\n', k, numel(PLOT_CONFIG_FILES), PLOT_CONFIG_FILES{k});

    plots    = smp_plot_config_load(PLOT_CONFIG_FILES{k});
    holdFigs = smp_plot_from_config(SMP_filtered, plots, cfg, driver_map, plot_opts);

    for i = 1:numel(holdFigs)
        if ~isempty(holdFigs{i}), set(holdFigs{i}, 'Visible', 'off'); end
    end

    smp_generate_pptx_report(holdFigs, plots, PPTX_TEMPLATE, OUTPUT_DIR, ...
                              base_report_name, PLOT_CONFIG_FILES{k}, ...
                              SESSION_FILTER, TEAM_FILTER, TRACK);
    close all;
end

%% =========================================================
%  SECTION 10: UPLOAD TO SQL / POCKETBASE
% =========================================================

if RUN_UPLOAD
    fprintf('\n========================================\n');
    fprintf('  DATA UPLOAD — TARGET: %s\n', upper(TARGET));
    fprintf('========================================\n\n');

    fprintf('[Upload 1/3] Loading cache for event "%s"...\n', EVENT_NAME);
    cache_up = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

    if ~isfield(cache_up, 'stats') || isempty(fieldnames(cache_up.stats))
        warning('Cache is empty — skipping upload. Run compile step first.');
    else
        fprintf('      Cache: %d manifest rows, %d group keys.\n', ...
            height(cache_up.manifest), numel(fieldnames(cache_up.stats)));

        fprintf('[Upload 2/3] Flattening stats...\n');
        T = smp_flatten_stats(cache_up, EVENT_NAME);
        if ismember('id', T.Properties.VariableNames)
            T = removevars(T, 'id');
        end

        if isempty(T) || height(T) == 0
            warning('Flatten produced no rows — skipping upload.');
        else
            fprintf('[Upload 3/3] Pushing %d rows to %s...\n', height(T), upper(TARGET));

            switch lower(TARGET)

                % ── PocketBase ────────────────────────────────────────────
                case 'pocketbase'
                    opts_pb           = struct();
                    opts_pb.batch     = BATCH_SIZE;
                    opts_pb.overwrite = OVERWRITE;
                    opts_pb.dry_run   = false;

                    result = smp_push_to_pocketbase(T, opts_pb);
                    fprintf('\n      Upload complete: %d rows uploaded, %d failed.\n', ...
                        result.n_uploaded, result.n_failed);

                % ── Azure Local / Online ──────────────────────────────────
                case {'azure_local', 'azure_online'}
                    if strcmpi(TARGET, 'azure_online')
                        fprintf('      >> Browser MFA popup may appear.\n');
                    end

                    conn = smp_sql_connect(TARGET);

                    opts_sql           = struct();
                    opts_sql.batch     = BATCH_SIZE;
                    opts_sql.overwrite = OVERWRITE;
                    opts_sql.dry_run   = false;

                    result = smp_push_to_sql(T, conn, opts_sql);
                    fprintf('\n      Upload complete: %d rows uploaded, %d failed.\n', ...
                        result.n_uploaded, result.n_failed);

                    assignin('base', 'sql_conn', conn);
                    fprintf('      Connection stored in workspace as ''sql_conn''.\n');
            end
        end
    end
else
    fprintf('\n[Upload] Skipped (RUN_UPLOAD = false)\n');
end

%% =========================================================
%  SECTION 11: SAVE CACHE
% =========================================================

fprintf('\nSaving cache...\n');
try
    smp_cache_save(TOP_LEVEL_DIR, cache, compile_opts.save_mode, alias);
    fprintf('Cache saved.\n');
catch ME_save
    fprintf('[ERROR] Cache save failed: %s\n', ME_save.message);
end

fprintf('\n=== Total time: %.1f minutes (%.0f seconds) ===\n', ...
    toc(t_script)/60, toc(t_script));