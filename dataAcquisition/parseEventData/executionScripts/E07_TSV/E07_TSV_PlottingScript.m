%% =========================================================
%  EXECUTE_MAIN_REPORT
%  =========================================================
clear; clc; close all;
t_script = tic;

%% =========================================================
%  SECTION 1: PATHS
% =========================================================

TOP_LEVEL_DIR     = 'E:\2026\E07_TSV\COM';

CHANNELS_FILE     = 'C:/SimEnv/dataAcquisition/Motec_MP/channels/channels.xlsx';
EVENT_ALIAS_FILE  = 'C:\SimEnv\dataAcquisition\parseEventData\executionScripts\E07_TSV\eventAlias.xlsx';
DRIVER_ALIAS_FILE = 'C:/SimEnv/dataAcquisition/Motec_MP/alias/driverAlias.xlsx';
PLOT_CONFIG_FILES  = {'C:/SimEnv/dataAcquisition/Motec_MP/plottingRequest/plottingRequest_E07TSV_PR_Final.xlsx',...
     'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest\plottingRequest_PerformanceReport.xlsx' };
SEASON_FILE       = 'C:/SimEnv/trackDB/seasonOverview.xlsx';
PPTX_TEMPLATE     = 'C:/SimEnv/dataAcquisition/Motec_MP/plot/templates/SuperCars_PPT.pptx';
OUTPUT_DIR        = 'C:/SimEnv/dataAcquisition/Motec_MP/plot/output';

% =========================================================
%  SECTION 2: EVENT CONFIG
% =========================================================
EVENT                 = 'E07';
TRACK                 = 'TSV';
EVENT_NAME            = 'TSV';
TEAM_FILTER           = {};           % {} = all teams, e.g. {'T8R', 'WAU'}
SESSION_FILTER        = {'Q20'};
CREATE_PITSTOP_REPORT = true;
workshop              = false;        % true = no session filter on stint grouping
SAVE_CACHE            = true;
PLOTTING              = true;
RUN_TEAMDATA_CONCAT   = true; 
% =========================================================
%  SECTION 3: PROCESSING + UPLOAD OPTIONS
% =========================================================

MODE       = 'parallel';         % 'serial' | 'parallel'

% ---- Parallel worker options (ignored in serial mode) ----
N_WORKERS          = 6;
TMP_DIR            = fullfile(tempdir, 'smp_parallel');
POLL_INTERVAL_S    = 3;
TIMEOUT_S          = 3600;
KEEP_WORKERS_OPEN  = false;   % false = cmd /c (auto-close on success)
                              % true  = cmd /k (leave window open — for debugging)

% ---- VCH recompute options ----
RUN_RECOMPUTE_VCH = false;    % gated channels now computed during smp_compile_event.
                              % Set true ONLY if you've edited channel math on already-compiled data.
RECOMPUTE_MODE    = 'serial';  % 'serial' | 'parallel'

% ---- VCH debug plot (active when RUN_RECOMPUTE_VCH = true) ----
VCH_DEBUG_PLOT = true;         % true = plot VCH channels after recompute for inspection
VCH_DEBUG_TEAM = '';           % '' = first available team in cache, or e.g. 'T8R'
VCH_DEBUG_X    = 'time';       % x-axis: 'time', or any channel field name
VCH_DEBUG_Y    = {             % y-axis channels to plot (one subplot each)
    'brakeBiasVCH', ...
    'RL_SlipVCH', ...
    'rTyreRL_VCH_P_FZ_C',  ...
    'CLa_SCz_Braking_VCH'...
};

% ---- Upload options ----
TARGET     = 'azure_online';   % 'pocketbase' | 'azure_local' | 'azure_online'
RUN_UPLOAD = false;
BATCH_SIZE = 200;
OVERWRITE  = false;

% ---- Compile options ----
compile_opts.mode              = 'stream';
compile_opts.track             = TRACK;
compile_opts.max_traces        = 4;
compile_opts.dist_n_points     = 1000;
compile_opts.dist_channel      = 'Odometer';
compile_opts.verbose           = true;
compile_opts.date_from         = datetime(2026, 6, 19);
compile_opts.saveCache         = true;
compile_opts.save_mode         = 'session';   % 'legacy' | 'session'
compile_opts.session_filter    = SESSION_FILTER;
compile_opts.load_all_channels = true;      % true = load full file, no channel filter (use for COM)
compile_opts.concat_csv_dir    = OUTPUT_DIR;  % '' = skip CSV; non-empty = save concat report here
compile_opts.showConcatReport  = false;      % pop-up summary after each multi-file session group
compile_opts.br2_channel       = 'BR2_Beacon_Number';
compile_opts.br2_protocol      = 'standard';  % 'standard' | 'TAS2025'

% ---- Plot options ----
plot_opts.fig_width     = 1200;
plot_opts.fig_height    = 650;
plot_opts.font_size     = 11;
plot_opts.n_laps_avg    = 3;
plot_opts.verbose       = true;
plot_opts.venue         = TRACK;

