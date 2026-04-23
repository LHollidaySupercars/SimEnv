%% =========================================================
%  EXECUTE_MAIN_REPORT
%  =========================================================
%  Single entry point — compile, VCH recompute, plots, upload.
%
%  WORKFLOW:
%    Step 1  — Edit CONFIG sections (1–3)
%    Step 2  — Run Section 5  to compile new .ld files
%           OR Section 5b to load cache only (re-plot, no compile)
%    Step 3  — Section 5c: VCH recompute  (set RUN_RECOMPUTE_VCH = true)
%    Step 4  — Section 5d: VCH debug plot (set VCH_DEBUG_PLOT  = true)
%    Step 5  — Section 8:  Plots → PPTX
%    Step 6  — Section 9:  Upload to SQL / PocketBase
%
%  COMPILE / RECOMPUTE MODES  (MODE / RECOMPUTE_MODE):
%    'serial'    — single-process via smp_compile_event
%    'parallel'  — N_WORKERS external MATLAB instances, file-polled
%
%  SQL TARGETS  (TARGET):
%    'pocketbase'   — local PocketBase instance
%    'azure_local'  — local SQL Server Express  (motorsport_local db)
%    'azure_online' — Motorsport Azure SQL       (Entra ID / browser MFA)
%
%  Set RUN_UPLOAD         = false to skip upload.
%  Set RUN_RECOMPUTE_VCH  = true  to rerun channel math on cached data.
%  Set VCH_DEBUG_PLOT     = true  to inspect generated channels after recompute.
%  Set KEEP_WORKERS_OPEN  = true  to leave worker cmd windows open (debug).
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
PLOT_CONFIG_FILES  = {'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest\plottingRequest_SystemsReport.xlsx','C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest\plottingRequest_PerformanceReport.xlsx'};
SEASON_FILE       = 'C:\SimEnv\trackDB\seasonOverview.xlsx';

PPTX_TEMPLATE     = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\templates\SuperCars_PPT.pptx';
OUTPUT_DIR        = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\output';

%% =========================================================
%  SECTION 2: EVENT CONFIG
% =========================================================
EVENT                 = 'E04';
TRACK                 = 'RUA';
EVENT_NAME            = 'RUA';
TEAM_FILTER           = {'T8R'};           % {} = all teams, e.g. {'T8R', 'WAU'}
SESSION_FILTER        = {'Q13'};
CREATE_PITSTOP_REPORT = false;
workshop              = false;        % true = no session filter on stint grouping
SAVE_CACHE            = false;
%% =========================================================
%  SECTION 3: PROCESSING + UPLOAD OPTIONS
% =========================================================

MODE       = 'serial';         % 'serial' | 'parallel'

% ---- Parallel worker options (ignored in serial mode) ----
N_WORKERS          = 4;
TMP_DIR            = fullfile(tempdir, 'smp_parallel');
POLL_INTERVAL_S    = 3;
TIMEOUT_S          = 3600;
KEEP_WORKERS_OPEN  = false;   % false = cmd /c (auto-close on success)
                              % true  = cmd /k (leave window open — for debugging)

% ---- VCH recompute options ----
RUN_RECOMPUTE_VCH = false;     % true = rerun channel math on all cached groups
RECOMPUTE_MODE    = 'serial';  % 'serial' | 'parallel'

% ---- VCH debug plot (active when RUN_RECOMPUTE_VCH = true) ----
VCH_DEBUG_PLOT = true;         % true = plot VCH channels after recompute for inspection
VCH_DEBUG_TEAM = '';           % '' = first available team in cache, or e.g. 'T8R'
VCH_DEBUG_X    = 'time';       % x-axis: 'time', or any channel field name
VCH_DEBUG_Y    = {             % y-axis channels to plot (one subplot each)
    'brakeBiasVCH', ...
    'RL_SlipVCH', ...
    'rTyreRL_VCH_P_FZ_C' ...
};

% ---- Upload options ----
TARGET     = 'azure_online';   % 'pocketbase' | 'azure_local' | 'azure_online'
RUN_UPLOAD = false;
BATCH_SIZE = 200;
OVERWRITE  = false;

