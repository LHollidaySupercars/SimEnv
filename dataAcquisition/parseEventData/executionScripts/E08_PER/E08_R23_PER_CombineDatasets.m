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

SESSION   = 'R23';   % session to process (used in all phases)

DRIVERS   = {};      % {} = all drivers
                     % car numbers:  {'18'}  or  {'18','99'}
                     % TLAs:         {'MOS'} or  {'MOS','DEP'}

OVERWRITE = true;    % true = re-process existing output files

% Phase 1 parallel options
PHASE1_MODE            = 'parallel';   % 'serial' | 'parallel'
N_WORKERS              = 6;       % 'auto' = one worker per driver, or integer e.g. 8
KEEP_WORKERS_OPEN      = true;         % true = cmd /k (windows stay open at report popup)
TMP_DIR                = '';           % '' = auto → <root_folder>\_tmp_parallel

% Phase 2 parallel options
ECU_CONCAT_MODE        = 'serial';   % 'serial' | 'parallel'
N_WORKERS_ECU          = 6;       % 'auto' = one worker per driver, or integer e.g. 8
KEEP_WORKERS_ECU_OPEN  = false;     % true = cmd /k (windows stay open)
TMP_DIR_ECU            = '';           % '' = auto → <root_folder>\_tmp_ecu_concat

% Phase 4 parallel options
PAIR_ECU_TEAM_MODE     = 'serial';   % 'serial' | 'parallel'
N_WORKERS_PAIR         = 6;       % number of workers for Phase 4 pairing
KEEP_WORKERS_PAIR_OPEN = false;    % true = cmd /k (windows stay open)
TMP_DIR_PAIR           = '';           % '' = auto → <root_folder>\_tmp_pair_phase
TRACKSIDE              = true;
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
cfg.rh_patch_file      = fullfile( pwd, 'dataAcquisition\parseEventData\executionScripts\E08_PER', 'E08_PER_Constants.xlsx');
CHANNELS_FILE          = fullfile( pwd, 'dataAcquisition\Motec_MP\channels\channels.xlsx');

