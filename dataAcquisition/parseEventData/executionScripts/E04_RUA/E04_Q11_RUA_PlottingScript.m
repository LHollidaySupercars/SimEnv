%% =========================================================
%  E04_Q11_PLOTTINGSCRIPT
%  =========================================================
%  Reporting pipeline for one event/session: compile cache (serial or
%  parallel), filter to session(s) of interest, generate plots + PPTX,
%  optionally upload, save cache.
%
%  NOTE: TeamData concat and channel augmentation (custom/gated channels
%  written back to .ld) are handled upstream by the VCS_*_CombineDatasets
%  script. This script assumes _HOL / COM data already exists and only
%  compiles/reports on it.
% =========================================================
clear; clc; close all;
t_script = tic;
%%

% =========================================================================
%  AT-TRACK CONTROLS  — edit these, nothing else
% =========================================================================

cfg.event          = 'E04';
cfg.track          = 'RUA';
cfg.event_name     = 'RUA';
cfg.team_filter    = {};           % {} = all teams, e.g. {'T8R', 'WAU'}
cfg.session_filter = {'Q11'};
cfg.workshop       = false;        % true = no session filter on stint grouping
cfg.save_cache     = true;
cfg.plotting       = true;
cfg.parallel_save  = true;

cfg.mode           = 'parallel';     % 'serial' | 'parallel'   (compile mode)

% ---- Parallel worker options (ignored in serial mode) ----
cfg.n_workers          = 6;
cfg.tmp_dir            = fullfile(tempdir, 'smp_parallel');
cfg.poll_interval_s    = 3;
cfg.timeout_s          = 3600;
cfg.keep_workers_open  = false;    % false = cmd /c (auto-close on success)
                                    % true  = cmd /k (leave window open — for debugging)

% ---- Upload options ----
cfg.upload_target  = 'azure_online';   % 'pocketbase' | 'azure_local' | 'azure_online'
cfg.run_upload     = false;
cfg.batch_size     = 200;
cfg.overwrite      = false;

% =========================================================================
%  EVENT CONFIG  — edit when setting up a new event
% =========================================================================
cfg.root_folder      = fullfile('E:\2026',join([cfg.event,'_',cfg.track]) ,'COM');
cfg.root_folder      = fullfile('E:\2026',join([cfg.event,'_',cfg.track]) ,'_HOL\teamData'); % dirty replacement step to get pitstops
cfg.channels_file    = fullfile(pwd,'dataAcquisition/Motec_MP/channels/channels.xlsx');
cfg.event_alias_file = fullfile(pwd,'dataAcquisition\parseEventData\executionScripts',join([cfg.event,'_',cfg.track]),'eventAlias.xlsx');
cfg.driver_alias_file= fullfile(pwd,'dataAcquisition/Motec_MP/alias/driverAlias.xlsx');
cfg.plot_config_files= {fullfile(pwd,'dataAcquisition\Motec_MP\plottingRequest',join([cfg.event,'_',cfg.track]), join(['PR_',join([cfg.event,'_',cfg.track]),'_plotRequest.xlsx'])),...
                        fullfile(pwd,'dataAcquisition\Motec_MP\plottingRequest',join([cfg.event,'_',cfg.track]), join(['AR_',join([cfg.event,'_',cfg.track]),'_plotRequest.xlsx'])),...
                        fullfile(pwd,'dataAcquisition\Motec_MP\plottingRequest',join([cfg.event,'_',cfg.track]), join(['SR_',join([cfg.event,'_',cfg.track]),'_plotRequest.xlsx']))};