% ---- Compile options ----
compile_opts.mode           = 'stream';
compile_opts.track          = TRACK;
compile_opts.max_traces     = 4;
compile_opts.dist_n_points  = 1000;
compile_opts.dist_channel   = 'Odometer';
compile_opts.verbose        = true;
compile_opts.date_from      = datetime(2026, 4, 10);
compile_opts.saveCache      = true;
compile_opts.save_mode      = 'session';   % 'legacy' | 'session'
compile_opts.session_filter = SESSION_FILTER;

% ---- Plot options ----
plot_opts.fig_width     = 1200;
plot_opts.fig_height    = 650;
plot_opts.font_size     = 11;
plot_opts.n_laps_avg    = 3;
plot_opts.verbose       = true;
plot_opts.venue         = TRACK;

%% =========================================================
%  SECTION 4: LOAD CONFIG FILES
% =========================================================
fprintf('=== %s Report — %s ===\n\n', upper(MODE), TRACK);

season                     = smp_season_load(SEASON_FILE);
[channels, channel_rules]  = smp_channel_config_load(CHANNELS_FILE);
alias                      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map                 = smp_driver_alias_load(DRIVER_ALIAS_FILE);
cfg                        = smp_colours();
compile_opts.channel_rules   = channel_rules;
compile_opts.detect_pitlane  = true;          % enable pit entry/exit classification
compile_opts.fcy_channel     = 'Sw_State_SC';    % Full Course Yellow flag channel
T_gated = readtable(CHANNELS_FILE, 'Sheet', 'gatedChannels', 'TextType', 'char');

%% =========================================================
%  SECTION 5: COMPILE
%  Run this cell when you have new/changed .ld files.
%  Already-cached files are skipped automatically.
% =========================================================

