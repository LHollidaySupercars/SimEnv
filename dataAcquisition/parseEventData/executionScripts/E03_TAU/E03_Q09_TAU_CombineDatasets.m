%% VCS_CombineDatasets.m
% Master pipeline: align TeamData, ECU, and L180 data for one event.
%
% Phases:
%   1  TeamData concat  — multi-stint .ld files → one HOL file per driver/session
%   2  ECU concat       — multi-file ECU per driver → single concatenated file
%   3  Split            — split ECU, L180, and TeamData HOL by ECU_Uptime boundaries
%   4  Pair             — match Dash/ECU/L180 by filename, validate with RPM xcorr
%   5  Merge            — write aligned COM .ld with ECU channels merged onto Dash

% addpath(genpath('dataAcquisition/Motec_MP'));
% addpath(genpath('dataAcquisition/parseEventData'));
addpath(genpath(fullfile(pwd, 'dataAcquisition\Motec_MP\smp_concat_helpers')));

% =========================================================================
%  AT-TRACK CONTROLS  — edit these, nothing else
% =========================================================================

SESSION   = 'Q09';   % session to process (used in all phases)

DRIVERS   = {};      % {} = all drivers
                     % car numbers:  {'18'}  or  {'18','99'}
                     % TLAs:         {'MOS'} or  {'MOS','DEP'}

OVERWRITE = true;    % true = re-process existing output files

% Phase 1 parallel options
PHASE1_MODE        = 'parallel';   % 'serial' | 'parallel'
N_WORKERS          = 6;       % 'auto' = one worker per driver, or integer e.g. 8
KEEP_WORKERS_OPEN  = true;         % true = cmd /k (windows stay open at report popup)
TMP_DIR            = '';           % '' = auto → <root_folder>\_tmp_parallel

% Phase 2 parallel options
PHASE2_MODE        = 'parallel';   % 'serial' | 'parallel'
N_WORKERS_ECU      = 6;       % 'auto' = one worker per driver, or integer e.g. 8
KEEP_WORKERS_ECU_OPEN = false;     % true = cmd /k (windows stay open)
TMP_DIR_ECU        = '';           % '' = auto → <root_folder>\_tmp_ecu_concat

% Phase 4 parallel options
PHASE4_MODE        = 'parallel';   % 'serial' | 'parallel'
N_WORKERS_PAIR     = 6;       % number of workers for Phase 4 pairing
KEEP_WORKERS_PAIR_OPEN = false;    % true = cmd /k (windows stay open)
TMP_DIR_PAIR       = '';           % '' = auto → <root_folder>\_tmp_pair_phase

% Phase 6 parallel options
PHASE6_MODE            = 'parallel';   % 'serial' | 'parallel'
N_WORKERS_AUG          = 6;            % number of workers for Phase 6 augmentation
KEEP_WORKERS_AUG_OPEN  = false;        % true = cmd /k (windows stay open)
TMP_DIR_AUG            = '';           % '' = auto → <root_folder>\_tmp_augment

% Phase toggles — turn off phases you don't need to re-run
RUN_TEAMDATA_CONCAT    = true;
RUN_ECU_CONCAT         = true;
RUN_SPLIT              = true;
RUN_PAIR               = true;
RUN_MERGE              = true;
RUN_L180_SORT          = true;
RUN_L180               = true;
RUN_XCORR_CHECK        = true;   % add per-sample engine residual channels to combined files
RUN_AUGMENT_CHANNELS   = true;   % Phase 6: run smp_custom_channels + smp_gated_channels on all COM files
cfg.rh_patch_file      = fullfile( pwd, 'dataAcquisition\parseEventData\executionScripts\E03_Q09', 'E03_TAU_Constants.xlsx');
CHANNELS_FILE          = fullfile( pwd, 'dataAcquisition\Motec_MP\channels\channels.xlsx');