cfg.season_file      = fullfile(pwd,'trackDB/seasonOverview.xlsx');
cfg.pptx_template    = fullfile(pwd,'dataAcquisition/Motec_MP/plot/templates/SuperCars_PPT.pptx');
cfg.output_dir       = fullfile(pwd,'dataAcquisition/Motec_MP/plot/output',join([cfg.event,'_',cfg.track]));
cfg.date_from        = datetime(2026, 4, 18);   % auto-filled from sessionDate.xlsx (this session's date)
% cfg.plot_config_files= {'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest\E07_TSV\PR_E07TSV_plotRequest.xlsx',...
%     'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest\E07_TSV\AR_E07TSV_plotRequest.xlsx'};
% ---- Tuning defaults (rarely changed) ----
cfg.max_traces        = 4;
cfg.dist_n_points     = 1000;
cfg.dist_channel      = 'Odometer';
cfg.br2_channel       = 'BR2_Beacon_Number';
cfg.br2_protocol      = 'standard';    % 'standard' | 'TAS2025'
cfg.fcy_channel       = 'Sw_State_SC'; % Full Course Yellow flag channel
cfg.detect_pitlane    = true;
cfg.load_all_channels = true;          % true = load full file, no channel filter
cfg.show_concat_report= false;

% =========================================================================
%  DERIVED  — built automatically by resolve_cfg_plotting, do not edit
% =========================================================================
cfg = resolve_cfg_plotting(cfg);

fprintf('=== %s Report — %s ===\n\n', upper(cfg.mode), cfg.track);

% =========================================================================

% =========================================================================
%%  SECTION 4: LOAD CONFIG FILES
% =========================================================================
season                    = smp_season_load(cfg.season_file);
[channels, channel_rules] = smp_channel_config_load(cfg.channels_file);
alias                     = smp_alias_load(cfg.event_alias_file);
driver_map                = smp_driver_alias_load(cfg.driver_alias_file);
T_gated                   = readtable(cfg.channels_file, 'Sheet', 'gatedChannels', 'TextType', 'char');

% ---- compile_opts: everything smp_compile_event needs ----
compile_opts = build_compile_opts(cfg, channel_rules, T_gated);

% ---- plot_opts ----
plot_opts.fig_width  = 1200;
plot_opts.fig_height = 650;
plot_opts.font_size  = 11;
plot_opts.n_laps_avg = 3;
plot_opts.verbose    = true;
plot_opts.venue      = cfg.track;

% =========================================================================
%%  SECTION 5: COMPILE
%  Run this cell when you have new/changed .ld files.
%  Already-cached files are skipped automatically.
% =========================================================================
tic;
cfg.mode = 'parallel'
if strcmp(cfg.mode, 'serial')
    compile_opts.beacon_check = true;
    compile_opts.l180_mode       = 'keep_separate';
    cache = smp_compile_serial(cfg, compile_opts, channels, season, driver_map, alias);
    
elseif strcmp(cfg.mode, 'parallel')
    compile_opts.l180_mode       = 'keep_separate';
    cache = smp_compile_parallel(cfg, compile_opts, channels, channel_rules, season, driver_map, alias);
else
    warning('Unknown cfg.mode "%s" — use ''serial'' or ''parallel''.', cfg.mode);
end
parallelCompile = toc;

%% =========================================================================
%  SECTION 5a: SAVE CACHE
% =========================================================================
t_script = tic;
if cfg.save_cache
    fprintf('\nSaving cache...\n');
    try
        if isfield(cfg, 'parallel_save') && cfg.parallel_save
            smp_save_parallel(cfg.root_folder, cache, compile_opts.save_mode, alias, cfg);
        else
            smp_cache_save(cfg.root_folder, cache, compile_opts.save_mode, alias);
        end
        fprintf('Cache saved.\n');
    catch ME_save
        fprintf('[ERROR] Cache save failed: %s\n', ME_save.message);
    end
end

fprintf('\n=== Total time: %.1f minutes (%.0f seconds) ===\n', ...
    toc(t_script)/60, toc(t_script));

%% SMP_TYRE_CHANGES_FROM_CACHE
% Infer tyre changes from cache by comparing tyre wheel-sensor ID lap-to-lap.
% Only considers laps > 5. Outputs a pit_summary-style table.
%% SMP_TYRE_CHANGES_FROM_CACHE
% Infer tyre changes from cache by comparing tyre wheel-sensor ID lap-to-lap.
% Only considers laps > 5. Outputs a pit_summary-style table.
pit_summary = smp_tyre_changes_from_cache(cache, driver_map);
disp(pit_summary);
saveLocation =fullfile(pwd,'dataAcquisition\parseEventData\pitStop', join([cfg.event, '_',cfg.track], '_'));
if ~isfolder(saveLocation)
    mkdir(saveLocation)
end
writetable(pit_summary, fullfile(saveLocation, '26VCS_PitStop_RUA_E04_Q11.xlsx'))

% =========================================================================

% =========================================================================
%%  SECTION 6: FILTER CACHE TO SESSION(S) OF INTEREST
% =========================================================================
SMP_filtered = smp_filter_cache(cache, alias, 'Session', cfg.session_filter);
smp_filter_summary(SMP_filtered);

% =========================================================================
%%  SECTION 8: PLOTS + POWERPOINT (per config file)
% =========================================================================
if cfg.plotting
    PLOT = false;
    CLOSEALL = false;
    run_plotting(cfg, SMP_filtered, driver_map, plot_opts, PLOT, CLOSEALL);
end

% =========================================================================
%%  SECTION 9: UPLOAD TO SQL / POCKETBASE
% =========================================================================
if cfg.run_upload
    run_upload(cfg, cache);
else
    fprintf('\n[Upload] Skipped (cfg.run_upload = false)\n');
end

% ======================================================================= %
%  LOCAL FUNCTIONS
% ======================================================================= %

function cfg = resolve_cfg_plotting(cfg)
% RESOLVE_CFG_PLOTTING  Derive compile paths from event config.
%   Assumes _HOL concat + team-sort has already been done by the
%   VCS_*_CombineDatasets script — this script only compiles from it.
    cfg.compile_dir      = fullfile(cfg.root_folder);
    cfg.compile_dir_sesh = fullfile(cfg.compile_dir, cfg.session_filter{1});
end


function compile_opts = build_compile_opts(cfg, channel_rules, T_gated)
% BUILD_COMPILE_OPTS  Assemble the options struct passed to smp_compile_event.
    compile_opts.mode              = 'stream';
    compile_opts.track             = cfg.track;
    compile_opts.max_traces        = cfg.max_traces;
    compile_opts.dist_n_points     = cfg.dist_n_points;
    compile_opts.dist_channel      = cfg.dist_channel;
    compile_opts.verbose           = true;
    compile_opts.date_from         = cfg.date_from;
    compile_opts.saveCache         = true;
    compile_opts.save_mode         = 'session';   % 'legacy' | 'session'
    compile_opts.session_filter    = cfg.session_filter;
    compile_opts.load_all_channels = cfg.load_all_channels;
    compile_opts.concat_csv_dir    = cfg.output_dir;   % '' = skip CSV
    compile_opts.showConcatReport  = cfg.show_concat_report;
    compile_opts.br2_channel       = cfg.br2_channel;
    compile_opts.br2_protocol      = cfg.br2_protocol;
    compile_opts.channel_rules     = channel_rules;
    compile_opts.detect_pitlane    = cfg.detect_pitlane;
    compile_opts.fcy_channel       = cfg.fcy_channel;
    compile_opts.beacon_check      = false;   % overridden to true for serial mode
    compile_opts.T_gated           = T_gated; % gated channels computed during compile
    if isfield(cfg, 'l180_mode') && ~isempty(cfg.l180_mode)
        compile_opts.l180_mode = cfg.l180_mode;
    else
        compile_opts.l180_mode = 'drop_duplicate';
    end
end


function cache = smp_compile_serial(cfg, compile_opts, channels, season, driver_map, alias)
% SMP_COMPILE_SERIAL  Serial compile of cfg.compile_dir_sesh.
    cache = smp_compile_event(cfg.compile_dir_sesh, cfg.team_filter, channels, ...
                               season, driver_map, alias, compile_opts);
end


function cache = smp_compile_parallel(cfg, compile_opts, channels, channel_rules, season, driver_map, alias)
% SMP_COMPILE_PARALLEL  Scan/diff, split, launch workers, poll, and merge
%   partial caches for a parallel compile pass.

    % ---- Prep tmp dir ----
    if ~exist(cfg.tmp_dir, 'dir'), mkdir(cfg.tmp_dir); end
    delete(fullfile(cfg.tmp_dir, 'partial_*.mat'));
    delete(fullfile(cfg.tmp_dir, 'done_*.flag'));
    delete(fullfile(cfg.tmp_dir, 'chunk_*.mat'));
    delete(fullfile(cfg.tmp_dir, 'worker_cfg.mat'));

    fprintf('============================================\n');
    fprintf('  Parallel Compile\n');
    fprintf('  Workers : %d\n', cfg.n_workers);
    fprintf('  TMP     : %s\n', cfg.tmp_dir);
    fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('============================================\n\n');

    % ---- Scan and diff ----
    scan_all = smp_scan_folders(cfg.compile_dir_sesh);
    if ~isempty(cfg.team_filter)
        keep     = ismember({scan_all.acronym}, cfg.team_filter);
        scan_all = scan_all(keep);
    end

    cache = smp_cache_load(cfg.compile_dir_sesh, cfg.session_filter);

    % Migrate old cache structure if needed
    if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
    if ~isfield(cache, 'traces'), cache.traces = struct(); end
    if ~isfield(cache, 'mode'),   cache.mode   = 'stream'; end
    if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
        cache.manifest.GroupKey = repmat({''}, height(cache.manifest), 1);
    end

    % Apply date_from filter
    if ~isempty(cfg.date_from)
        date_from_dn = datenum(cfg.date_from);
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
        return;
    end

    fprintf('%d file(s) to process.\n', numel(to_load));

    if cfg.workshop
        groups = smp_append_stints(to_load, driver_map, alias);
    else
        groups = smp_append_stints(to_load, driver_map, alias, cfg.session_filter);
    end

    chunk_groups(cfg, groups);

    worker_cfg = build_worker_cfg(cfg, compile_opts, channels, channel_rules, season, driver_map, alias);
    worker_cfg.l180_mode = compile_opts.l180_mode;
    save(fullfile(cfg.tmp_dir, 'worker_cfg.mat'), 'worker_cfg');
    fprintf('\n');

    launch_compile_workers(cfg);
    poll_compile_workers(cfg);

    cache = merge_partial_caches(cfg, cache);
end


function chunk_groups(cfg, groups)
% CHUNK_GROUPS  Split groups across cfg.n_workers and save one chunk_W.mat each.
    n_groups   = numel(groups);
    chunk_size = ceil(n_groups / cfg.n_workers);
    fprintf('%d group(s) across %d worker(s).\n\n', n_groups, cfg.n_workers);

    for w = 1:cfg.n_workers
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
        save(fullfile(cfg.tmp_dir, sprintf('chunk_%d.mat', w)), 'worker_groups');
    end
end


function worker_cfg = build_worker_cfg(cfg, compile_opts, channels, channel_rules, season, driver_map, alias)
% BUILD_WORKER_CFG  Assemble the struct saved for smp_compile_worker to load.
    [min_lt, max_lt] = smp_season_get(season, cfg.track);

    worker_cfg.test_mode           = false;
    worker_cfg.channels_to_extract = channels;
    worker_cfg.channel_rules       = channel_rules;
    worker_cfg.driver_map          = driver_map;
    worker_cfg.alias               = alias;
    worker_cfg.season              = season;
    worker_cfg.track               = cfg.track;
    worker_cfg.top_level_dir       = cfg.root_folder;
    worker_cfg.min_lt              = min_lt;
    worker_cfg.max_lt              = max_lt;
    worker_cfg.T_gated             = compile_opts.T_gated;

    % Forward all compile_opts fields that process_stream needs
    worker_cfg.max_traces     = compile_opts.max_traces;
    worker_cfg.detect_pitlane = compile_opts.detect_pitlane;
    worker_cfg.fcy_channel    = compile_opts.fcy_channel;
    worker_cfg.br2_channel    = compile_opts.br2_channel;
    worker_cfg.br2_protocol   = compile_opts.br2_protocol;
    worker_cfg.beacon_check   = compile_opts.beacon_check;
    if isfield(compile_opts, 'all_laps'),          worker_cfg.all_laps       = compile_opts.all_laps;         end
    if isfield(compile_opts, 'load_all_channels'), worker_cfg.load_all_ch    = compile_opts.load_all_channels; end
    if isfield(compile_opts, 'concat_csv_dir'),    worker_cfg.concat_csv_dir = compile_opts.concat_csv_dir;   end
    if isfield(compile_opts, 'showConcatReport'),  worker_cfg.show_report    = compile_opts.showConcatReport; end
    if isfield(compile_opts, 'uniqueFingerprint'), worker_cfg.unique_fp      = compile_opts.uniqueFingerprint; end
end


function launch_compile_workers(cfg)
% LAUNCH_COMPILE_WORKERS  Spawn cfg.n_workers MATLAB worker processes.
    win_mode = 'cmd /c'; if cfg.keep_workers_open, win_mode = 'cmd /k'; end
    fprintf('Launching %d compile worker(s)...\n', cfg.n_workers);
    matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');
    for w = 1:cfg.n_workers
        sys_cmd = sprintf('start "SMP Worker %d" %s ""%s" -batch "smp_compile_worker(%d, ''%s'')"', ...
            w, win_mode, matlab_exe, w, strrep(cfg.tmp_dir, '\', '\\'));
        system(sys_cmd);
        fprintf('  Worker %d launched\n', w);
        pause(1.5);
    end
end


function poll_compile_workers(cfg)
% POLL_COMPILE_WORKERS  Block until all workers write their done_*.flag.
    fprintf('\nWaiting for workers...\n\n');
    t_poll     = tic;
    last_count = -1;
    while true
        done_flags = dir(fullfile(cfg.tmp_dir, 'done_*.flag'));
        n_done     = numel(done_flags);
        if n_done ~= last_count
            fprintf('[%s]  %d / %d worker(s) done\n', ...
                datestr(now,'HH:MM:SS'), n_done, cfg.n_workers);
            last_count = n_done;
        end
        if n_done >= cfg.n_workers
            fprintf('\nAll workers finished.\n\n');
            break;
        end
        if toc(t_poll) > cfg.timeout_s
            warning('Timeout after %ds — check worker windows for errors.', cfg.timeout_s);
        end
        pause(cfg.poll_interval_s);
    end
end


function cache = merge_partial_caches(cfg, cache)
% MERGE_PARTIAL_CACHES  Merge each worker's partial_W.mat into cache.
    fprintf('Merging results...\n');
    for w = 1:cfg.n_workers
        partial_file = fullfile(cfg.tmp_dir, sprintf('partial_%d.mat', w));
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


% end


function run_plotting(cfg, SMP_filtered, driver_map, plot_opts, PLOT, CLOSEALL)
% RUN_PLOTTING  Generate plots + PPTX for each configured plot-request file.
    if iscell(cfg.session_filter)
        session_str = strjoin(cfg.session_filter, '_');
    else
        session_str = cfg.session_filter;
    end
    team_str         = strjoin(cfg.team_filter, '_'); %#ok<NASGU>
    base_report_name = sprintf('26VCS_%s%s_%s', cfg.event, cfg.track, session_str); %#ok<NASGU>

    plot_config_files = cfg.plot_config_files;
    if ischar(plot_config_files)
        plot_config_files = {plot_config_files};
    end

    for k = 1:numel(plot_config_files)
        fprintf('\n=== Report %d/%d: %s ===\n', k, numel(plot_config_files), plot_config_files{k});

        plots    = smp_plot_config_load(plot_config_files{k});
        holdFigs = smp_plot_from_config(SMP_filtered, plots, smp_colours(), driver_map, plot_opts);

        handles = unique([holdFigs{~cellfun(@isempty, holdFigs)}]);
        set(handles, 'Visible', 'on');
        if PLOT
        smp_generate_pptx_report(holdFigs, plots, cfg.pptx_template, cfg.output_dir, ...
                                  base_report_name, plot_config_files{k}, ...
                                  cfg.session_filter, cfg.team_filter, cfg.track);
        end
        if CLOSEALL
            close all;
        end
    end
end


function run_upload(cfg, cache)
% RUN_UPLOAD  Flatten cache stats and push to the configured target.
    fprintf('\n========================================\n');
    fprintf('  DATA UPLOAD — TARGET: %s\n', upper(cfg.upload_target));
    fprintf('========================================\n\n');

    fprintf('[Upload 1/3] Using compiled cache for event "%s"...\n', cfg.event_name);
    cache_up = cache;

    if ~isfield(cache_up, 'stats') || isempty(fieldnames(cache_up.stats))
        warning('Cache is empty — skipping upload. Run compile step first.');
        return;
    end

    fprintf('      Cache: %d manifest rows, %d group keys.\n', ...
        height(cache_up.manifest), numel(fieldnames(cache_up.stats)));

    fprintf('[Upload 2/3] Flattening stats...\n');
    T = smp_flatten_stats(cache_up, cfg.event_name);
    if ismember('id', T.Properties.VariableNames)
        T = removevars(T, 'id');
    end

    if isempty(T) || height(T) == 0
        warning('Flatten produced no rows — skipping upload.');
        return;
    end

    fprintf('[Upload 3/3] Pushing %d rows to %s...\n', height(T), upper(cfg.upload_target));

    switch lower(cfg.upload_target)
        case 'pocketbase'
            opts_pb           = struct();
            opts_pb.batch     = cfg.batch_size;
            opts_pb.overwrite = cfg.overwrite;
            opts_pb.dry_run   = false;

            result = smp_push_to_pocketbase(T, opts_pb);
            fprintf('\n      Upload complete: %d rows uploaded, %d failed.\n', ...
                result.n_uploaded, result.n_failed);

        case {'azure_local', 'azure_online'}
            if strcmpi(cfg.upload_target, 'azure_online')
                fprintf('      >> Browser MFA popup may appear.\n');
            end

            conn = smp_sql_connect(cfg.upload_target);

            opts_sql           = struct();
            opts_sql.batch     = cfg.batch_size;
            opts_sql.overwrite = cfg.overwrite;
            opts_sql.dry_run   = false;

            result = smp_push_to_sql(T, conn, opts_sql);
            fprintf('\n      Upload complete: %d rows uploaded, %d failed.\n', ...
                result.n_uploaded, result.n_failed);

            assignin('base', 'sql_conn', conn);
            fprintf('      Connection stored in workspace as ''sql_conn''.\n');
    end
end