switch lower(MODE)

    % ----------------------------------------------------------
    case 'serial'
    % ----------------------------------------------------------
        cache = smp_compile_event(TOP_LEVEL_DIR, TEAM_FILTER, channels, ...
                                  season, driver_map, alias, compile_opts);

    % ----------------------------------------------------------
    case 'parallel'
    % ----------------------------------------------------------

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
                    d       = dir(files{j});
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
            worker_cfg.T_gated             = T_gated;
            save(fullfile(TMP_DIR, 'worker_cfg.mat'), 'worker_cfg');
            fprintf('\n');

            % ---- Launch workers ----
            win_mode   = 'cmd /c'; if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
            fprintf('Launching %d compile worker(s)...\n', N_WORKERS);
            matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');
            for w = 1:N_WORKERS
                sys_cmd = sprintf('start "SMP Worker %d" %s ""%s" -batch "smp_compile_worker(%d, ''%s'')"', ...
                    w, win_mode, matlab_exe, w, strrep(TMP_DIR, '\', '\\'));
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
                    fprintf('[%s]  %d / %d worker(s) done\n', ...
                        datestr(now,'HH:MM:SS'), n_done, N_WORKERS);
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

    otherwise
        error('Unknown MODE "%s" — use ''serial'' or ''parallel''.', MODE);
end

%% =========================================================
%  SECTION 5b: LOAD ONLY  (re-plot without recompiling)
%  Comment out Section 5 above and run this cell instead
%  when no new .ld files need processing.
% =========================================================

% cache = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

%% =========================================================
%  SECTION 5c: VCH RECOMPUTE  (set RUN_RECOMPUTE_VCH = true)
%  Re-reads raw .ld files, reruns smp_custom_channels +
%  smp_gated_channels, and overwrites only the VCH channel
%  stats in the cache. All standard channel stats are untouched.
%  Use after editing channel math without new .ld files.
%  Requires cache to be in workspace (from Section 5 or 5b).
% =========================================================

if RUN_RECOMPUTE_VCH
    vch_opts.track          = TRACK;
    vch_opts.session_filter = SESSION_FILTER;
    vch_opts.verbose        = true;
    vch_opts.T_gated        = T_gated;   % already loaded in Section 4 — no extra disk read

    switch lower(RECOMPUTE_MODE)

        % ----------------------------------------------------------
        case 'serial'
        % ----------------------------------------------------------
            fprintf('\n=== VCH Recompute (serial) ===\n\n');
            cache = smp_recompute_vch(TOP_LEVEL_DIR, season, driver_map, alias, ...
                                      channels, vch_opts, cache);

        % ----------------------------------------------------------
        case 'parallel'
        % ----------------------------------------------------------
            fprintf('\n=== VCH Recompute (parallel) ===\n\n');

            VCH_TMP = fullfile(tempdir, 'smp_vch_recompute');
            if ~exist(VCH_TMP, 'dir'), mkdir(VCH_TMP); end
            delete(fullfile(VCH_TMP, 'vch_chunk_*.mat'));
            delete(fullfile(VCH_TMP, 'vch_partial_*.mat'));
            delete(fullfile(VCH_TMP, 'vch_done_*.flag'));
            delete(fullfile(VCH_TMP, 'vch_worker_cfg.mat'));

            % ---- Build group list from current cache manifest ----
            groups_vch = groups_from_manifest(cache.manifest, SESSION_FILTER);
            n_vch      = numel(groups_vch);
            fprintf('%d group(s) to recompute across %d worker(s).\n\n', n_vch, N_WORKERS);

            % ---- Save shared worker config ----
            [min_lt, max_lt]                   = smp_season_get(season, TRACK);
            vch_worker_cfg.channels_to_extract = channels;
            vch_worker_cfg.driver_map          = driver_map;
            vch_worker_cfg.min_lt              = min_lt;
            vch_worker_cfg.max_lt              = max_lt;
            vch_worker_cfg.T_gated             = T_gated;
            save(fullfile(VCH_TMP, 'vch_worker_cfg.mat'), 'vch_worker_cfg'); %#ok<NASGU>

            % ---- Split groups across workers ----
            chunk_size = ceil(n_vch / N_WORKERS);
            for w = 1:N_WORKERS
                i_start = (w-1)*chunk_size + 1;
                i_end   = min(w*chunk_size, n_vch);
                if i_start > n_vch
                    worker_groups = groups_vch([]); %#ok<NASGU>
                else
                    worker_groups = groups_vch(i_start:i_end); %#ok<NASGU>
                    fprintf('VCH Worker %d: groups %d-%d  (%d group(s))\n', ...
                        w, i_start, i_end, i_end - i_start + 1);
                end
                save(fullfile(VCH_TMP, sprintf('vch_chunk_%d.mat', w)), 'worker_groups');
            end

            % ---- Launch VCH workers ----
            win_mode   = 'cmd /c'; if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
            fprintf('\nLaunching %d VCH worker(s)...\n', N_WORKERS);
            matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');
            for w = 1:N_WORKERS
                sys_cmd = sprintf('start "VCH Worker %d" %s ""%s" -batch "smp_recompute_vch_worker(%d, ''%s'')"', ...
                    w, win_mode, matlab_exe, w, strrep(VCH_TMP, '\', '\\'));
                system(sys_cmd);
                fprintf('  Worker %d launched\n', w);
                pause(1.5);
            end

            % ---- Poll until all VCH workers finish ----
            fprintf('\nWaiting for VCH workers...\n\n');
            t_poll_vch = tic;
            last_count = -1;
            while true
                done_flags = dir(fullfile(VCH_TMP, 'vch_done_*.flag'));
                n_done     = numel(done_flags);
                if n_done ~= last_count
                    fprintf('[%s]  %d / %d VCH worker(s) done\n', ...
                        datestr(now,'HH:MM:SS'), n_done, N_WORKERS);
                    last_count = n_done;
                end
                if n_done >= N_WORKERS
                    fprintf('\nAll VCH workers finished.\n\n');
                    break;
                end
                if toc(t_poll_vch) > TIMEOUT_S
                    error('VCH worker timeout after %ds.', TIMEOUT_S);
                end
                pause(POLL_INTERVAL_S);
            end

            % ---- Merge VCH partial results back into cache ----
            fprintf('Merging VCH results...\n');
            for w = 1:N_WORKERS
                partial_file = fullfile(VCH_TMP, sprintf('vch_partial_%d.mat', w));
                if ~exist(partial_file, 'file')
                    fprintf('  [WARN] VCH Worker %d produced no output — skipping.\n', w);
                    continue;
                end
                loaded  = load(partial_file, 'partial');
                partial = loaded.partial;
                keys    = fieldnames(partial.vch_stats);
                for k = 1:numel(keys)
                    gk = keys{k};
                    if ~isfield(cache.stats, gk)
                        fprintf('  [WARN] group_key "%s" not in cache — skipping.\n', gk);
                        continue;
                    end
                    vch_keys = fieldnames(partial.vch_stats.(gk));
                    for v = 1:numel(vch_keys)
                        cache.stats.(gk).(vch_keys{v}) = partial.vch_stats.(gk).(vch_keys{v});
                    end
                    fprintf('  Merged %d VCH channel(s) into cache.stats.%s\n', numel(vch_keys), gk);
                end
            end

            % ---- Save updated cache ----
            fprintf('\nSaving cache after VCH recompute...\n');
            tic;
            smp_cache_save(TOP_LEVEL_DIR, cache, compile_opts.save_mode, alias);
            fprintf('Cache saved in %.1fs.\n\n', toc);

        otherwise
            error('Unknown RECOMPUTE_MODE "%s" — use ''serial'' or ''parallel''.', RECOMPUTE_MODE);
    end
end

%% =========================================================
%  SECTION 5d: VCH DEBUG PLOT
%  Reads a raw .ld file for one group, reruns the full
%  channel math pipeline, and plots VCH_DEBUG_Y vs
%  VCH_DEBUG_X so you can visually verify each generated
%  channel looks correct before using it downstream.
%
%  Configure in Section 3:
%    VCH_DEBUG_PLOT = true
%    VCH_DEBUG_TEAM = 'T8R'                  ('' = first team found)
%    VCH_DEBUG_X    = 'time'                 (or any channel field name)
%    VCH_DEBUG_Y    = {'brakeBiasVCH', ...}  (one subplot per entry)
% =========================================================

if RUN_RECOMPUTE_VCH && VCH_DEBUG_PLOT && ~isempty(VCH_DEBUG_Y)
    fprintf('\n=== VCH Debug Plot ===\n');

    % ---- Select which group to inspect ----
    dbg_manifest = cache.manifest;
    if ~isempty(SESSION_FILTER)
        dbg_manifest = dbg_manifest(ismember(dbg_manifest.Session, SESSION_FILTER), :);
    end
    if ~isempty(VCH_DEBUG_TEAM)
        dbg_manifest = dbg_manifest(strcmpi(dbg_manifest.TeamAcronym, VCH_DEBUG_TEAM), :);
    end

    if height(dbg_manifest) == 0
        fprintf('  [WARN] No matching group for debug plot — check VCH_DEBUG_TEAM.\n');
    else
        % First file from the first unique group
        [~, ui]  = unique(dbg_manifest.GroupKey, 'stable');
        dbg_row  = dbg_manifest(ui(1), :);
        dbg_file = dbg_row.Path{1};
        dbg_team = dbg_row.TeamAcronym{1};
        dbg_gk   = dbg_row.GroupKey{1};

        fprintf('  Team  : %s\n', dbg_team);
        fprintf('  Group : %s\n', dbg_gk);
        fprintf('  File  : %s\n', dbg_file);

        try
            % ---- Load raw .ld and rerun full math pipeline ----
            fprintf('  Loading .ld and rerunning channel math...\n');
            dbg_data          = motec_ld_reader(dbg_file, channels);
            dbg_data          = smp_custom_channels(dbg_data);
            [dbg_data, ~]     = smp_gated_channels(dbg_data, T_gated);

            % ---- Build figure ----
            n_ch = numel(VCH_DEBUG_Y);
            figure('Name',        sprintf('VCH Debug — %s | %s', dbg_team, dbg_gk), ...
                   'NumberTitle', 'off', ...
                   'Position',    [80, 80, 1200, max(250, 200 * n_ch)]);

            for pi = 1:n_ch
                ch_name = VCH_DEBUG_Y{pi};
                ax      = subplot(n_ch, 1, pi);

                if ~isfield(dbg_data, ch_name)
                    title(ax, sprintf('%s  —  NOT FOUND in generated channels', ch_name), ...
                          'Interpreter', 'none', 'Color', [0.8 0 0]);
                    fprintf('  [!] "%s" not found — check smp_custom_channels / smp_gated_channels\n', ch_name);
                    continue;
                end

                y_ch = dbg_data.(ch_name);
                y    = y_ch.data;

                % Resolve x axis
                if strcmpi(VCH_DEBUG_X, 'time')
                    x     = y_ch.time;
                    x_lbl = 'Time  (s)';
                elseif isfield(dbg_data, VCH_DEBUG_X)
                    x_src = dbg_data.(VCH_DEBUG_X);
                    x     = interp1(x_src.time, x_src.data, y_ch.time, 'linear', 'extrap');
                    x_lbl = sprintf('%s  [%s]', VCH_DEBUG_X, x_src.units);
                else
                    fprintf('  [!] X channel "%s" not found — falling back to time\n', VCH_DEBUG_X);
                    x     = y_ch.time;
                    x_lbl = 'Time  (s)';
                end

                plot(ax, x, y, 'LineWidth', 1);
                xlabel(ax, x_lbl);
                ylabel(ax, sprintf('%s  [%s]', ch_name, y_ch.units));
                title(ax, ch_name, 'Interpreter', 'none');
                grid(ax, 'on');
            end

            sgtitle(sprintf('VCH Debug — %s | %s | %s', dbg_team, dbg_gk, dbg_file), ...
                    'Interpreter', 'none', 'FontSize', 9);
            fprintf('  Debug plot complete.\n\n');

        catch ME_dbg
            fprintf('  [ERROR] VCH debug plot failed: %s\n', ME_dbg.message);
        end
    end
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

    switch lower(MODE)

        % ------------------------------------------------------
        case 'serial'
        % ------------------------------------------------------
            stops   = smp_pitstop_detect(SMP_filtered);
            pitData = smp_stops_to_pitdata(stops, SMP_filtered, driver_map);
            figs    = plotPitStops(pitData, 'Cfg', cfg, 'DriverMap', driver_map);

        % ------------------------------------------------------
        case 'parallel'
        % ------------------------------------------------------

            % ---- Clean up any previous pitstop worker artefacts ----
            delete(fullfile(TMP_DIR, 'chunk_pit_*.mat'));
            delete(fullfile(TMP_DIR, 'done_pit_*.flag'));
            delete(fullfile(TMP_DIR, 'partial_pit_*.mat'));

            % ---- Split SMP_filtered teams across workers ----
            all_teams  = fieldnames(SMP_filtered);
            n_teams    = numel(all_teams);
            n_pit_workers = min(N_WORKERS, n_teams);   % no point spawning more workers than teams
            chunk_size = ceil(n_teams / n_pit_workers);

            fprintf('\n============================================\n');
            fprintf('  Parallel Pitstop Detection\n');
            fprintf('  Teams   : %d\n', n_teams);
            fprintf('  Workers : %d\n', n_pit_workers);
            fprintf('============================================\n\n');

            for w = 1:n_pit_workers
                i_start   = (w-1)*chunk_size + 1;
                i_end     = min(w*chunk_size, n_teams);
                team_keys = all_teams(i_start:i_end);

                % Build SMP subset for this worker
                SMP_chunk = struct(); %#ok<NASGU>
                for ti = 1:numel(team_keys)
                    SMP_chunk.(team_keys{ti}) = SMP_filtered.(team_keys{ti});
                end

                save(fullfile(TMP_DIR, sprintf('chunk_pit_%d.mat', w)), 'SMP_chunk');
                fprintf('Worker %d: teams %d-%d  (%s)\n', w, i_start, i_end, ...
                    strjoin(team_keys, ', '));
            end

            % ---- Launch pitstop workers ----
            win_mode   = 'cmd /c'; if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
            fprintf('\nLaunching %d pitstop worker(s)...\n', n_pit_workers);
            matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');
            for w = 1:n_pit_workers
                sys_cmd = sprintf('start "PIT Worker %d" %s ""%s" -batch "smp_pitstop_worker(%d, ''%s'')"', ...
                    w, win_mode, matlab_exe, w, strrep(TMP_DIR, '\', '\\'));
                system(sys_cmd);
                fprintf('  Worker %d launched\n', w);
                pause(1.5);
            end

            % ---- Poll until all pitstop workers finish ----
            fprintf('\nWaiting for pitstop workers...\n\n');
            t_poll_pit = tic;
            last_count = -1;
            while true
                done_flags = dir(fullfile(TMP_DIR, 'done_pit_*.flag'));
                n_done     = numel(done_flags);
                if n_done ~= last_count
                    fprintf('[%s]  %d / %d pitstop worker(s) done\n', ...
                        datestr(now,'HH:MM:SS'), n_done, n_pit_workers);
                    last_count = n_done;
                end
                if n_done >= n_pit_workers
                    fprintf('\nAll pitstop workers finished.\n\n');
                    break;
                end
                if toc(t_poll_pit) > TIMEOUT_S
                    error('Pitstop worker timeout after %ds.', TIMEOUT_S);
                end
                pause(POLL_INTERVAL_S);
            end

            % ---- Merge partial stops ----
            fprintf('Merging pitstop results...\n');
            stops = struct();
            for w = 1:n_pit_workers
                partial_file = fullfile(TMP_DIR, sprintf('partial_pit_%d.mat', w));
                if ~exist(partial_file, 'file')
                    fprintf('  [WARN] Worker %d produced no pitstop output — skipping.\n', w);
                    continue;
                end
                loaded = load(partial_file, 'partial_stops');
                ps     = loaded.partial_stops;
                keys   = fieldnames(ps);
                for k = 1:numel(keys)
                    stops.(keys{k}) = ps.(keys{k});
                end
                fprintf('  Worker %d — %d team(s) merged\n', w, numel(keys));
            end

            pitData = smp_stops_to_pitdata(stops, SMP_filtered, driver_map);
            figs    = plotPitStops(pitData, 'Cfg', cfg, 'DriverMap', driver_map);
    end
end

%% =========================================================
%  SECTION 8: PLOTS + POWERPOINT (per config file)
% =========================================================

if iscell(SESSION_FILTER)
    session_str = strjoin(SESSION_FILTER, '_');
else
    session_str = SESSION_FILTER;
end
team_str         = strjoin(TEAM_FILTER, '_');
base_report_name = sprintf('26VCS_%s%s_%s', EVENT, TRACK, session_str);

if ischar(PLOT_CONFIG_FILES)
    PLOT_CONFIG_FILES = {PLOT_CONFIG_FILES};
end

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
%  SECTION 9: UPLOAD TO SQL / POCKETBASE
% =========================================================

if RUN_UPLOAD
    fprintf('\n========================================\n');
    fprintf('  DATA UPLOAD — TARGET: %s\n', upper(TARGET));
    fprintf('========================================\n\n');

    fprintf('[Upload 1/3] Using compiled cache for event "%s"...\n', EVENT_NAME);
    cache_up = cache;

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
%  SECTION 10: SAVE CACHE
% =========================================================
if SAVE_CACHE
    fprintf('\nSaving cache...\n');
    try
        smp_cache_save(TOP_LEVEL_DIR, cache, compile_opts.save_mode, alias);
        fprintf('Cache saved.\n');
    catch ME_save
        fprintf('[ERROR] Cache save failed: %s\n', ME_save.message);
    end
end

fprintf('\n=== Total time: %.1f minutes (%.0f seconds) ===\n', ...
    toc(t_script)/60, toc(t_script));


% ======================================================================= %
%  LOCAL: BUILD GROUP LIST FROM MANIFEST
%  Used by the parallel VCH recompute path in Section 5c.
% ======================================================================= %
function groups = groups_from_manifest(manifest, session_filter)
    groups = struct('key', {}, 'team_acronym', {}, 'driver', {}, ...
                    'session', {}, 'files', {});

    if ~isempty(session_filter)
        keep     = ismember(manifest.Session, session_filter);
        manifest = manifest(keep, :);
    end

    ok       = manifest.LoadOK & ~cellfun(@isempty, manifest.GroupKey);
    manifest = manifest(ok, :);

    if height(manifest) == 0, return; end

    unique_keys = unique(manifest.GroupKey, 'stable');

    for k = 1:numel(unique_keys)
        gk   = unique_keys{k};
        rows = manifest(strcmp(manifest.GroupKey, gk), :);

        g.key          = gk;
        g.team_acronym = rows.TeamAcronym{1};
        g.driver       = rows.Driver{1};
        g.session      = rows.Session{1};
        g.files        = rows.Path;

        groups(end+1) = g; %#ok<AGROW>
    end
end
