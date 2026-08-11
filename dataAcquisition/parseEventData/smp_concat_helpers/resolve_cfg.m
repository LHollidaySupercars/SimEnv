function cfg = resolve_cfg(cfg, SESSION, DRIVERS, OVERWRITE)
% RESOLVE_CFG  Derive all paths, channel aliases, and filter fields from the
%   user-supplied event config and AT-TRACK controls. Do not edit.

ALIAS_DIR = fullfile(pwd, 'dataAcquisition\Motec_MP\alias');

% ---- Alias files ----
cfg.event_alias_file  = fullfile(pwd,'\dataAcquisition\parseEventData\executionScripts', cfg.hol_event, 'eventAlias.xlsx');
cfg.driver_alias_file = fullfile(ALIAS_DIR, 'driverAlias.xlsx');
cfg.session_meta_file = fullfile(fileparts(mfilename('fullpath')), ...
                            'channels', 'session_metadata.xlsx');

% ---- Directory paths ----
cfg.td_input_dir      = fullfile(cfg.root_folder, '_TeamData');
cfg.td_hol_output_dir = fullfile(cfg.root_folder, '_HOL', 'teamData');
cfg.ecu_input_dir     = fullfile(cfg.root_folder, 'ECU', SESSION);
cfg.ecu_hol_dir       = fullfile(cfg.root_folder,'_HOL', 'ECU');
cfg.ecu_concat_dir    = cfg.ecu_hol_dir;   % Phase 2 writes; Phase 3 reads same dir
cfg.l180_input_dir    = fullfile(cfg.root_folder, 'L180');
cfg.l180_hol_dir      = fullfile(cfg.root_folder, 'L180', 'HOL');
cfg.com_dir           = fullfile(cfg.root_folder, 'COM', SESSION);

% ---- Phase-specific field aliases ----
cfg.merge_resample_hz  = cfg.resample_hz;
cfg.merge_max_offset_s = cfg.max_offset_s;
cfg.merge_rpm_min      = cfg.rpm_min;
cfg.dash_rpm_ch        = cfg.rpm_ch;
cfg.ecu_rpm_ch         = cfg.rpm_ch;
cfg.l180_rpm_ch        = cfg.rpm_ch;
cfg.ecu_ert_names      = {cfg.ert_ch};
cfg.l180_ert_names     = {cfg.ert_ch};
cfg.td_ert_names       = {cfg.ert_ch};
cfg.session_labels     = {SESSION};
cfg.session_aliases    = {};
cfg.com_rpm_ch         = 'ecu_Engine_Speed';
cfg.com_ecu_rpm_ch     = 'ecu_Engine_Speed';
cfg.com_l180_rpm_ch    = 'l180_Engine_Speed';

% ---- xcorr + residual channel names ----
cfg.xcorr_ecu_dash_ch  = 'xcorr_ecu_dash';
cfg.xcorr_l180_dash_ch = 'xcorr_l180_dash';
cfg.xcorr_l180_ecu_ch  = 'xcorr_l180_ecu';
cfg.resid_ecu_dash_ch  = 'resid_ecu_dash';
cfg.resid_l180_dash_ch = 'resid_l180_dash';
cfg.resid_l180_ecu_ch  = 'resid_l180_ecu';

% ---- Session / overwrite ----
cfg.overwrite        = OVERWRITE;
cfg.session          = SESSION;
cfg.session_filter   = {SESSION};

% ---- Resolve DRIVERS → per-phase filters ----
cfg.fix_filter       = DRIVERS;
cfg.driver_filter    = {};
cfg.team_filter      = {};
cfg.split_car_filter = {};
cfg.ecu_tla_filter   = {};

if ~isempty(DRIVERS)
    fix_driver_map = [];
    if isfile(cfg.driver_alias_file)
        try
            fix_driver_map = smp_driver_alias_load(cfg.driver_alias_file);
        catch, end
    end
    fix_canonicals = {}; fix_tlas = {}; fix_car_nums = {};
    if ~isempty(fix_driver_map)
        keys = fieldnames(fix_driver_map);
        for ki = 1 : numel(keys)
            e = fix_driver_map.(keys{ki});
            match = ismember(lower(DRIVERS), lower(e.tla)) | ...
                    ismember(lower(DRIVERS), lower(e.num));
            if any(match)
                fix_canonicals{end+1} = e.canonical;
                fix_tlas{end+1}       = e.tla;
                fix_car_nums{end+1}   = e.num;
            end
        end
    end
    if ~isempty(fix_canonicals)
        cfg.driver_filter    = fix_canonicals;
        cfg.ecu_tla_filter   = fix_tlas;
        cfg.split_car_filter = fix_car_nums;
        fprintf('[resolve_cfg] Restricted to: TLAs=%s  Cars=%s\n', ...
            strjoin(fix_tlas,','), strjoin(fix_car_nums,','));
    else
        fprintf('[resolve_cfg] WARNING: no alias matches found for: %s\n', ...
            strjoin(DRIVERS,','));
    end
end
end