% =========================================================
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
compile_opts.beacon_check = false;
compile_opts.T_gated      = T_gated;   % gated channels computed during compile, no separate recompute needed

% Point compiler at HOL output if pre-concat was used
if RUN_TEAMDATA_CONCAT
    COMPILE_DIR = fullfile(TOP_LEVEL_DIR, '_HOL');
    COMPILE_DIR_Sesh = fullfile(COMPILE_DIR,SESSION_FILTER{1})
else
    COMPILE_DIR = TOP_LEVEL_DIR;   % raw _TeamData as before
    COMPILE_DIR_Sesh = fullfile(COMPILE_DIR,SESSION_FILTER{1})
end

if RUN_TEAMDATA_CONCAT
    COMPILE_DIR = fullfile(TOP_LEVEL_DIR, '_HOL');
    COMPILE_DIR_Sesh = fullfile(COMPILE_DIR,SESSION_FILTER{1})
    smp_sort_hol_to_teams(COMPILE_DIR_Sesh, DRIVER_ALIAS_FILE)
end


%% =========================================================
%  SECTION 5: COMPILE
%  Run this cell when you have new/changed .ld files.
%  Already-cached files are skipped automatically.
% =========================================================

switch lower(MODE)

    % ----------------------------------------------------------
    case 'serial'
        compile_opts.beacon_check = true;
    % ----------------------------------------------------------
        cache = smp_compile_event(COMPILE_DIR_Sesh, TEAM_FILTER, channels, ...
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
            worker_cfg.track               = TRACK;
            worker_cfg.top_level_dir       = TOP_LEVEL_DIR;
            worker_cfg.min_lt              = min_lt;
            worker_cfg.max_lt              = max_lt;
            worker_cfg.T_gated             = T_gated;
            % Forward all compile_opts fields that process_stream needs
            worker_cfg.max_traces          = compile_opts.max_traces;
            worker_cfg.detect_pitlane      = compile_opts.detect_pitlane;
            worker_cfg.fcy_channel         = compile_opts.fcy_channel;
            worker_cfg.br2_channel         = compile_opts.br2_channel;
            worker_cfg.br2_protocol        = compile_opts.br2_protocol;
            worker_cfg.beacon_check        = compile_opts.beacon_check;
            if isfield(compile_opts, 'all_laps'),         worker_cfg.all_laps         = compile_opts.all_laps;         end
            if isfield(compile_opts, 'load_all_channels'),worker_cfg.load_all_ch      = compile_opts.load_all_channels; end
            if isfield(compile_opts, 'concat_csv_dir'),   worker_cfg.concat_csv_dir   = compile_opts.concat_csv_dir;   end
            if isfield(compile_opts, 'showConcatReport'), worker_cfg.show_report      = compile_opts.showConcatReport; end
            if isfield(compile_opts, 'uniqueFingerprint'),worker_cfg.unique_fp        = compile_opts.uniqueFingerprint; end
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
                if isfield(pc, 'laps')
                    if ~isfield(cache, 'laps'), cache.laps = struct(); end
                    keys_lp = fieldnames(pc.laps);
                    for k = 1:numel(keys_lp)
                        cache.laps.(keys_lp{k}) = pc.laps.(keys_lp{k});
                    end
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

%% SMP_TYRE_CHANGES_FROM_CACHE
% Infer tyre changes from cache by comparing tyre wheel-sensor ID lap-to-lap.
% Only considers laps > 5. Outputs a pit_summary-style table.
%
% Usage:
%   Run after loading cache (e.g. cache = smp_cache_load(top_level_dir))
%   Requires driver_map in workspace for car number lookup.

TYRE_CHS = {'TPM1S_FL_WS_ID', 'TPM1S_FR_WS_ID', ...
             'TPM1S_RL_WS_ID', 'TPM1S_RR_WS_ID'};
corners  = {'FL', 'FR', 'RL', 'RR'};
MIN_LAP  = 5;

% ── Accumulators ──────────────────────────────────────────────────────────
rows = {};   % {driver, car, lap, FL, FR, RL, RR, n_tyres}

group_keys = fieldnames(cache.stats);

for g = 1:numel(group_keys)
    gk   = group_keys{g};
    stat = cache.stats.(gk);

    if ~isfield(stat, 'Beacon') || ~isfield(stat.Beacon, 'lap_numbers'), continue; end

    lap_nums = stat.Beacon.lap_numbers(:);   % [N x 1]
    n_laps   = numel(lap_nums);
    if n_laps < 2, continue; end

    % Resolve driver label from manifest
    drv = gk;   % fallback
    if isfield(cache, 'manifest') && ismember('Driver', cache.manifest.Properties.VariableNames)
        mask = strcmp(cache.manifest.GroupKey, gk);
        if any(mask)
            drv = strtrim(char(string(cache.manifest.Driver(find(mask,1)))));
        end
    end

    % Resolve car number from driver_map
    car = '';
    if exist('driver_map', 'var') && ~isempty(driver_map) && isstruct(driver_map)
        name_strip = regexprep(lower(strtrim(drv)), '[^a-z0-9]', '');
        dm_keys    = fieldnames(driver_map);
        entry      = [];
        % 1. Direct key
        if isfield(driver_map, drv)
            entry = driver_map.(drv);
        end
        % 2. Strip-normalised key
        if isempty(entry)
            for k = 1:numel(dm_keys)
                if strcmp(name_strip, regexprep(lower(dm_keys{k}), '[^a-z0-9]', ''))
                    entry = driver_map.(dm_keys{k}); break;
                end
            end
        end
        % 3. Alias search
        if isempty(entry)
            for k = 1:numel(dm_keys)
                e = driver_map.(dm_keys{k});
                if ~isfield(e, 'aliases'), continue; end
                for a = 1:numel(e.aliases)
                    if strcmp(name_strip, regexprep(lower(e.aliases{a}), '[^a-z0-9]', ''))
                        entry = e; break;
                    end
                end
                if ~isempty(entry), break; end
            end
        end
        if ~isempty(entry) && isfield(entry, 'num') && ~isempty(entry.num)
            car = entry.num;
        end
    end

    % Pull tyre ID stats per lap for each corner
    id_change = struct();   % intra-lap delta (non-zero = ID changed mid-lap)
    id_mean   = struct();   % per-lap mean (constant for stable sensor; differs across pitstop)
    for c = 1:4
        ch_field = matlab.lang.makeValidName(TYRE_CHS{c});
        if isfield(stat, ch_field)
            id_change.(corners{c}) = stat.(ch_field).change(:);
            id_mean.(corners{c})   = stat.(ch_field).mean(:);
        else
            id_change.(corners{c}) = nan(n_laps, 1);
            id_mean.(corners{c})   = nan(n_laps, 1);
        end
    end

    % Compare lap i to lap i+1; only flag laps where lap_number > MIN_LAP
    for i = 1:(n_laps - 1)
        lap_i    = lap_nums(i);
        lap_next = lap_nums(i+1);

        % Must be consecutive laps and both > MIN_LAP
        if lap_next ~= lap_i + 1, continue; end
        if lap_i <= MIN_LAP,      continue; end

        changed = false(1, 4);
        n_ch    = 0;
        for c = 1:4
            % Primary: intra-lap change is non-zero (new ID appeared mid pit-lap)
            v_chg = id_change.(corners{c})(i+1);
            mid_lap_change = ~isnan(v_chg) && v_chg ~= 0;

            % Fallback: mean differs lap-to-lap (new ID appeared at lap boundary)
            m_before = id_mean.(corners{c})(i);
            m_after  = id_mean.(corners{c})(i+1);
            boundary_change = ~isnan(m_before) && ~isnan(m_after) && m_before ~= m_after;

            if mid_lap_change || boundary_change
                changed(c) = true;
                n_ch = n_ch + 1;
            end
        end

        if n_ch == 0, continue; end   % no change — skip

        rows{end+1} = {drv, car, lap_next, changed(1), changed(2), changed(3), changed(4), n_ch}; %#ok
    end
end

% ── Build output table ────────────────────────────────────────────────────
if isempty(rows)
    fprintf('No tyre changes detected.\n');
    pit_summary = table();
else
    rows     = vertcat(rows{:});
    Driver   = string(rows(:,1));
    Car      = string(rows(:,2));
    Lap      = cell2mat(rows(:,3));
    FL       = logical(cell2mat(rows(:,4)));
    FR       = logical(cell2mat(rows(:,5)));
    RL       = logical(cell2mat(rows(:,6)));
    RR       = logical(cell2mat(rows(:,7)));
    NumTyres = cell2mat(rows(:,8));

    pit_summary = table(Car, Driver, Lap, NumTyres, FL, FR, RL, RR);
    pit_summary = sortrows(pit_summary, {'Car','Lap'});

    % Add sequential stop number per car
    StopNumber = zeros(height(pit_summary), 1);
    prev = ''; cnt = 0;
    for i = 1:height(pit_summary)
        if ~strcmp(char(pit_summary.Car(i)), prev)
            cnt = 1; prev = char(pit_summary.Car(i));
        else
            cnt = cnt + 1;
        end
        StopNumber(i) = cnt;
    end
    pit_summary.StopNumber = StopNumber;

    disp(pit_summary);
end

%% =========================================================
%  SECTION 6: FILTER CACHE TO SESSION(S) OF INTEREST
% =========================================================

SMP_filtered = smp_filter_cache(cache, alias, 'Session', SESSION_FILTER);
smp_filter_summary(SMP_filtered);

%% =========================================================
%  SECTION 8: PLOTS + POWERPOINT (per config file)
% ==========================================================
if PLOTTING
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

        handles = unique([holdFigs{~cellfun(@isempty, holdFigs)}]);
        set(handles, 'Visible', 'on');

        % smp_generate_pptx_report(holdFigs, plots, PPTX_TEMPLATE, OUTPUT_DIR, ...
        %                           base_report_name, PLOT_CONFIG_FILES{k}, ...
        %                           SESSION_FILTER, TEAM_FILTER, TRACK);
        % close all;
    end
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