% =========================================================================
%  EVENT CONFIG  — edit when setting up a new event
% =========================================================================
cfg.root_folder  = 'E:\2026\E08_PER';   % event root — all paths derived from here
cfg.hol_venue    = 'PER';
cfg.hol_event    = 'E08_PER';
cfg.event_date   = '2026-08-01';   % auto-filled from sessionDate.xlsx (this session's date) — used by Phase 1 (TeamData date filter) and Phase 4b (L180 sort)

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
%%  PHASE 0 — SPLIT ECU COMBINED SESSIONS 
% =========================================================================
% RUN_SPLIT_COMBINED = true;
% if RUN_SPLIT_COMBINED
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 0 — Split combined sessions\n');
%     fprintf('%s\n', repmat('=', 1, 60));
% 
%     split0_cfg                        = cfg;
%     split0_cfg.combined_input_dir     = 'E:\2026\E08_PER\ECU\P01_P02';
%     split0_cfg.combined_session_names = {'P01_P02'};
%     split0_cfg.ecu_format             = true;    % ECU M1 logger format
%     split0_cfg.overwrite              = false;   % don't clobber a manual split you already did
% 
%     [split0_csv, split0_ok, split0_skip, split0_fail] = smp_split_combined_sessions(split0_cfg);
% 
%     split0_csv_path = fullfile(split0_cfg.combined_input_dir, ...
%         sprintf('combined_split_report_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
%     fid0 = fopen(split0_csv_path, 'w');
%     if fid0 ~= -1
%         for ri = 1 : numel(split0_csv)
%             fprintf(fid0, '%s\n', split0_csv{ri});
%         end
%         fclose(fid0);
%         fprintf('Combined-split report -> %s\n', split0_csv_path);
%     end
%     fprintf('=== Phase 0: %d ok, %d skipped, %d failed ===\n\n', split0_ok, split0_skip, split0_fail);
% end
% =========================================================================
%%  PHASE 0 — SPLIT L180 COMBINED SESSIONS 
% =========================================================================
% RUN_SPLIT_L180_COMBINED = true;
% if RUN_SPLIT_L180_COMBINED
%     fprintf('\n%s\n', repmat('=', 1, 60));
%     fprintf('PHASE 0c — Split combined L180 sessions\n');
%     fprintf('%s\n', repmat('=', 1, 60));
% 
%     split0c_cfg                        = cfg;
%     split0c_cfg.combined_input_dir     = 'E:\2026\E08_PER\L180';
%     split0c_cfg.combined_session_names = {'P01_P02'};
%     split0c_cfg.split_data_type        = 'L180';   % same folder, filename suffixed by label
%     split0c_cfg.ecu_format             = cfg.l180_ecu_format;
%     split0c_cfg.overwrite              = false;
% 
%     [split0c_csv, split0c_ok, split0c_skip, split0c_fail] = smp_split_combined_sessions(split0c_cfg);
% 
%     split0c_csv_path = fullfile(split0c_cfg.combined_input_dir, ...
%         sprintf('combined_split_report_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
%     fid0c = fopen(split0c_csv_path, 'w');
%     if fid0c ~= -1
%         for ri = 1 : numel(split0c_csv)
%             fprintf(fid0c, '%s\n', split0c_csv{ri});
%         end
%         fclose(fid0c);
%         fprintf('Combined L180 split report -> %s\n', split0c_csv_path);
%     end
%     fprintf('=== Phase 0c: %d ok, %d skipped, %d failed ===\n\n', split0c_ok, split0c_skip, split0c_fail);
% end
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
%%  PHASE 2 — ECU CONCAT - REQUIRED FOR REY SINCE E08
% =========================================================================
if RUN_ECU_CONCAT
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 2 — ECU concat\n');
    fprintf('%s\n', repmat('=', 1, 60));
    cfg.driverFilter           = {'REY'};
    fprintf('------Track Side ECU exists \n %s', cfg.driverFilter)
    if strcmp(ECU_CONCAT_MODE, 'serial')
        smp_concat_ecu_per_driver(cfg);
    else
        launch_parallel_workers_ecu(cfg, N_WORKERS_ECU, KEEP_WORKERS_ECU_OPEN, TMP_DIR_ECU);
    end
end
% =========================================================================
%%  PHASE 3 — PAIR ECU + TeamData REQUIRED FOR REY SINCE E08
% =========================================================================
pairs_excel = '';
if RUN_PAIR
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 4 — Pair sessions  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    cfg.overwrite   = false;
    if strcmp(PAIR_ECU_TEAM_MODE, 'serial')
        pairs_excel = smp_pair_sessions(cfg);
    elseif strcmp(PAIR_ECU_TEAM_MODE, 'parallel')
        pairs_excel = launch_parallel_workers_pair(cfg, N_WORKERS_PAIR, KEEP_WORKERS_PAIR_OPEN, TMP_DIR_PAIR);
    end
    cfg.pairs_excel = pairs_excel;
end
% =========================================================================
%   ECU/DASH RESIDUAL CHECK
% =========================================================================
% 
if RUN_XCORR_CHECK
    fprintf('\n%s\n', repmat('=', 1, 60));
    fprintf('PHASE 4c — ECU/Dash engine residual  [%s]\n', cfg.session);
    fprintf('%s\n', repmat('=', 1, 60));
    add_residual_channels(cfg.com_dir, ...
        cfg.com_ecu_rpm_ch, cfg.dash_rpm_ch, cfg.resid_ecu_dash_ch, cfg.resample_hz);
end

if TRACKSIDE
    fprintf('\nTransfering Data:\n From: %s => %s',COMPILE_DIR_Sesh, cfg.com_dir);
    smp_copy_folder_contents(COMPILE_DIR_Sesh, cfg.com_dir);
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

% =========================================================================
%%  PHASE 7 — AUGMENT COM FILES WITH SIMULINK - DEVELOPMENT FOR NOW
% =========================================================================

% ---- Load vehicle kinematic parameters ----
GEN3_KinematicParameters;   % populates 'vehicle' in the workspace

% ---- Config ----
chanList = {'Steering_Angle', 'Ground_Speed', 'Acceleration_Y_Filt', ...
            'Wheel_Speed_Front_Left', 'Wheel_Speed_Front_Right'};

com_path{1}  = 'F:\2026\E08_PER\_HOL\teamData\R23\01_T8R\FEE_2026_R23_combined_l180.ld';
com_path{2}  = 'F:\2026\E08_PER\_HOL\teamData\R23\03_WTG\MOS_2026_R23_combined_l180.ld';
com_path{3}  = 'F:\2026\E08_PER\_HOL\teamData\R23\10_T18\DEP_2026_R23_combined_l180.ld';
com_path{4}  = 'F:\2026\E08_PER\_HOL\teamData\R23\10_T18\REY_2026_R23_combined_l180.ld';

modelName = 'V8_mdl';

params.rTyreFront = 320/1000;
params.rTyreRear  = 330/1000;
params.mass       = 1350;
params.RAD2DEG_V  = 180/pi;
params.vehicle    = vehicle;
params.Cd_inital  = 1;

% ---- Build channel input bus (base workspace, before sim compiles) ----
build_aug_input_bus(chanList, 'AugInputBus');

% ---- Build vehicle bus: clear stale workspace state + file, rebuild fresh ----
evalin('base', 'clearvars -regexp ^VehicleBus$|^slBus');

f = which('VehicleBus.m');
if ~isempty(f)
    delete(f);
end

Simulink.Bus.createObject(params.vehicle, 'VehicleBus');

% Sanity check: confirm the bus actually came out nested, not flat
b = evalin('base', 'VehicleBus');
assert(~strcmp(b.Elements(1).DataType, 'double'), ...
    'VehicleBus built flat, not nested — check vehicle struct / stale file on path.');

% ---- Load .ld file ----
for i = 1 : length(com_path)

    aug_data      = motec_ld_reader(com_path{i}, {});
    aug_data.info = motec_ld_info(com_path{i}, false);
    preNames      = fieldnames(aug_data);
    simParams     
    % ---- Run sim ----
    simOut = run_sim_augment(modelName, aug_data, chanList, params);
    [aug_data, newChannels] = extract_new_sim_channels(aug_data, simOut, preNames);
    
    fprintf('New channel(s): %s\n', strjoin(newChannels, ', '));
end
% aug_data now has new channels stamped write_to_ld=true.
% Paste existing ld_ch collection loop + ld_add_channel + movefile here.


%% ===================== Local functions ==================================

function simOut = run_sim_augment(modelName, aug_data, chanList, params)
    ds = build_sim_input_dataset(aug_data, chanList);

    simIn = Simulink.SimulationInput(modelName);
    pNames = fieldnames(params);
    for pi = 1:numel(pNames)
        simIn = simIn.setVariable(pNames{pi}, params.(pNames{pi}));
    end
    simIn  = simIn.setExternalInput(ds);
    simOut = sim(simIn);
end

function [aug_data, newChannels] = extract_new_sim_channels(aug_data, simOut, preNames)
    newChannels = {};

    outputFields = {'bicycleModel', 'bicycleModel1'};  % adjust to match what's actually populated
    for oi = 1:numel(outputFields)
        of = outputFields{oi};
        if ~isprop(simOut, of), continue; end

        s = simOut.(of);
        if ~isfield(s, 'signals'), continue; end

        for si = 1:numel(s.signals)
            name = s.signals(si).label;
            if isempty(name), name = sprintf('%s_%d', of, si); end

            if isfield(aug_data, name), continue; end  % pass-through, skip

            ch.data        = s.signals(si).values(:);
            ch.time        = s.time(:);
            ch.units       = '';
            ch.sample_rate = 1 / mean(diff(s.time));
            ch.raw_name    = name;
            ch.write_to_ld = true;
            ch.overwrite   = false;

            aug_data.(name) = ch;
            newChannels{end+1} = name; %#ok<AGROW>
        end
    end
end

function ds = build_sim_input_dataset(chan, chanList)
% Bus input format per MathWorks docs: a struct whose fields are
% timeseries objects, field names matching bus element names exactly.
% That struct becomes the single Dataset element for the bus Inport.

    busData = struct();

    for i = 1:numel(chanList)
        name = chanList{i};
        t = chan.(name).time(:);
        v = chan.(name).data(:);

        mono = [true; diff(t) > 0];
        t = t(mono);
        v = v(mono);

        ts = timeseries(v, t, 'Name', name);
        ts.DataInfo.Interpolation = tsdata.interpolation('linear');

        busData.(name) = ts;
    end

    ds = Simulink.SimulationData.Dataset;
    ds = ds.addElement(busData, 'Road Input');   % struct-of-timeseries, one Dataset element
end

function busObj = build_aug_input_bus(chanList, busName)
% BUILD_AUG_INPUT_BUS  Build a Simulink.Bus object from chanList, loop-based
% so it always stays in sync with build_sim_input_dataset.
    if nargin < 2 || isempty(busName)
        busName = 'AugInputBus';
    end

    elems(numel(chanList), 1) = Simulink.BusElement;
    for i = 1:numel(chanList)
        elems(i).Name       = chanList{i};
        elems(i).DataType   = 'double';
        elems(i).Dimensions = 1;
        elems(i).Complexity = 'real';
    end

    busObj = Simulink.Bus;
    busObj.Elements = elems;

    assignin('base', busName, busObj);
    fprintf('Bus object "%s" built with %d element(s): %s\n', ...
        busName, numel(chanList), strjoin(chanList, ', '));
end

function busObj = build_vehicle_bus(vehicleStruct, busName)
% BUILD_VEHICLE_BUS  Build a Simulink.Bus object from the fieldnames of
% an existing vehicle params struct. Dimensions are auto-detected from
% the actual field values (scalar -> 1, vector -> numel).
    if nargin < 2 || isempty(busName)
        busName = 'VehicleBus';
    end

    fn = fieldnames(vehicleStruct);
    elems(numel(fn), 1) = Simulink.BusElement;
    for i = 1:numel(fn)
        val = vehicleStruct.(fn{i});
        elems(i).Name       = fn{i};
        elems(i).DataType   = 'double';
        elems(i).Dimensions = numel(val);   % scalar=1, vector=N
        elems(i).Complexity = 'real';
    end

    busObj = Simulink.Bus;
    busObj.Elements = elems;

    assignin('base', busName, busObj);
    fprintf('Bus object "%s" built with %d element(s): %s\n', ...
        busName, numel(fn), strjoin(fn, ', '));
end