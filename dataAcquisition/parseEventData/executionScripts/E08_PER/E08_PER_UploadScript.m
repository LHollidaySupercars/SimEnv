%% =========================================================
%  E08_PER_PlottingScript
%  Event-wide upload pass — run ONCE per event, independent of the
%  per-session E08_R25_PER_PlottingScript. Does not touch that script's
%  cache. Fires detached, non-blocking SQL pushes; does not wait for them.
% =========================================================
clear; clc;
t_script = tic;

%% ---- PATHS ----
TOP_LEVEL_DIR     = 'F:\2026\E08_PER\COM';
CHANNELS_FILE     = fullfile(pwd, 'dataAcquisition/Motec_MP/channels/channels.xlsx');
EVENT_ALIAS_FILE  = fullfile(pwd, 'dataAcquisition/Motec_MP/alias/eventAlias.xlsx');
DRIVER_ALIAS_FILE = fullfile(pwd, 'dataAcquisition/Motec_MP/alias/driverAlias.xlsx');
SEASON_FILE       = fullfile(pwd, 'trackDB/seasonOverview.xlsx');
RH_PATCH_FILE     = fullfile(pwd, 'dataAcquisition\parseEventData\executionScripts\E08_PER', 'E08_PER_Constants.xlsx');
COM_DIR           = 'F:\2026\E08_PER\COM';
RUN_AUGMENT_CHANNELS = true;
%% ---- EVENT CONFIG ----

TRACK = 'PER';

%% ---- UPLOAD CONFIG ----
upload_opts.track            = TRACK;
upload_opts.math_version     = 'v1.0';        % bump by hand after any lap_stats/flatten logic change
upload_opts.target           = 'azure_online'; % 'pocketbase' | 'azure_local' | 'azure_online'
upload_opts.flush_rows       = 400;
upload_opts.batch            = 200;
upload_opts.overwrite        = false;          % fallback only — math_version drives overwrite in SQL push
upload_opts.keep_worker_open = false;
upload_opts.verbose          = true;


% SECTION OPTIONS
PHASE_1_AUGMENT              = true;
%% ---- LOAD CONFIG ----
season      = smp_season_load(SEASON_FILE);
channels    = smp_channel_config_load(CHANNELS_FILE);
alias       = smp_alias_load(EVENT_ALIAS_FILE);
driver_map  = smp_driver_alias_load(DRIVER_ALIAS_FILE);

% =========================================================================
%%  SECTION 1: AUGMENT COM FILES
% =========================================================================
if PHASE_1_AUGMENT

    driver_map = [];
    if  isfile(DRIVER_ALIAS_FILE)
        try
            driver_map = smp_driver_alias_load(cfg.driver_alias_file);
            cfg.driver_map = driver_map;
        catch
            fprintf('  [WARN] Could not load driver alias — RH patch table will lack Driver/MAN.\n');
        end
    end
    
    % ---- Load RH patch table from Excel (replaces hardcoded Car/FrontRH/RearRH/Session) ----
    % cfg.rh_patch_file : path to an Excel file with columns Car | FrontRH | RearRH | Session
    cfg.PatchRH = smp_load_rh_patch(RH_PATCH_FILE, driver_map);
    
    PHASE6_MODE = 'serial';
    cfg.session = 'Q23'
    if RUN_AUGMENT_CHANNELS
        fprintf('\n%s\n', repmat('=', 1, 60));
        fprintf('dPHASE 6 — Augment COM files  [%s]\n', cfg.session);
        fprintf('%s\n', repmat('=', 1, 60));
    
        if strcmp(PHASE6_MODE, 'serial')
            augment_com_files_serial(COM_DIR, CHANNELS_FILE, cfg, driver_map);
        else
            launch_parallel_workers_augment(COM_DIR, CHANNELS_FILE, cfg, ...
                N_WORKERS_AUG, KEEP_WORKERS_AUG_OPEN, TMP_DIR_AUG, driver_map);
        end
    end
    
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('VCS_CombineDatasets complete.\n');
    fprintf('%s\n\n', repmat('=', 1, 60));

end
% =========================================================================
%%  SECTION 2: UPLOAD TO SQL
% =========================================================================
smp_compile_event_upload(TOP_LEVEL_DIR, channels, season, driver_map, alias, upload_opts);

fprintf('\n=== E08_PER_PlottingScript (upload) complete: %.1f min ===\n', toc(t_script)/60);
fprintf('Note: SQL pushes are detached background processes — check %s\\_upload_queue\\*.log for status.\n', ...
    TOP_LEVEL_DIR);