% =========================================================================
%  EVENT CONFIG  — edit when setting up a new event
% =========================================================================
cfg.root_folder  = 'E:\2026\E03_TAU';   % event root — all paths derived from here
cfg.hol_venue    = 'Sydney Motorsport Park';
cfg.hol_event    = 'E03_TAU';
cfg.event_date   = '2026-04-11';   % auto-filled from sessionDate.xlsx (this session's date) — used by Phase 1 (TeamData date filter) and Phase 4b (L180 sort)

cfg.warmup_beacon_chs  = {'Lap Beacon Number','Lap_Beacon_Number','Lap_Number','Lap Number'};
cfg.ridealong_car_nums = {};

% =========================================================================
%  TUNING DEFAULTS  — rarely changed
% =========================================================================
cfg.rpm_ch        = 'Engine_Speed';   % shared across Dash, ECU, and L180
cfg.ert_ch        = 'ECU_Uptime';     % shared ERT channel name across ECU, L180, TeamData
cfg.resample_hz   = 100;              % shared: Phase 4 and Phase 5
cfg.max_offset_s  = 4500;            % shared: Phase 4 and Phase 5
cfg.rpm_min       = 500;              % shared: Phase 4 and Phase 5
cfg.quality_min   = 0.01;
cfg.min_gap_s     = 1000;
cfg.min_seg_s     = 650;
cfg.max_overlap_s = -30;              % Phase 2 ECU concat
cfg.ecu_format    = true;
cfg.unique_fp     = true;
cfg.show_report   = true;
cfg.split_on_reset  = true;
cfg.rename_output   = true;
cfg.l180_ecu_format = false;

% =========================================================================
%  DERIVED  — built automatically by resolve_cfg, do not edit
% =========================================================================
cfg = resolve_cfg(cfg, SESSION, DRIVERS, OVERWRITE);

% =========================================================================
%%  PHASE 1 — TEAMDATA CONCAT
% =========================================================================
if RUN_TEAMDATA_CONCAT
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 1 — TeamData concat\n');
    fprintf('%s\n', repmat('=', 1, 60));

    concat_cfg.event_date          = cfg.event_date;
    concat_cfg.date_tolerance_days = 0;
    concat_cfg.flagged_paths       = {};
    concat_cfg.root_folder         = cfg.root_folder;
    concat_cfg.td_input_dir        = fullfile(cfg.root_folder, '_TeamData');
    concat_cfg.td_hol_output_dir   = fullfile(cfg.root_folder, '_HOL','teamData');
    concat_cfg.hol_venue           = cfg.hol_event;
    concat_cfg.hol_event           = sprintf('%s%s', cfg.hol_event, cfg.hol_venue);
    concat_cfg.event_alias_file    = cfg.event_alias_file;
    concat_cfg.driver_alias_file   = cfg.driver_alias_file;
    concat_cfg.session_filter      = cfg.session_filter;
    concat_cfg.unique_fp           = true;
    concat_cfg.show_report         = true;
    concat_cfg.overwrite           = false;
    concat_cfg.driver_filter       = {};
    concat_cfg.team_filter         = {};
    if strcmp(PHASE1_MODE, 'serial')
        smp_concat_teamdata(concat_cfg);
    else
        p1_tmp = TMP_DIR;
        if isempty(p1_tmp)
            p1_tmp = fullfile(concat_cfg.root_folder, '_tmp_parallel');
        end
        n_workers_p1 = launch_parallel_workers(concat_cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR);
        smp_wait_for_workers(p1_tmp, n_workers_p1);
    end
    % Sort HOL output into team subfolders
    COMPILE_DIR      = fullfile(cfg.root_folder, '_HOL','teamData');
    COMPILE_DIR_Sesh = fullfile(COMPILE_DIR, SESSION);
    smp_sort_hol_to_teams(COMPILE_DIR_Sesh, cfg.driver_alias_file);
end

% =========================================================================
%%  PHASE 2 — ECU CONCAT
% =========================================================================
if RUN_ECU_CONCAT
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 2 — ECU concat\n');
    fprintf('%s\n', repmat('=', 1, 60));
    if strcmp(PHASE2_MODE, 'serial')
        smp_concat_ecu_per_driver(cfg);
    else
        launch_parallel_workers_ecu(cfg, N_WORKERS_ECU, KEEP_WORKERS_ECU_OPEN, TMP_DIR_ECU);
    end
end

% =========================================================================
%%  PHASE 3 — SPLIT
% =========================================================================
if RUN_SPLIT
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 3 — Split (ECU + L180 + TeamData)\n');
    fprintf('%s\n', repmat('=', 1, 60));
    smp_split_ecu_by_uptime(cfg);
end

% =========================================================================
%%  PHASE 4 — PAIR ECU + TeamData
% =========================================================================
pairs_excel = '';
if RUN_PAIR
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 4 — Pair sessions  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    cfg.overwrite   = false;
    if strcmp(PHASE4_MODE, 'serial')
        pairs_excel = smp_pair_sessions(cfg);
    elseif strcmp(PHASE4_MODE, 'parallel')
        pairs_excel = launch_parallel_workers_pair(cfg, N_WORKERS_PAIR, KEEP_WORKERS_PAIR_OPEN, TMP_DIR_PAIR);
    end

    cfg.pairs_excel = pairs_excel;
end

% =========================================================================
%%  PHASE 4c — ECU/DASH RESIDUAL CHECK
% =========================================================================
if RUN_XCORR_CHECK
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 4c — ECU/Dash engine residual  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    add_residual_channels(cfg.com_dir, ...
        cfg.com_ecu_rpm_ch, cfg.dash_rpm_ch, cfg.resid_ecu_dash_ch, cfg.resample_hz);
end

% =========================================================================
%%  PHASE 5a — SORT L180 TO HOL
% =========================================================================
if RUN_L180_SORT
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 4b — Sort L180 to HOL  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    cfg.l180_input_dir      = fullfile(cfg.root_folder, 'L180');
    cfg.move                = false;
    cfg.dry_run             = false;
    cfg.date_tolerance_days = 1;
    smp_sort_l180_to_hol(cfg);
end

% =========================================================================
%%  PHASE 5 — PAIR L180 ONTO COMBINED
% =========================================================================
if RUN_L180
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 5 — Pair L180 onto Combined  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    cfg.overwrite = true;
    % Replace this when you want to connect dash to L180
    cfg.com_rpm_ch         = 'Engine_Speed';
    smp_pair_l180(cfg);
    smp_sort_hol_to_teams(cfg.com_dir, cfg.driver_alias_file);
end

% =========================================================================
%%  PHASE 5b — L180 RESIDUAL CHECKS
% =========================================================================
if RUN_XCORR_CHECK && RUN_L180
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 5b — L180 engine residuals  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    add_residual_channels(fullfile(cfg.com_dir, '01_T8R'), ...
        cfg.com_l180_rpm_ch, cfg.dash_rpm_ch,    cfg.resid_l180_dash_ch, cfg.resample_hz);
    add_residual_channels(fullfile(cfg.com_dir, '01_T8R'), ...
        cfg.com_l180_rpm_ch, cfg.com_ecu_rpm_ch, cfg.resid_l180_ecu_ch,  cfg.resample_hz);
    add_residual_channels(fullfile(cfg.com_dir, '03_WTG'), ...
        cfg.com_l180_rpm_ch, cfg.dash_rpm_ch,    cfg.resid_l180_dash_ch, cfg.resample_hz);
    add_residual_channels(fullfile(cfg.com_dir, '03_WTG'), ...
        cfg.com_l180_rpm_ch, cfg.com_ecu_rpm_ch, cfg.resid_l180_ecu_ch,  cfg.resample_hz);
    add_residual_channels(fullfile(cfg.com_dir, '10_T18'), ...
        cfg.com_l180_rpm_ch, cfg.dash_rpm_ch,    cfg.resid_l180_dash_ch, cfg.resample_hz);
    add_residual_channels(fullfile(cfg.com_dir, '10_T18'), ...
        cfg.com_l180_rpm_ch, cfg.com_ecu_rpm_ch, cfg.resid_l180_ecu_ch,  cfg.resample_hz);
end

% =========================================================================
%%  PHASE 6 — AUGMENT COM FILES WITH CUSTOM + GATED CHANNELS
% =========================================================================
% ---- Load driver alias map (needed to resolve Driver + manufacturer) ----
driver_map = [];
if isfield(cfg, 'driver_alias_file') && isfile(cfg.driver_alias_file)
    try
        driver_map = smp_driver_alias_load(cfg.driver_alias_file);
        cfg.driver_map = driver_map;
    catch
        fprintf('  [WARN] Could not load driver alias — RH patch table will lack Driver/MAN.\n');
    end
end

% ---- Load RH patch table from Excel (replaces hardcoded Car/FrontRH/RearRH/Session) ----
% cfg.rh_patch_file : path to an Excel file with columns Car | FrontRH | RearRH | Session
cfg.PatchRH = smp_load_rh_patch(cfg.rh_patch_file, driver_map);

PHASE6_MODE = 'serial';

if RUN_AUGMENT_CHANNELS
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('dPHASE 6 — Augment COM files  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));

    if strcmp(PHASE6_MODE, 'serial')
        augment_com_files_serial(cfg.com_dir, CHANNELS_FILE, cfg, driver_map);
    else
        launch_parallel_workers_augment(cfg.com_dir, CHANNELS_FILE, cfg, ...
            N_WORKERS_AUG, KEEP_WORKERS_AUG_OPEN, TMP_DIR_AUG, driver_map);
    end
end

fprintf('\n%s\n', repmat('=', 1, 60));
fprintf('VCS_CombineDatasets complete.\n');
fprintf('%s\n\n', repmat('=', 1, 60));
%%

smp_sort_hol_to_teams(cfg.com_dir, cfg.driver_alias_file);

%%
%{
% Debug helper — visually verify Dash/ECU alignment after xcorr.
% Update paths and uncomment to use.
smp_plot_pair_check(...
    '/Volumes/JHU/E06_DAR/_TeamData/_HOL/Q17/ALL_2026_Q17.ld', ...
    '/Volumes/JHU/E06_DAR/ECU/HOL/Q17/ALL_2026_Q17.ld', ...
    'ALL Q17');
%}

% NOTE: all local functions previously here now live in
% dataAcquisition\Motec_MP\smp_concat_helpers\ as individual files on the path.
% See that folder for: augment_com_files_serial, launch_parallel_workers_augment,
% recursive_find_ld, filter_aug_files, resolve_driver_tla, resolve_cfg,
% launch_parallel_workers, launch_parallel_workers_ecu, add_residual_channels,
% launch_parallel_workers_pair, smp_plot_pair_check, build_stem_map, extract_stem,
% extract_tla_session, strip_common_prefix, local_resolve_manufacturer_by_tla,
% resolve_tla_by_car_number, local_resolve_manufacturer, smp_wait_for_workers.

% %% VCS_CombineDatasets.m
% % Master pipeline: align TeamData, ECU, and L180 data for one event.
% %
% % Phases:
% %   1  TeamData concat  — multi-stint .ld files → one HOL file per driver/session
% %   2  ECU concat       — multi-file ECU per driver → single concatenated file
% %   3  Split            — split ECU, L180, and TeamData HOL by ECU_Uptime boundaries
% %   4  Pair             — match Dash/ECU/L180 by filename, validate with RPM xcorr
% %   5  Merge            — write aligned COM .ld with ECU channels merged onto Dash
% 
% % addpath(genpath('dataAcquisition/Motec_MP'));
% % addpath(genpath('dataAcquisition/parseEventData'));
% 
% % =========================================================================
% %  AT-TRACK CONTROLS  — edit these, nothing else
% % =========================================================================
% 
% SESSION   = 'Q09';   % session to process (used in all phases)
% 
% DRIVERS   = {};      % {} = all drivers
%                      % car numbers:  {'18'}  or  {'18','99'}
%                      % TLAs:         {'MOS'} or  {'MOS','DEP'}
% 
% OVERWRITE = true;    % true = re-process existing output files
% 
% % Phase 1 parallel options
% PHASE1_MODE        = 'parallel';   % 'serial' | 'parallel'
% N_WORKERS          = 6;       % 'auto' = one worker per driver, or integer e.g. 8
% KEEP_WORKERS_OPEN  = true;         % true = cmd /k (windows stay open at report popup)
% TMP_DIR            = '';           % '' = auto → <root_folder>\_tmp_parallel
% 
% % Phase 2 parallel options
% PHASE2_MODE        = 'parallel';   % 'serial' | 'parallel'
% N_WORKERS_ECU      = 6;       % 'auto' = one worker per driver, or integer e.g. 8
% KEEP_WORKERS_ECU_OPEN = false;     % true = cmd /k (windows stay open)
% TMP_DIR_ECU        = '';           % '' = auto → <root_folder>\_tmp_ecu_concat
% 
% % Phase 4 parallel options
% PHASE4_MODE        = 'parallel';   % 'serial' | 'parallel'
% N_WORKERS_PAIR     = 6;       % number of workers for Phase 4 pairing
% KEEP_WORKERS_PAIR_OPEN = false;    % true = cmd /k (windows stay open)
% TMP_DIR_PAIR       = '';           % '' = auto → <root_folder>\_tmp_pair_phase
% 
% % Phase 6 parallel options
% PHASE6_MODE            = 'parallel';   % 'serial' | 'parallel'
% N_WORKERS_AUG          = 6;            % number of workers for Phase 6 augmentation
% KEEP_WORKERS_AUG_OPEN  = false;        % true = cmd /k (windows stay open)
% TMP_DIR_AUG            = '';           % '' = auto → <root_folder>\_tmp_augment
% 
% % Phase toggles — turn off phases you don't need to re-run
% RUN_TEAMDATA_CONCAT    = true;
% RUN_ECU_CONCAT         = true;
% RUN_SPLIT              = true;
% RUN_PAIR               = true;
% RUN_MERGE              = true;
% RUN_L180_SORT          = true;
% RUN_L180               = true;
% RUN_XCORR_CHECK        = true;   % add per-sample engine residual channels to combined files
% RUN_AUGMENT_CHANNELS   = true;   % Phase 6: run smp_custom_channels + smp_gated_channels on all COM files
% cfg.rh_patch_file      = fullfile( pwd, 'dataAcquisition\parseEventData\executionScripts\E03_Q09', 'E03_TAU_Constants.xlsx');
% CHANNELS_FILE          = fullfile( pwd, 'dataAcquisition\Motec_MP\channels\channels.xlsx');
% 
% % =========================================================================
% %  EVENT CONFIG  — edit when setting up a new event
% % =========================================================================
% cfg.root_folder  = 'E:\2026\E03_TAU';   % event root — all paths derived from here
% cfg.hol_venue    = 'Sydney Motorsport Park';
% cfg.hol_event    = 'E03_TAU';
% cfg.event_date   = '2026-04-11';   % auto-filled from sessionDate.xlsx (this session's date) — used by Phase 1 (TeamData date filter) and Phase 4b (L180 sort)
% 
% cfg.warmup_beacon_chs  = {'Lap Beacon Number','Lap_Beacon_Number','Lap_Number','Lap Number'};
% cfg.ridealong_car_nums = {};
% 
% % =========================================================================
% %  TUNING DEFAULTS  — rarely changed
% % =========================================================================
% cfg.rpm_ch        = 'Engine_Speed';   % shared across Dash, ECU, and L180
% cfg.ert_ch        = 'ECU_Uptime';     % shared ERT channel name across ECU, L180, TeamData
% cfg.resample_hz   = 100;              % shared: Phase 4 and Phase 5
% cfg.max_offset_s  = 4500;            % shared: Phase 4 and Phase 5
% cfg.rpm_min       = 500;              % shared: Phase 4 and Phase 5
% cfg.quality_min   = 0.01;
% cfg.min_gap_s     = 1000;
% cfg.min_seg_s     = 650;
% cfg.max_overlap_s = -30;              % Phase 2 ECU concat
% cfg.ecu_format    = true;
% cfg.unique_fp     = true;
% cfg.show_report   = true;
% cfg.split_on_reset  = true;
% cfg.rename_output   = true;
% cfg.l180_ecu_format = false;
% 
% % =========================================================================
% %  DERIVED  — built automatically by resolve_cfg, do not edit
% % =========================================================================
% cfg = resolve_cfg(cfg, SESSION, DRIVERS, OVERWRITE);
% 
% % =========================================================================
% %%  PHASE 1 — TEAMDATA CONCAT
% % =========================================================================
% if RUN_TEAMDATA_CONCAT
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 1 — TeamData concat\n');
%     fprintf('%s\n', repmat('=', 1, 60));
% 
%     concat_cfg.event_date          = cfg.event_date;
%     concat_cfg.date_tolerance_days = 0;
%     concat_cfg.flagged_paths       = {};
%     concat_cfg.root_folder         = cfg.root_folder;
%     concat_cfg.td_input_dir        = fullfile(cfg.root_folder, '_TeamData');
%     concat_cfg.td_hol_output_dir   = fullfile(cfg.root_folder, '_HOL','teamData');
%     concat_cfg.hol_venue           = cfg.hol_event;
%     concat_cfg.hol_event           = sprintf('%s%s', cfg.hol_event, cfg.hol_venue);
%     concat_cfg.event_alias_file    = cfg.event_alias_file;
%     concat_cfg.driver_alias_file   = cfg.driver_alias_file;
%     concat_cfg.session_filter      = cfg.session_filter;
%     concat_cfg.unique_fp           = true;
%     concat_cfg.show_report         = true;
%     concat_cfg.overwrite           = false;
%     concat_cfg.driver_filter       = {};
%     concat_cfg.team_filter         = {};
%     PHASE1_MODE = 'serial'
%     if strcmp(PHASE1_MODE, 'serial')
%         smp_concat_teamdata(concat_cfg);
%     else
%         launch_parallel_workers(concat_cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR);
%     end
% 
%     % Sort HOL output into team subfolders
%     COMPILE_DIR      = fullfile(cfg.root_folder, '_HOL','teamData');
%     COMPILE_DIR_Sesh = fullfile(COMPILE_DIR, SESSION);
%     smp_sort_hol_to_teams(COMPILE_DIR_Sesh, cfg.driver_alias_file);
% end
% 
% % =========================================================================
% %%  PHASE 2 — ECU CONCAT
% % =========================================================================
% if RUN_ECU_CONCAT
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 2 — ECU concat\n');
%     fprintf('%s\n', repmat('=', 1, 60));
%     % PHASE2_MODE = 'serial'
%     if strcmp(PHASE2_MODE, 'serial')
%         smp_concat_ecu_per_driver(cfg);
%     else
%         launch_parallel_workers_ecu(cfg, N_WORKERS_ECU, KEEP_WORKERS_ECU_OPEN, TMP_DIR_ECU);
%     end
% end
% 
% % =========================================================================
% %%  PHASE 3 — SPLIT
% % =========================================================================
% if RUN_SPLIT
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 3 — Split (ECU + L180 + TeamData)\n');
%     fprintf('%s\n', repmat('=', 1, 60));
%     smp_split_ecu_by_uptime(cfg);
% end
% 
% % =========================================================================
% %%  PHASE 4 — PAIR ECU + TeamData
% % =========================================================================
% pairs_excel = '';
% if RUN_PAIR
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 4 — Pair sessions  [%s]\n', cfg.session);
%     fprintf('%s\n', repmat('=', 1, 60));
%     cfg.overwrite   = false;
%     % PHASE4_MODE = 'serial';   
%     if strcmp(PHASE4_MODE, 'serial')
%         pairs_excel = smp_pair_sessions(cfg);
%     elseif strcmp(PHASE4_MODE, 'parallel')
%         pairs_excel = launch_parallel_workers_pair(cfg, N_WORKERS_PAIR, KEEP_WORKERS_PAIR_OPEN, TMP_DIR_PAIR);
%     end
% 
%     cfg.pairs_excel = pairs_excel;
% end
% 
% % =========================================================================
% %%  PHASE 4c — ECU/DASH RESIDUAL CHECK
% % =========================================================================
% if RUN_XCORR_CHECK
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 4c — ECU/Dash engine residual  [%s]\n', cfg.session);
%     fprintf('%s\n', repmat('=', 1, 60));
%     add_residual_channels(cfg.com_dir, ...
%         cfg.com_ecu_rpm_ch, cfg.dash_rpm_ch, cfg.resid_ecu_dash_ch, cfg.resample_hz);
% end
% 
% % =========================================================================
% %%  PHASE 5a — SORT L180 TO HOL
% % =========================================================================
% if RUN_L180_SORT
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 4b — Sort L180 to HOL  [%s]\n', cfg.session);
%     fprintf('%s\n', repmat('=', 1, 60));
%     cfg.l180_input_dir      = fullfile(cfg.root_folder, 'L180');
%     cfg.move                = false;
%     cfg.dry_run             = false;
%     cfg.date_tolerance_days = 1;
%     smp_sort_l180_to_hol(cfg);
% end
% 
% % =========================================================================
% %%  PHASE 5 — PAIR L180 ONTO COMBINED
% % =========================================================================
% if RUN_L180
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 5 — Pair L180 onto Combined  [%s]\n', cfg.session);
%     fprintf('%s\n', repmat('=', 1, 60));
%     cfg.overwrite = true;
%     % Replace this when you want to connect dash to L180    
%     cfg.com_rpm_ch         = 'Engine_Speed';
%     smp_pair_l180(cfg);
%     smp_sort_hol_to_teams(cfg.com_dir, cfg.driver_alias_file);
% end
% 
% % =========================================================================
% %%  PHASE 5b — L180 RESIDUAL CHECKS
% % =========================================================================
% if RUN_XCORR_CHECK && RUN_L180
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 5b — L180 engine residuals  [%s]\n', cfg.session);
%     fprintf('%s\n', repmat('=', 1, 60));
%     add_residual_channels(fullfile(cfg.com_dir, '01_T8R'), ...
%         cfg.com_l180_rpm_ch, cfg.dash_rpm_ch,    cfg.resid_l180_dash_ch, cfg.resample_hz);
%     add_residual_channels(fullfile(cfg.com_dir, '01_T8R'), ...
%         cfg.com_l180_rpm_ch, cfg.com_ecu_rpm_ch, cfg.resid_l180_ecu_ch,  cfg.resample_hz);
%     add_residual_channels(fullfile(cfg.com_dir, '03_WTG'), ...
%         cfg.com_l180_rpm_ch, cfg.dash_rpm_ch,    cfg.resid_l180_dash_ch, cfg.resample_hz);
%     add_residual_channels(fullfile(cfg.com_dir, '03_WTG'), ...
%         cfg.com_l180_rpm_ch, cfg.com_ecu_rpm_ch, cfg.resid_l180_ecu_ch,  cfg.resample_hz);
%     add_residual_channels(fullfile(cfg.com_dir, '10_T18'), ...
%         cfg.com_l180_rpm_ch, cfg.dash_rpm_ch,    cfg.resid_l180_dash_ch, cfg.resample_hz);
%     add_residual_channels(fullfile(cfg.com_dir, '10_T18'), ...
%         cfg.com_l180_rpm_ch, cfg.com_ecu_rpm_ch, cfg.resid_l180_ecu_ch,  cfg.resample_hz);
% end
% 
% % =========================================================================
% %%  PHASE 6 — AUGMENT COM FILES WITH CUSTOM + GATED CHANNELS
% % =========================================================================
% % ---- Load driver alias map (needed to resolve Driver + manufacturer) ----
% driver_map = [];
% if isfield(cfg, 'driver_alias_file') && isfile(cfg.driver_alias_file)
%     try
%         driver_map = smp_driver_alias_load(cfg.driver_alias_file);
%         cfg.driver_map = driver_map;
%     catch
%         fprintf('  [WARN] Could not load driver alias — RH patch table will lack Driver/MAN.\n');
%     end
% end
% 
% % ---- Load RH patch table from Excel (replaces hardcoded Car/FrontRH/RearRH/Session) ----
% % cfg.rh_patch_file : path to an Excel file with columns Car | FrontRH | RearRH | Session
% cfg.PatchRH = smp_load_rh_patch(cfg.rh_patch_file, driver_map);
% 
% PHASE6_MODE = 'serial';
% 
% if RUN_AUGMENT_CHANNELS
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('dPHASE 6 — Augment COM files  [%s]\n', cfg.session);
%     fprintf('%s\n', repmat('=', 1, 60));
% 
%     if strcmp(PHASE6_MODE, 'serial')
%         augment_com_files_serial(cfg.com_dir, CHANNELS_FILE, cfg, driver_map);
%     else
%         launch_parallel_workers_augment(cfg.com_dir, CHANNELS_FILE, cfg, ...
%             N_WORKERS_AUG, KEEP_WORKERS_AUG_OPEN, TMP_DIR_AUG, driver_map);
%     end
% end
% 
% fprintf('\n%s\n', repmat('=', 1, 60));
% fprintf('VCS_CombineDatasets complete.\n');
% fprintf('%s\n\n', repmat('=', 1, 60));
% %%
% 
% smp_sort_hol_to_teams(cfg.com_dir, cfg.driver_alias_file);
% 
% %%
% %{
% % Debug helper — visually verify Dash/ECU alignment after xcorr.
% % Update paths and uncomment to use.
% smp_plot_pair_check(...
%     '/Volumes/JHU/E06_DAR/_TeamData/_HOL/Q17/ALL_2026_Q17.ld', ...
%     '/Volumes/JHU/E06_DAR/ECU/HOL/Q17/ALL_2026_Q17.ld', ...
%     'ALL Q17');
% %}
% 
% % =========================================================================
% %  LOCAL FUNCTIONS
% % =========================================================================
% 
% function augment_com_files_serial(com_dir, channels_file, cfg, driver_map)
% % AUGMENT_COM_FILES_SERIAL  Serial Phase 6 — augment every .ld in com_dir.
% %   Recursively scans com_dir, applies driver alias + session filters,
% %   then runs smp_custom_channels + smp_gated_channels on each file.
%     if nargin < 3, cfg = struct(); end
%     if nargin < 4, driver_map = []; end
% 
%     try
%         T_gated_vcs = readtable(channels_file, 'Sheet', 'gatedChannels', 'TextType', 'char');
%     catch
%         T_gated_vcs = table();
%         fprintf('  [WARN] Could not load gatedChannels sheet — skipping gated channels.\n');
%     end
% 
%     % Recursive .ld scan
%     all_paths = recursive_find_ld(com_dir);
%     if isempty(all_paths)
%         fprintf('  [WARN] No .ld files found (recursive) in %s\n', com_dir);
%         return;
%     end
% 
%     % Apply driver + session filter
%     all_paths = filter_aug_files(all_paths, cfg);
%     if isempty(all_paths)
%         fprintf('  [WARN] No files remain after driver/session filter.\n');
%         return;
%     end
% 
%     n_aug_ok   = 0;
%     n_aug_fail = 0;
% 
%     for fi = 1:numel(all_paths)
%         com_path = all_paths{fi};
%         [~, fname] = fileparts(com_path);
%         fprintf('  [%d/%d] %s\n', fi, numel(all_paths), fname);
%         try
%     aug_data      = motec_ld_reader(com_path, {});
%     aug_data.info = motec_ld_info(com_path, false);
% 
%     % ---- Manufacturer fallback via driver alias lookup ----
%             if (~isfield(aug_data.info, 'manufacturer') || isempty(aug_data.info.manufacturer)) && ...
%                isfield(aug_data.info, 'driver') && ~isempty(aug_data.info.driver) && ...
%                ~isempty(driver_map)
%                 tla = resolve_driver_tla(aug_data.info.driver, driver_map);
%                 mfr = local_resolve_manufacturer_by_tla(tla, driver_map);
%                 if ~isempty(mfr)
%                     aug_data.info.manufacturer = mfr;
%                     fprintf('    Manufacturer resolved via alias: %s\n', mfr);
%                 else
%                     fprintf('    [WARN] Manufacturer not found via alias for driver "%s"\n', aug_data.info.driver);
%                 end
%             end
% 
%             aug_data = smp_custom_channels(aug_data, ...
%                 'manufacturer', aug_data.info.manufacturer, ...
%                 'driver',       aug_data.info.driver, ...
%                 'session',      aug_data.info.session, ...
%                 'patchRH',      cfg.PatchRH);
% 
%             [aug_data, ~] = smp_gated_channels(aug_data, T_gated_vcs);
%     % ... rest of the try block (the ld_ch collection loop etc.) stays unchanged ...
%             % Collect channels flagged write_to_ld=true
%             % (set by make_channel and smp_gated_channels — not present on
%             % channels read back from file, so works on first run and re-runs)
%             all_fields = fieldnames(aug_data);
%             ch_list = {};
%             for ci = 1:numel(all_fields)
%                 fn = all_fields{ci};
%                 ch = aug_data.(fn);
%                 if ~isstruct(ch) || ~isfield(ch, 'write_to_ld') || ~ch.write_to_ld
%                     continue;
%                 end
%                 ld_ch.name        = ch.raw_name;
%                 ld_ch.units       = ch.units;
%                 ld_ch.sample_rate = ch.sample_rate;
%                 ld_ch.value       = ch.data(:);
%                 if isfield(ch, 'dec_places')
%                     ld_ch.dec_places = ch.dec_places;
%                 else
%                     ld_ch.dec_places = 2;
%                 end
%                 if isfield(ch, 'overwrite')
%                     ld_ch.overwrite = ch.overwrite;
%                 else
%                     ld_ch.overwrite = false;
%                 end
% 
%                 ld_ch.mul         = 1;
%                 ld_ch.scale       = 1;
%                 vals = ld_ch.value(isfinite(ld_ch.value));
%                 if ~isempty(vals) && min(vals) < 0
%                     ld_ch.offset = floor(min(vals)) - 1;
%                 else
%                     ld_ch.offset = 0;
%                 end
%                 ch_list{end+1} = ld_ch; %#ok<SAGROW>
%             end
% 
%             if isempty(ch_list)
%                 fprintf('    No new channels computed — skipping write.\n');
%                 n_aug_ok = n_aug_ok + 1;
%             else
%                 tmp_path = [com_path '.aug_tmp'];
%                 ld_add_channel(com_path, tmp_path, ch_list);
%                 movefile(tmp_path, com_path, 'f');
%                 fprintf('    Written %d channel(s)\n', numel(ch_list));
%                 n_aug_ok = n_aug_ok + 1;
%             end
%         catch ME
%             fprintf('    [ERROR] %s\n', ME.message);
%             n_aug_fail = n_aug_fail + 1;
%             tmp_path = [com_path '.aug_tmp'];
%             if exist(tmp_path, 'file'), delete(tmp_path); end
%         end
%         clear aug_data ch_list;
%     end
%     fprintf('  Phase 6 complete — OK: %d  Failed: %d\n', n_aug_ok, n_aug_fail);
% end
% 
% 
% function launch_parallel_workers_augment(com_dir, channels_file, cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR, driver_map)
% % LAUNCH_PARALLEL_WORKERS_AUGMENT  Spawn N MATLAB workers for Phase 6 COM augmentation.
% %   Recursively scans com_dir, applies driver/session filter, then splits
% %   files across workers. Each worker calls smp_augment_com_worker.
%     if nargin < 3, cfg = struct(); end
% 
%     % ---- Resolve tmp dir ----
%     p6_tmp = TMP_DIR;
%     if isempty(p6_tmp)
%         p6_tmp = fullfile(cfg.root_folder, '_tmp_augment');
%     end
%     if ~exist(p6_tmp, 'dir'), mkdir(p6_tmp); end
%     delete(fullfile(p6_tmp, 'chunk_*.mat'));
%     delete(fullfile(p6_tmp, 'worker_cfg.mat'));
%     delete(fullfile(p6_tmp, 'done_*.flag'));
% 
%     % ---- Recursive .ld scan + filter ----
%     all_files = recursive_find_ld(com_dir);
%     if isempty(all_files)
%         fprintf('[WARN] launch_parallel_workers_augment: no .ld files found (recursive) in %s\n', com_dir);
%         return;
%     end
%     all_files = filter_aug_files(all_files, cfg);
%     if isempty(all_files)
%         fprintf('[WARN] launch_parallel_workers_augment: no files remain after driver/session filter.\n');
%         return;
%     end
%     n_files = numel(all_files);
% 
%     % ---- Resolve worker count ----
%     if ischar(N_WORKERS) || N_WORKERS == 0
%         n_workers_p6 = n_files;
%     else
%         n_workers_p6 = min(N_WORKERS, n_files);
%     end
% 
%     fprintf('============================================\n');
%     fprintf('  Parallel COM Augment\n');
%     fprintf('  Files   : %d\n', n_files);
%     fprintf('  Workers : %d\n', n_workers_p6);
%     fprintf('  TMP     : %s\n', p6_tmp);
%     fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
%     fprintf('============================================\n\n');
% 
%     % ---- Split files across workers ----
%     chunk_size_p6 = ceil(n_files / n_workers_p6);
%     for w = 1:n_workers_p6
%         i_start = (w-1)*chunk_size_p6 + 1;
%         i_end   = min(w*chunk_size_p6, n_files);
%         if i_start > n_files
%             worker_files = {}; %#ok<NASGU>
%         else
%             worker_files = all_files(i_start:i_end); %#ok<NASGU>
%             fprintf('Worker %d: files %d-%d (%d file(s))\n', w, i_start, i_end, i_end-i_start+1);
%         end
%         save(fullfile(p6_tmp, sprintf('chunk_%d.mat', w)), 'worker_files');
%     end
% 
%     % ---- Save shared worker cfg ----
%     aug_worker_cfg = cfg; %#ok<NASGU>
%     aug_worker_cfg.channels_file = channels_file;
%     aug_worker_cfg.driver_map    = driver_map;   % <-- add this
%     save(fullfile(p6_tmp, 'worker_cfg.mat'), 'aug_worker_cfg');
%     fprintf('\n');
% 
%     % ---- Launch workers ----
%     motec_mp_dir = fileparts(mfilename('fullpath'));
%     matlab_exe   = fullfile(matlabroot, 'bin', 'matlab.exe');
%     win_mode     = 'cmd /c';
%     if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
% 
%     fprintf('Launching %d worker(s)...\n', n_workers_p6);
%     for w = 1:n_workers_p6
%         sys_cmd = sprintf( ...
%             'start "SMP Augment Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); smp_augment_com_worker(%d, ''%s'')""', ...
%             w, win_mode, matlab_exe, ...
%             strrep(motec_mp_dir, '\', '\\'), ...
%             w, strrep(p6_tmp, '\', '\\'));
%         system(sys_cmd);
%         fprintf('  Worker %d launched\n', w);
%         pause(1.5);
%     end
%     fprintf('\nWorkers running — augmenting COM files concurrently.\n');
%     fprintf('done_N.flag written to TMP after each worker completes.\n\n');
% end
% 
% 
% function ld_paths = recursive_find_ld(root_dir)
% % RECURSIVE_FIND_LD  Recursively find all .ld files under root_dir.
%     ld_paths = {};
%     if ~isfolder(root_dir), return; end
%     stack = {root_dir};
%     while ~isempty(stack)
%         cur = stack{end}; stack(end) = [];
%         d = dir(fullfile(cur, '*.ld'));
%         for k = 1:numel(d)
%             if ~startsWith(d(k).name, '._')
%                 ld_paths{end+1} = fullfile(cur, d(k).name); %#ok<AGROW>
%             end
%         end
%         sub = dir(cur);
%         for k = 1:numel(sub)
%             if sub(k).isdir && sub(k).name(1) ~= '.'
%                 stack{end+1} = fullfile(cur, sub(k).name); %#ok<AGROW>
%             end
%         end
%     end
% end
% 
% 
% function paths = filter_aug_files(paths, cfg)
% % FILTER_AUG_FILES  Apply driver alias + session filter to a list of .ld paths.
% %
% %   Session filter: if cfg.session_filter is set, reads each file header and
% %     keeps only files whose event/session string matches.
% %   Driver filter:  if cfg.fix_filter is non-empty, loads the driver alias map
% %     and keeps only files whose driver resolves to a listed TLA/car number.
% 
%     if isempty(paths), return; end
% 
%     % ---- Build driver alias map (once) ----
%     driver_map = [];
%     has_driver_filter = isfield(cfg, 'fix_filter') && ~isempty(cfg.fix_filter);
%     if has_driver_filter && isfield(cfg, 'driver_alias_file') && isfile(cfg.driver_alias_file)
%         try
%             driver_map = smp_driver_alias_load(cfg.driver_alias_file);
%         catch
%             fprintf('  [WARN] filter_aug_files: could not load driver alias — skipping driver filter.\n');
%             has_driver_filter = false;
%         end
%     end
% 
%     % ---- Session strings to accept ----
%     has_session_filter = isfield(cfg, 'session_filter') && ~isempty(cfg.session_filter);
%     accepted_sessions  = {};
%     if has_session_filter
%         accepted_sessions = lower(cfg.session_filter);
%     end
% 
%     if ~has_driver_filter && ~has_session_filter
%         return;   % nothing to filter
%     end
% 
%     keep = true(size(paths));
%     for i = 1:numel(paths)
%         try
%             info = motec_ld_info(paths{i}, false);
%         catch
%             fprintf('  [WARN] filter_aug_files: could not read header of %s — keeping.\n', paths{i});
%             continue;
%         end
% 
%         % ---- Session check ----
%         if has_session_filter
%             file_session = '';
%             if isfield(info, 'event'),   file_session = lower(strtrim(info.event));   end
%             if isfield(info, 'session'), file_session = lower(strtrim(info.session)); end
%             if ~any(contains(file_session, accepted_sessions))
%                 keep(i) = false;
%                 continue;
%             end
%         end
% 
%         % ---- Driver check ----
%         if has_driver_filter
%             raw_drv = '';
%             if isfield(info, 'driver'), raw_drv = strtrim(info.driver); end
%             tla = resolve_driver_tla(raw_drv, driver_map);
%             if isempty(tla), tla = raw_drv; end
%             % cfg.fix_filter may contain TLAs or car numbers
%             if ~any(strcmpi(tla, cfg.fix_filter)) && ~any(strcmpi(raw_drv, cfg.fix_filter))
%                 keep(i) = false;
%             end
%         end
%     end
% 
%     n_removed = sum(~keep);
%     if n_removed > 0
%         fprintf('  filter_aug_files: removed %d file(s) that did not match driver/session filter.\n', n_removed);
%     end
%     paths = paths(keep);
% end
% 
% 
% function tla = resolve_driver_tla(raw_driver, driver_map)
% % Resolve a raw driver string to its canonical TLA via the alias map.
% % Returns '' if no match found.
%     tla = '';
%     if isempty(driver_map) || isempty(raw_driver), return; end
%     raw_lower = lower(raw_driver);
%     keys = fieldnames(driver_map);
%     for ki = 1:numel(keys)
%         entry = driver_map.(keys{ki});
%         if any(strcmp(raw_lower, entry.aliases))
%             if ~isempty(entry.tla)
%                 tla = entry.tla;
%             elseif ~isempty(entry.canonical)
%                 tla = entry.canonical;
%             end
%             return;
%         end
%     end
% end
% 
% 
% function cfg = resolve_cfg(cfg, SESSION, DRIVERS, OVERWRITE)
% % RESOLVE_CFG  Derive all paths, channel aliases, and filter fields from the
% %   user-supplied event config and AT-TRACK controls. Do not edit.
% 
% ALIAS_DIR = fullfile(pwd, 'dataAcquisition\Motec_MP\alias');
% 
% % ---- Alias files ----
% cfg.event_alias_file  = fullfile(pwd,'\dataAcquisition\parseEventData\executionScripts', cfg.hol_event, 'eventAlias.xlsx');
% cfg.driver_alias_file = fullfile(ALIAS_DIR, 'driverAlias.xlsx');
% cfg.session_meta_file = fullfile(fileparts(mfilename('fullpath')), ...
%                             'channels', 'session_metadata.xlsx');
% 
% % ---- Directory paths ----
% cfg.td_input_dir      = fullfile(cfg.root_folder, '_TeamData');
% cfg.td_hol_output_dir = fullfile(cfg.root_folder, '_HOL', 'teamData');
% cfg.ecu_input_dir     = fullfile(cfg.root_folder, 'ECU', SESSION);
% cfg.ecu_hol_dir       = fullfile(cfg.root_folder,'_HOL', 'ECU');
% cfg.ecu_concat_dir    = cfg.ecu_hol_dir;   % Phase 2 writes; Phase 3 reads same dir
% cfg.l180_input_dir    = fullfile(cfg.root_folder, 'L180');
% cfg.l180_hol_dir      = fullfile(cfg.root_folder, 'L180', 'HOL');
% cfg.com_dir           = fullfile(cfg.root_folder, 'COM', SESSION);
% 
% % ---- Phase-specific field aliases ----
% cfg.merge_resample_hz  = cfg.resample_hz;
% cfg.merge_max_offset_s = cfg.max_offset_s;
% cfg.merge_rpm_min      = cfg.rpm_min;
% cfg.dash_rpm_ch        = cfg.rpm_ch;
% cfg.ecu_rpm_ch         = cfg.rpm_ch;
% cfg.l180_rpm_ch        = cfg.rpm_ch;
% cfg.ecu_ert_names      = {cfg.ert_ch};
% cfg.l180_ert_names     = {cfg.ert_ch};
% cfg.td_ert_names       = {cfg.ert_ch};
% cfg.session_labels     = {SESSION};
% cfg.session_aliases    = {};
% cfg.com_rpm_ch         = 'ecu_Engine_Speed';
% cfg.com_ecu_rpm_ch     = 'ecu_Engine_Speed';
% cfg.com_l180_rpm_ch    = 'l180_Engine_Speed';
% 
% % ---- xcorr + residual channel names ----
% cfg.xcorr_ecu_dash_ch  = 'xcorr_ecu_dash';
% cfg.xcorr_l180_dash_ch = 'xcorr_l180_dash';
% cfg.xcorr_l180_ecu_ch  = 'xcorr_l180_ecu';
% cfg.resid_ecu_dash_ch  = 'resid_ecu_dash';
% cfg.resid_l180_dash_ch = 'resid_l180_dash';
% cfg.resid_l180_ecu_ch  = 'resid_l180_ecu';
% 
% % ---- Session / overwrite ----
% cfg.overwrite        = OVERWRITE;
% cfg.session          = SESSION;
% cfg.session_filter   = {SESSION};
% 
% % ---- Resolve DRIVERS → per-phase filters ----
% cfg.fix_filter       = DRIVERS;
% cfg.driver_filter    = {};
% cfg.team_filter      = {};
% cfg.split_car_filter = {};
% cfg.ecu_tla_filter   = {};
% 
% if ~isempty(DRIVERS)
%     fix_driver_map = [];
%     if isfile(cfg.driver_alias_file)
%         try
%             fix_driver_map = smp_driver_alias_load(cfg.driver_alias_file);
%         catch, end
%     end
%     fix_canonicals = {}; fix_tlas = {}; fix_car_nums = {};
%     if ~isempty(fix_driver_map)
%         keys = fieldnames(fix_driver_map);
%         for ki = 1 : numel(keys)
%             e = fix_driver_map.(keys{ki});
%             match = ismember(lower(DRIVERS), lower(e.tla)) | ...
%                     ismember(lower(DRIVERS), lower(e.num));
%             if any(match)
%                 fix_canonicals{end+1} = e.canonical;
%                 fix_tlas{end+1}       = e.tla;
%                 fix_car_nums{end+1}   = e.num;
%             end
%         end
%     end
%     if ~isempty(fix_canonicals)
%         cfg.driver_filter    = fix_canonicals;
%         cfg.ecu_tla_filter   = fix_tlas;
%         cfg.split_car_filter = fix_car_nums;
%         fprintf('[resolve_cfg] Restricted to: TLAs=%s  Cars=%s\n', ...
%             strjoin(fix_tlas,','), strjoin(fix_car_nums,','));
%     else
%         fprintf('[resolve_cfg] WARNING: no alias matches found for: %s\n', ...
%             strjoin(DRIVERS,','));
%     end
% end
% end
% 
% 
% function launch_parallel_workers(concat_cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR)
% % LAUNCH_PARALLEL_WORKERS  Spawn one MATLAB worker per driver group (or N_WORKERS).
% %   Each worker loads its assigned chunk of driver groups and calls
% %   smp_concat_teamdata_worker. Done flags are written to TMP_DIR on completion.
% 
% % ---- Resolve tmp dir ----
% p1_tmp = TMP_DIR;
% if isempty(p1_tmp)
%     p1_tmp = fullfile(concat_cfg.root_folder, '_tmp_parallel');
% end
% if ~exist(p1_tmp, 'dir'), mkdir(p1_tmp); end
% delete(fullfile(p1_tmp, 'chunk_*.mat'));
% delete(fullfile(p1_tmp, 'worker_cfg.mat'));
% delete(fullfile(p1_tmp, 'done_*.flag'));
% 
% % ---- Pre-scan to enumerate driver groups (no data loaded) ----
% alias_p1      = smp_alias_load(concat_cfg.event_alias_file);
% driver_map_p1 = smp_driver_alias_load(concat_cfg.driver_alias_file);
% scan_p1       = smp_scan_folders(concat_cfg.td_input_dir);
% if ~isempty(concat_cfg.team_filter)
%     keep_p1 = ismember({scan_p1.acronym}, concat_cfg.team_filter);
%     scan_p1 = scan_p1(keep_p1);
% end
% to_load_p1 = struct('path', {}, 'team_index', {}, 'team_acronym', {});
% n_tl_p1 = 0;
% for t_p1 = 1 : numel(scan_p1)
%     for f_p1 = 1 : numel(scan_p1(t_p1).files)
%         n_tl_p1 = n_tl_p1 + 1;
%         to_load_p1(n_tl_p1).path         = scan_p1(t_p1).files{f_p1};
%         to_load_p1(n_tl_p1).team_index   = scan_p1(t_p1).index;
%         to_load_p1(n_tl_p1).team_acronym = scan_p1(t_p1).acronym;
%     end
% end
% groups_p1 = smp_append_stints(to_load_p1, driver_map_p1, alias_p1, concat_cfg.session_filter);
% if ~isempty(concat_cfg.driver_filter)
%     keep_p1   = ismember(lower({groups_p1.driver}), lower(concat_cfg.driver_filter));
%     groups_p1 = groups_p1(keep_p1);
% end
% n_groups_p1 = numel(groups_p1);
% 
% % ---- Resolve worker count ----
% if ischar(N_WORKERS) || N_WORKERS == 0
%     n_workers_p1 = n_groups_p1;
% else
%     n_workers_p1 = min(N_WORKERS, n_groups_p1);
% end
% 
% fprintf('============================================\n');
% fprintf('  Parallel TeamData Concat\n');
% fprintf('  Groups  : %d\n', n_groups_p1);
% fprintf('  Workers : %d\n', n_workers_p1);
% fprintf('  TMP     : %s\n', p1_tmp);
% fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
% fprintf('============================================\n\n');
% 
% % ---- Split groups across workers ----
% chunk_size_p1 = ceil(n_groups_p1 / n_workers_p1);
% for w = 1 : n_workers_p1
%     i_start = (w-1)*chunk_size_p1 + 1;
%     i_end   = min(w*chunk_size_p1, n_groups_p1);
%     if i_start > n_groups_p1
%         worker_groups = groups_p1([]); %#ok<NASGU>
%         fprintf('Worker %d: no groups assigned\n', w);
%     else
%         worker_groups = groups_p1(i_start:i_end); %#ok<NASGU>
%         fprintf('Worker %d: groups %d-%d  (%d group(s))\n', ...
%             w, i_start, i_end, i_end - i_start + 1);
%     end
%     save(fullfile(p1_tmp, sprintf('chunk_%d.mat', w)), 'worker_groups');
% end
% 
% % ---- Save shared worker cfg (driver_filter cleared — worker sets it) ----
% worker_cfg               = concat_cfg; %#ok<NASGU>
% worker_cfg.driver_filter = {};
% save(fullfile(p1_tmp, 'worker_cfg.mat'), 'worker_cfg');
% fprintf('\n');
% 
% % ---- Launch workers ----
% motec_mp_dir = fileparts(mfilename('fullpath'));
% matlab_exe   = fullfile(matlabroot, 'bin', 'matlab.exe');
% win_mode     = 'cmd /c';
% if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
% fprintf('Launching %d worker(s)...\n', n_workers_p1);
% for w = 1 : n_workers_p1
%     sys_cmd = sprintf( ...
%         'start "SMP Concat Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); smp_concat_teamdata_worker(%d, ''%s'')"', ...
%         w, win_mode, matlab_exe, ...
%         strrep(motec_mp_dir, '\', '\\'), ...
%         w, strrep(p1_tmp, '\', '\\'));
%     system(sys_cmd);
%     fprintf('  Worker %d launched\n', w);
%     pause(1.5);
% end
% fprintf('\nWorkers running — report popups will appear per driver.\n');
% fprintf('done_N.flag written to TMP after each popup is dismissed.\n\n');
% end
% 
% 
% function launch_parallel_workers_ecu(cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR)
% % LAUNCH_PARALLEL_WORKERS_ECU  Spawn N MATLAB workers for Phase 2 ECU concat.
% %   Each worker loads its assigned driver group chunk and calls
% %   smp_concat_ecu_per_driver. Done flags are written to TMP_DIR on completion.
% 
% % ---- Resolve tmp dir ----
% p2_tmp = TMP_DIR;
% if isempty(p2_tmp)
%     p2_tmp = fullfile(cfg.root_folder, '_tmp_ecu_concat');
% end
% if ~exist(p2_tmp, 'dir')
%     mkdir(p2_tmp)
% end
% delete(fullfile(p2_tmp, 'chunk_*.mat'));
% delete(fullfile(p2_tmp, 'worker_cfg.mat'));
% delete(fullfile(p2_tmp, 'done_*.flag'));
% 
% % ---- Pre-scan to enumerate ECU driver groups (no data loaded) ----
% INPUT_DIR    = cfg.ecu_input_dir;
% ECU_FORMAT   = cfg.ecu_format; %#ok<NASGU>
% driver_map   = [];
% if isfield(cfg, 'driver_alias_file') && isfile(cfg.driver_alias_file)
%     try
%         driver_map = smp_driver_alias_load(cfg.driver_alias_file);
%     catch, end
% end
% 
% % Inline recursive .ld scan (skips HOL subfolder — mirrors recursive_find_ld)
% ld_files = {};
% if isfolder(INPUT_DIR)
%     stack = {INPUT_DIR};
%     while ~isempty(stack)
%         cur = stack{end}; stack(end) = [];
%         d = dir(fullfile(cur, '*.ld'));
%         for k = 1 : numel(d)
%             if ~startsWith(d(k).name, '._')
%                 ld_files{end+1} = fullfile(cur, d(k).name); %#ok<AGROW>
%             end
%         end
%         sub = dir(cur);
%         for k = 1 : numel(sub)
%             if sub(k).isdir && sub(k).name(1) ~= '.' && ~strcmpi(sub(k).name, 'HOL')
%                 stack{end+1} = fullfile(cur, sub(k).name); %#ok<AGROW>
%             end
%         end
%     end
% end
% 
% if isempty(ld_files)
%     fprintf('[WARN] launch_parallel_workers_ecu: no .ld files in %s\n', INPUT_DIR);
%     return;
% end
% 
% group_keys = {};
% for fi = 1 : numel(ld_files)
%     fp = ld_files{fi};
%     [~, fn, ~] = fileparts(fp);
%     prefix = regexp(fn, '^([^_]+)', 'match', 'once');
%     if strcmpi(prefix, 'S3'), continue; end
% 
%     group_key = fn;
%     try
%         hdr     = motec_ld_info(fp, false);
%         raw_drv = strtrim(hdr.driver);
%         % Inline resolve_driver_info: match raw_drv against alias entries
%         drv_key  = raw_drv;
%         if ~isempty(driver_map) && ~isempty(raw_drv)
%             raw_lower = lower(raw_drv);
%             keys_dm   = fieldnames(driver_map);
%             for ki = 1 : numel(keys_dm)
%                 entry = driver_map.(keys_dm{ki});
%                 if any(strcmp(raw_lower, entry.aliases))
%                     if ~isempty(entry.tla),       drv_key = entry.tla;
%                     elseif ~isempty(entry.canonical), drv_key = entry.canonical;
%                     end
%                     break;
%                 end
%             end
%         end
%         if ~isempty(prefix)
%             group_key = [prefix '_' drv_key];
%         else
%             group_key = drv_key;
%         end
%     catch, end
%     group_keys{end+1} = group_key; %#ok<AGROW>
% end
% 
% all_drivers = unique(group_keys);
% 
% % Apply driver filter if set
% if isfield(cfg, 'ecu_tla_filter') && ~isempty(cfg.ecu_tla_filter)
%     keep_drv = false(size(all_drivers));
%     for i = 1 : numel(all_drivers)
%         tla_part = regexprep(all_drivers{i}, '^[^_]+_', '');
%         keep_drv(i) = ismember(lower(tla_part), lower(cfg.ecu_tla_filter)) || ...
%                       ismember(lower(all_drivers{i}), lower(cfg.ecu_tla_filter));
%     end
%     all_drivers = all_drivers(keep_drv);
% end
% 
% n_drivers_p2 = numel(all_drivers);
% 
% % ---- Resolve worker count ----
% if ischar(N_WORKERS) || N_WORKERS == 0
%     n_workers_p2 = n_drivers_p2;
% else
%     n_workers_p2 = min(N_WORKERS, n_drivers_p2);
% end
% 
% fprintf('============================================\n');
% fprintf('  Parallel ECU Concat\n');
% fprintf('  Drivers : %d\n', n_drivers_p2);
% fprintf('  Workers : %d\n', n_workers_p2);
% fprintf('  TMP     : %s\n', p2_tmp);
% fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
% fprintf('============================================\n\n');
% 
% % ---- Split drivers across workers ----
% chunk_size_p2 = ceil(n_drivers_p2 / n_workers_p2);
% for w = 1 : n_workers_p2
%     i_start = (w-1)*chunk_size_p2 + 1;
%     i_end   = min(w*chunk_size_p2, n_drivers_p2);
%     if i_start > n_drivers_p2
%         worker_drivers = all_drivers([]); %#ok<NASGU>
%         fprintf('Worker %d: no drivers assigned\n', w);
%     else
%         worker_drivers = all_drivers(i_start:i_end); %#ok<NASGU>
%         fprintf('Worker %d: drivers %d-%d  (%d driver(s))\n', ...
%             w, i_start, i_end, i_end - i_start + 1);
%     end
%     save(fullfile(p2_tmp, sprintf('chunk_%d.mat', w)), 'worker_drivers');
% end
% 
% % ---- Save shared worker cfg ----
% worker_cfg = cfg; %#ok<NASGU>
% save(fullfile(p2_tmp, 'worker_cfg.mat'), 'worker_cfg');
% fprintf('\n');
% 
% % ---- Launch workers ----
% motec_mp_dir = fileparts(mfilename('fullpath'));
% matlab_exe   = fullfile(matlabroot, 'bin', 'matlab.exe');
% win_mode     = 'cmd /c';
% if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
% fprintf('Launching %d worker(s)...\n', n_workers_p2);
% for w = 1 : n_workers_p2
%     sys_cmd = sprintf( ...
%         'start "SMP ECU Concat Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); smp_concat_ecu_per_driver_worker(%d, ''%s'')"', ...
%         w, win_mode, matlab_exe, ...
%         strrep(motec_mp_dir, '\', '\\'), ...
%         w, strrep(p2_tmp, '\', '\\'));
%     system(sys_cmd);
%     fprintf('  Worker %d launched\n', w);
%     pause(1.5);
% end
% fprintf('\nWorkers running — ECU concat files written to ecu_concat_dir concurrently.\n');
% fprintf('done_N.flag written to TMP after each worker completes.\n\n');
% end
% 
% 
% function add_residual_channels(com_dir, ch_a_name, ch_b_name, out_ch_name, resample_hz)
% % ADD_RESIDUAL_CHANNELS  Compute per-sample residual (A − B) for all .ld files
% %   in com_dir and append the result as a new channel back into each file.
% %
% %   Both channels are resampled to a common grid at resample_hz before
% %   subtraction, so the output is a time-series aligned to channel A's
% %   time base.
% %
% %   Arguments:
% %     com_dir       - folder containing combined .ld files
% %     ch_a_name     - minuend channel name   (e.g. 'ecu_Engine_Speed')
% %     ch_b_name     - subtrahend channel name (e.g. 'Engine_Speed')
% %     out_ch_name   - name for the residual channel written to file
% %     resample_hz   - common sample rate for interpolation
% 
% files = dir(fullfile(com_dir, '*.ld'));
% if isempty(files)
%     fprintf('  [residual] No .ld files found in: %s\n', com_dir);
%     return;
% end
% 
% dt = 1 / resample_hz;
% 
% for fi = 1 : numel(files)
%     fpath = fullfile(files(fi).folder, files(fi).name);
%     fprintf('  [residual] %s  (%s − %s)\n', files(fi).name, ch_a_name, ch_b_name);
% 
%     % ---- Load both channels ----
%     try
%         da = motec_ld_reader(fpath, {ch_a_name}, false);
%         db = motec_ld_reader(fpath, {ch_b_name}, false);
%     catch ME
%         fprintf('    WARNING: could not load channels — %s\n', ME.message);
%         continue;
%     end
%     fn_a = fieldnames(da); fn_b = fieldnames(db);
%     if isempty(fn_a) || isempty(fn_b)
%         fprintf('    WARNING: one or both channels missing, skipping.\n');
%         continue;
%     end
%     ch_a = da.(fn_a{1}); ch_b = db.(fn_b{1});
% 
%     % ---- Resample to common time grid ----
%     t_start = max(ch_a.time(1),   ch_b.time(1));
%     t_end   = min(ch_a.time(end), ch_b.time(end));
%     if t_end <= t_start
%         fprintf('    WARNING: no overlapping time range, skipping.\n');
%         continue;
%     end
%     t_grid = (t_start : dt : t_end)';
%     v_a = interp1(ch_a.time(:), double(ch_a.data(:)), t_grid, 'linear', NaN);
%     v_b = interp1(ch_b.time(:), double(ch_b.data(:)), t_grid, 'linear', NaN);
% 
%     % ---- Compute residual ----
%     resid = single(v_a - v_b);
% 
%     % ---- Build channel struct for ld_add_channel ----
%     resid_ch.name        = char(out_ch_name);
%     resid_ch.value       = resid;
%     resid_ch.sample_rate = resample_hz;
%     if ischar(ch_a.units) || isstring(ch_a.units)
%         resid_ch.units = char(ch_a.units);
%     else
%         resid_ch.units = '';
%     end
%     tmp_file = [fpath '.residtmp'];
%     try
%         ld_add_channel(fpath, tmp_file, resid_ch);
%         movefile(tmp_file, fpath, 'f');
%         % Delete the original file's stale .ldx index so i2 Pro rebuilds it
%         ldx_path = [fpath(1:end-2) 'ldx'];
%         if exist(ldx_path, 'file'), delete(ldx_path); end
%         fprintf('    Written: %s  (%.0f Hz, %.1f s)\n', ...
%             out_ch_name, resample_hz, t_end - t_start);
%     catch ME
%         if exist(tmp_file, 'file'), delete(tmp_file); end
%         fprintf('    WARNING: write failed — %s\n', ME.message);
%     end
% end
% end
% 
% 
% function pairs_excel = launch_parallel_workers_pair(cfg, N_WORKERS, KEEP_WORKERS_OPEN, TMP_DIR)
% % LAUNCH_PARALLEL_WORKERS_PAIR  Spawn N MATLAB workers for Phase 4 pairing.
% %   Each worker loads assigned candidate pairs and calls smp_pair_sessions_worker.
% %   Results are aggregated from audit_N.mat files. Done flags written to TMP_DIR on completion.
% 
% % ---- Resolve tmp dir ----
% p4_tmp = TMP_DIR;
% if isempty(p4_tmp)
%     p4_tmp = fullfile(cfg.root_folder, '_tmp_pair_phase');
% end
% if ~exist(p4_tmp, 'dir'), mkdir(p4_tmp); end
% delete(fullfile(p4_tmp, 'chunk_*.mat'));
% delete(fullfile(p4_tmp, 'worker_cfg.mat'));
% delete(fullfile(p4_tmp, 'audit_*.mat'));
% delete(fullfile(p4_tmp, 'done_*.flag'));
% 
% % ---- Pre-scan to enumerate candidate pairs ----
% SESSION         = cfg.session;
% TD_HOL_DIR      = cfg.td_hol_output_dir;
% ECU_HOL_DIR     = cfg.ecu_hol_dir;
% L180_HOL_DIR    = cfg.l180_hol_dir;
% 
% dash_dir = fullfile(TD_HOL_DIR, SESSION);
% ecu_dir  = fullfile(ECU_HOL_DIR, SESSION);
% l180_dir = fullfile(L180_HOL_DIR, SESSION);
% 
% dash_map = build_stem_map(dash_dir);
% ecu_map  = build_stem_map(ecu_dir);
% l180_map = build_stem_map(l180_dir);
% 
% % ---- Generate candidates table (same logic as smp_pair_sessions Phase 1-2) ----
% ecu_stems  = fieldnames(ecu_map);
% dash_stems = fieldnames(dash_map);
% 
% candidates  = {};
% review_rows = {};
% 
% for i = 1 : numel(ecu_stems)
%     stem = ecu_stems{i};
%     if isfield(dash_map, stem)
%         candidates(end+1, :) = {dash_map.(stem), ecu_map.(stem), stem}; %#ok<AGROW>
%     else
%         review_rows(end+1, :) = {ecu_map.(stem), 'ECU', 'ECU_NO_DASH', ''}; %#ok<AGROW>
%     end
% end
% 
% matched_dash_stems = {};
% if size(candidates, 1) > 0
%     matched_dash_stems = candidates(:, 3);
% end
% for i = 1 : numel(dash_stems)
%     stem = dash_stems{i};
%     if ~any(strcmp(matched_dash_stems, stem))
%         review_rows(end+1, :) = {dash_map.(stem), 'Dash', 'DASH_NO_ECU', ''}; %#ok<AGROW>
%     end
% end
% 
% % TLA filter
% if isfield(cfg, 'ecu_tla_filter') && ~isempty(cfg.ecu_tla_filter)
%     keep = false(size(candidates, 1), 1);
%     for i = 1 : size(candidates, 1)
%         [stem_tla, ~] = extract_tla_session(candidates{i, 3});
%         keep(i) = any(strcmpi(stem_tla, cfg.ecu_tla_filter));
%     end
%     candidates = candidates(keep, :);
% end
% 
% % ---- Overwrite filter — drop candidates whose COM file already exists ----
% OVERWRITE_P4 = isfield(cfg, 'overwrite') && cfg.overwrite;
% if ~OVERWRITE_P4 && ~isempty(candidates)
%     COM_DIR_P4 = cfg.com_dir;
%     keep_cand = true(size(candidates, 1), 1);
%     for i = 1 : size(candidates, 1)
%         [~, dash_base, dash_ext] = fileparts(candidates{i, 1});
%         com_check = fullfile(COM_DIR_P4, [dash_base '_combined' dash_ext]);
%         if exist(com_check, 'file')
%             keep_cand(i) = false;
%         end
%     end
%     n_skipped_p4 = sum(~keep_cand);
%     candidates   = candidates(keep_cand, :);
%     if n_skipped_p4 > 0
%         fprintf('  Overwrite=false: skipping %d pair(s) with existing COM files\n', n_skipped_p4);
%     end
% end
% 
% n_candidates = size(candidates, 1);
% 
% % ---- Extract unique TLAs — split unit (one TLA goes to exactly one worker) ----
% all_tlas_p4 = {};
% for i = 1 : n_candidates
%     [stem_tla, ~] = extract_tla_session(candidates{i, 3});
%     all_tlas_p4{end+1} = stem_tla; %#ok<AGROW>
% end
% all_tlas_p4 = unique(all_tlas_p4);
% n_tlas_p4   = numel(all_tlas_p4);
% 
% % ---- Resolve worker count (capped by unique TLA count) ----
% if ischar(N_WORKERS) || N_WORKERS == 0
%     n_workers_p4 = n_tlas_p4;
% else
%     n_workers_p4 = min(N_WORKERS, n_tlas_p4);
% end
% 
% fprintf('============================================\n');
% fprintf('  Parallel Phase 4: Dash/ECU Pairing\n');
% fprintf('  Candidates : %d\n', n_candidates);
% fprintf('  TLAs       : %d\n', n_tlas_p4);
% fprintf('  Workers    : %d\n', n_workers_p4);
% fprintf('  TMP        : %s\n', p4_tmp);
% fprintf('  Time       : %s\n', datestr(now, 'HH:MM:SS'));
% fprintf('============================================\n\n');
% 
% % ---- Split TLAs across workers (each TLA goes to exactly one worker) ----
% chunk_size_p4 = ceil(n_tlas_p4 / n_workers_p4);
% for w = 1 : n_workers_p4
%     i_start = (w-1)*chunk_size_p4 + 1;
%     i_end   = min(w*chunk_size_p4, n_tlas_p4);
%     if i_start > n_tlas_p4
%         worker_tlas = all_tlas_p4([]); %#ok<NASGU>
%         fprintf('Worker %d: no TLAs assigned\n', w);
%     else
%         worker_tlas = all_tlas_p4(i_start:i_end); %#ok<NASGU>
%         fprintf('Worker %d: TLAs %d-%d  (%s)\n', ...
%             w, i_start, i_end, strjoin(all_tlas_p4(i_start:i_end), ', '));
%     end
%     save(fullfile(p4_tmp, sprintf('chunk_%d.mat', w)), 'worker_tlas');
% end
% 
% % ---- Save shared worker cfg ----
% worker_cfg = cfg; %#ok<NASGU>
% save(fullfile(p4_tmp, 'worker_cfg.mat'), 'worker_cfg');
% fprintf('\n');
% 
% % ---- Launch workers ----
% motec_mp_dir = fileparts(mfilename('fullpath'));
% matlab_exe   = fullfile(matlabroot, 'bin', 'matlab.exe');
% win_mode     = 'cmd /c';
% if KEEP_WORKERS_OPEN, win_mode = 'cmd /k'; end
% fprintf('Launching %d worker(s)...\n', n_workers_p4);
% for w = 1 : n_workers_p4
%     sys_cmd = sprintf( ...
%         'start "SMP Pair Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); smp_pair_sessions_worker(%d, ''%s'')"', ...
%         w, win_mode, matlab_exe, ...
%         strrep(motec_mp_dir, '\', '\\'), ...
%         w, strrep(p4_tmp, '\', '\\'));
%     system(sys_cmd);
%     fprintf('  Worker %d launched\n', w);
%     pause(1.5);
% end
% fprintf('\nWorkers running — COM files written to COM_DIR concurrently.\n');
% fprintf('done_N.flag written to TMP after each worker completes.\n\n');
% pairs_excel = '';
% 
% end
% 
% 
% function smp_plot_pair_check(dash_file, ecu_file, session_label)
% % SMP_PLOT_PAIR_CHECK  Visually verify Dash/ECU alignment after xcorr.
% % Overlays RPM from both files on a shared time axis.
% %
% % Usage:
% %   smp_plot_pair_check(dash_file, ecu_file)
% %   smp_plot_pair_check(dash_file, ecu_file, 'ALL_Q17')
% 
% if nargin < 3
%     [~, stem] = fileparts(dash_file);
%     session_label = stem;
% end
% 
% % ---- Load Dash RPM ----
% fprintf('Loading Dash...\n');
% da = motec_ld_reader(dash_file, {'Engine_Speed'}, false);
% fn = fieldnames(da);
% if isempty(fn)
%     error('No usable RPM channel found in Dash file.');
% end
% ch_a = da.(fn{1});
% t_a  = ch_a.time(:);
% v_a  = double(ch_a.data(:));
% fprintf('  Dash: %s  |  %.0f Hz  |  %.1f s  |  peak %.0f RPM\n', ...
%     fn{1}, ch_a.sample_rate, t_a(end), max(v_a));
% 
% % ---- Load ECU RPM ----
% fprintf('Loading ECU...\n');
% ecu_candidates = {'Engine.Speed', 'Engine_Speed'};
% db = [];
% for ci = 1:numel(ecu_candidates)
%     try
%         tmp = motec_ld_reader(ecu_file, {ecu_candidates{ci}}, true);
%         fn2 = fieldnames(tmp);
%         if ~isempty(fn2) && max(tmp.(fn2{1}).data) > 2500
%             db = tmp; break;
%         end
%     catch, end
% end
% if isempty(db)
%     error('No usable RPM channel found in ECU file.');
% end
% fn2  = fieldnames(db);
% ch_b = db.(fn2{1});
% t_b  = ch_b.time(:);
% v_b  = double(ch_b.data(:));
% fprintf('  ECU:  %s  |  %.0f Hz  |  %.1f s  |  peak %.0f RPM\n', ...
%     fn2{1}, ch_b.sample_rate, t_b(end), max(v_b));
% 
% % ---- Run xcorr to get offset ----
% fprintf('Running xcorr...\n');
% RESAMPLE_HZ = 50;
% RPM_MIN     = 500;
% dt          = 1 / RESAMPLE_HZ;
% 
% t_a_g = (t_a(1):dt:t_a(end))';
% t_b_g = (t_b(1):dt:t_b(end))';
% v_a_g = interp1(t_a, v_a, t_a_g, 'linear', NaN);
% v_b_g = interp1(t_b, v_b, t_b_g, 'linear', NaN);
% 
% mask_a = v_a_g >= RPM_MIN & ~isnan(v_a_g);
% mask_b = v_b_g >= RPM_MIN & ~isnan(v_b_g);
% 
% xc_a = v_a_g; xc_b = v_b_g;
% xc_a(~mask_a) = 0; xc_b(~mask_b) = 0;
% xc_a(mask_a)  = xc_a(mask_a) - mean(xc_a(mask_a));
% xc_b(mask_b)  = xc_b(mask_b) - mean(xc_b(mask_b));
% 
% [xc_vals, lags] = xcorr(xc_a, xc_b);
% [~, peak_idx]   = max(xc_vals);
% lag_samples     = lags(peak_idx);
% offset_s        = (t_a(1) - t_b(1)) + lag_samples * dt;
% 
% xc_norm = max(abs(xc_vals));
% xc_self = sqrt(sum(xc_a.^2) * sum(xc_b.^2));
% quality = 0;
% if xc_self > 0, quality = xc_norm / xc_self; end
% 
% fprintf('  Offset: %+.3f s  |  Quality: %.4f\n', offset_s, quality);
% 
% % ---- Plot ----
% t_b_aligned = t_b + offset_s;
% 
% figure('Name', ['Pair Check: ' session_label], 'Position', [100 100 1400 500]);
% 
% % Top: full signal overlay
% subplot(2,1,1);
% plot(t_a,         v_a, 'b',  'LineWidth', 0.8); hold on;
% plot(t_b_aligned, v_b, 'r--','LineWidth', 0.8);
% xlabel('Time (s)'); ylabel('RPM');
% title(sprintf('%s  |  offset = %+.3fs  |  quality = %.4f', ...
%     session_label, offset_s, quality));
% legend('Dash (Engine\_Speed)', 'ECU (aligned)', 'Location', 'best');
% grid on;
% 
% % Bottom: zoomed to first 300s of Dash for fine detail
% subplot(2,1,2);
% t_zoom = [t_a(1), min(t_a(1)+300, t_a(end))];
% plot(t_a,         v_a, 'b',  'LineWidth', 1.0); hold on;
% plot(t_b_aligned, v_b, 'r--','LineWidth', 1.0);
% xlim(t_zoom);
% xlabel('Time (s)'); ylabel('RPM');
% title('Zoomed — first 300s of Dash');
% legend('Dash', 'ECU (aligned)', 'Location', 'best');
% grid on;
% end
% 
% 
% % =========================================================================
% %  HELPER FUNCTIONS
% % =========================================================================
% 
% function map = build_stem_map(folder)
% % BUILD_STEM_MAP  Create struct map of MATLAB-safe file stems to full paths.
% % Maps: {valid_stem} -> full_filepath
%     map = struct();
%     if ~isfolder(folder), return; end
%     listing_temp = dir(fullfile(folder, '**', '*.ld'));
%     listing = listing_temp(~[listing_temp.isdir]);
%     listing = listing(~startsWith({listing.name}, '._'));
%     listing = listing(~contains({listing.name}, '_shifted'));
%     for i = 1 : numel(listing)
%         [~, stem]  = fileparts(listing(i).name);
%         safe_stem  = matlab.lang.makeValidName(stem);
%         map.(safe_stem) = fullfile(listing(i).folder, listing(i).name);
%     end
% end
% 
% 
% function stem = extract_stem(filepath)
% % EXTRACT_STEM  Get MATLAB-safe filename stem (without .ld extension).
%     [~, name] = fileparts(filepath);
%     stem = matlab.lang.makeValidName(name);
% end
% 
% 
% function [tla, session] = extract_tla_session(stem)
% % EXTRACT_TLA_SESSION  Parse stem as TLA_YEAR_SESSION pattern.
% % Returns: TLA = three-letter acronym, SESSION = remainder after TLA_YEAR
%     parts = strsplit(stem, '_');
%     if numel(parts) >= 1, tla = parts{1}; else, tla = stem; end
%     if numel(parts) >= 3, session = strjoin(parts(3:end), '_'); else, session = ''; end
% end
% 
% 
% function relpath = strip_common_prefix(filepath, root_folder)
% % STRIP_COMMON_PREFIX  Convert absolute path to relative path.
% % If filepath starts with root_folder, strip it and return remainder.
% % Otherwise return filepath unchanged.
%     if startsWith(filepath, root_folder, 'IgnoreCase', true)
%         relpath = filepath(length(root_folder)+1:end);
%         if startsWith(relpath, filesep)
%             relpath = relpath(2:end);
%         end
%     else
%         relpath = filepath;
%     end
% end
% 
% function mfr = local_resolve_manufacturer_by_tla(tla, driver_map)
% % Resolve manufacturer for a driver given their already-resolved TLA.
% mfr = '';
% if isempty(driver_map) || isempty(tla), return; end
% keys = fieldnames(driver_map);
% for ki = 1:numel(keys)
%     entry = driver_map.(keys{ki});
%     if isfield(entry, 'tla') && strcmp(entry.tla, tla)
%         if isfield(entry, 'manufacturer') && ~isempty(entry.manufacturer)
%             mfr = entry.manufacturer;
%         end
%         return;
%     end
% end
% end
% 
% function tla = resolve_tla_by_car_number(car_num, driver_map)
% % RESOLVE_TLA_BY_CAR_NUMBER  Resolve a car number to its canonical driver TLA
% %   via the alias map's 'num' field. Returns '' if no match found.
% %   car_num may be numeric or char/string; entry.num is stored as char.
%     tla = '';
%     if isempty(driver_map) || ~isstruct(driver_map) || isempty(car_num)
%         return;
%     end
%     car_key = strtrim(char(string(car_num)));
%     keys = fieldnames(driver_map);
%     for ki = 1:numel(keys)
%         entry = driver_map.(keys{ki});
%         if ~isfield(entry, 'num') || isempty(entry.num)
%             continue;
%         end
%         entry_key = strtrim(char(string(entry.num)));
%         if strcmp(entry_key, car_key)
%             if isfield(entry, 'tla') && ~isempty(entry.tla)
%                 tla = entry.tla;
%             elseif isfield(entry, 'canonical') && ~isempty(entry.canonical)
%                 tla = entry.canonical;
%             end
%             return;
%         end
%     end
% end
% function mfr = local_resolve_manufacturer(driver_key, driver_map)
% % Resolve manufacturer for a driver, accepting either a TLA or full name.
% % Tries an exact TLA match first (cheap, unambiguous), then falls back
% % to a case-insensitive full-name match against driver_map.
% mfr = '';
% if isempty(driver_map) || isempty(driver_key), return; end
% 
% driver_key = strtrim(driver_key);
% keys = fieldnames(driver_map);
% 
% % ---- Pass 1: exact TLA match ----
% for ki = 1:numel(keys)
%     entry = driver_map.(keys{ki});
%     if isfield(entry, 'tla') && strcmp(entry.tla, strrep(driver_key, ' ', '_'))
%         if isfield(entry, 'manufacturer') && ~isempty(entry.manufacturer)
%             mfr = entry.manufacturer;
%         end
%         return;
%     end
% end
% 
% % ---- Pass 2: case-insensitive full-name match ----
% for ki = 1:numel(keys)
%     entry = driver_map.(keys{ki});
%     if isfield(entry, 'name') && strcmpi(strtrim(entry.name), driver_key)
%         if isfield(entry, 'manufacturer') && ~isempty(entry.manufacturer)
%             mfr = entry.manufacturer;
%         end
%         return;
%     end
% end
% end
% 
% 
