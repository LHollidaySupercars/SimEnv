function smp_split_ecu_by_uptime(cfg)
%% smp_split_ecu_by_uptime(cfg)
% Split ECU, L180, and TeamData .ld files into per-session files by detecting
% session boundaries via Engine_Run_Time resets / gaps.
%
% Strategy: binary-patch data_ptr and data_len in each channel metadata
% record so each output file exposes only its session window.  No sample
% data is moved — every output file is the same byte-size as the source.
%
% Required cfg fields:
%   cfg.ecu_concat_dir    — ECU input folder (output of smp_concat_ecu_per_driver)
%   cfg.hol_dir           — root HOL output folder; ECU goes to HOL/ECU/
%   cfg.session_labels    — cell array, one label per segment e.g. {'Q14','Q15'}
%   cfg.session_aliases   — Nx2 cell {canonical, {alias,...}}
%   cfg.min_gap_s         — forward ERT jump (s) needed to count as boundary
%   cfg.min_seg_s         — minimum segment duration (s); shorter gaps are merged
%   cfg.split_on_reset    — true = also split on ERT resets (ECU power cycle)
%   cfg.ecu_format        — true = M1 ECU logger (float32 type-4)
%   cfg.l180_ecu_format   — false = standard dash/logger format
%   cfg.l180_input_dir    — L180 raw folder ('' = skip L180 split)
%   cfg.td_hol_output_dir — TeamData HOL folder ('' = skip TD split)
%   cfg.hol_venue         — venue string patched into output headers
%   cfg.hol_event         — event string patched into output headers
%   cfg.overwrite         — true = overwrite existing output files
%   cfg.rename_output     — true = name outputs {TLA}_{year}_{session}.ld
%   cfg.driver_alias_file — path to driverAlias.xlsx ('' = skip)
%   cfg.ecu_ert_names     — ERT channel name candidates for ECU (default: {'ECU_Uptime'})
%   cfg.l180_ert_names    — ERT channel name candidates for L180 (default: {'ECU_Uptime'})
%   cfg.td_ert_names      — ERT channel name candidates for TeamData (default: {'ECU_Uptime'})

% =========================================================================
%  RESOLVE CONFIG
% =========================================================================
INPUT_DIR      = cfg.ecu_concat_dir;
OUTPUT_DIR      = cfg.ecu_hol_dir;
L180_OUTPUT_DIR = cfg.l180_hol_dir;
SESSION_LABELS = cfg.session_labels;
SESSION_ALIASES = cfg.session_aliases;
MIN_GAP_S      = cfg.min_gap_s;
MIN_SEG_S      = cfg.min_seg_s;
SPLIT_ON_RESET = cfg.split_on_reset;
ECU_FORMAT     = cfg.ecu_format;
HOL_VENUE      = cfg.hol_venue;
HOL_EVENT      = cfg.hol_event;
OVERWRITE      = cfg.overwrite;
RENAME_OUTPUT  = cfg.rename_output;
DRIVER_ALIAS_FILE = cfg.driver_alias_file;

if isfield(cfg, 'ecu_ert_names') && ~isempty(cfg.ecu_ert_names)
    ERT_NAMES = cfg.ecu_ert_names;
else
    ERT_NAMES = {'ECU_Uptime'};
end

L180_INPUT_DIR = '';
% if isfield(cfg, 'l180_input_dir'), L180_INPUT_DIR = cfg.l180_input_dir; end
% L180_OUTPUT_DIR = '';
% if ~isempty(L180_INPUT_DIR)
%     L180_OUTPUT_DIR = fullfile(cfg.hol_dir, 'L180');
% end
L180_ECU_FORMAT = cfg.l180_ecu_format;
if isfield(cfg, 'l180_ert_names') && ~isempty(cfg.l180_ert_names)
    L180_ERT_NAMES = cfg.l180_ert_names;
else
    L180_ERT_NAMES = {'ECU_Uptime'};
end

TD_INPUT_DIR = '';
if isfield(cfg, 'td_hol_output_dir') && ~isempty(cfg.td_hol_output_dir)
    TD_INPUT_DIR = cfg.td_hol_output_dir;
end
if isfield(cfg, 'td_hol_output_dir') && ~isempty(cfg.td_hol_output_dir)
    TD_OUTPUT_DIR = cfg.td_hol_output_dir;
else
    TD_OUTPUT_DIR = '';   % skip TeamData split if no output dir configured
end
TD_ECU_FORMAT = false;
if isfield(cfg, 'td_ert_names') && ~isempty(cfg.td_ert_names)
    TD_ERT_NAMES = cfg.td_ert_names;
else
    TD_ERT_NAMES = {'ECU_Uptime'};
end

% =========================================================================
%  LOAD DRIVER ALIAS MAP
% =========================================================================
driver_map = [];
if ~isempty(DRIVER_ALIAS_FILE) && isfile(DRIVER_ALIAS_FILE)
    try
        driver_map = smp_driver_alias_load(DRIVER_ALIAS_FILE);
        fprintf('Loaded driver aliases: %d entries.\n', numel(fieldnames(driver_map)));
    catch err_da
        fprintf('[WARN] Could not load driver aliases: %s\n', err_da.message);
    end
end

% =========================================================================
%  BUILD CONFIG STRUCTS
% =========================================================================
shared_cfg = struct( ...
    'session_labels',  {SESSION_LABELS}, ...
    'session_aliases', {SESSION_ALIASES}, ...
    'min_gap_s',       MIN_GAP_S, ...
    'min_seg_s',       MIN_SEG_S, ...
    'split_on_reset',  SPLIT_ON_RESET, ...
    'rename_output',   RENAME_OUTPUT, ...
    'overwrite',       OVERWRITE, ...
    'hol_venue',       HOL_VENUE, ...
    'hol_event',       HOL_EVENT ...
);
if isfield(cfg, 'warmup_beacon_chs')
    shared_cfg.warmup_beacon_chs = cfg.warmup_beacon_chs;
elseif isfield(cfg, 'warmup_beacon_ch')
    shared_cfg.warmup_beacon_chs = {cfg.warmup_beacon_ch};
end
if isfield(cfg, 'ridealong_car_nums')
    shared_cfg.ridealong_car_nums = cfg.ridealong_car_nums;
end
if isfield(cfg, 'split_car_filter')
    shared_cfg.split_car_filter = cfg.split_car_filter;
end

ecu_cfg              = shared_cfg;
ecu_cfg.input_dir    = INPUT_DIR;
ecu_cfg.output_dir   = OUTPUT_DIR;
ecu_cfg.source_label = 'ECU';
ecu_cfg.ecu_format   = ECU_FORMAT;
ecu_cfg.ert_names    = ERT_NAMES;

% =========================================================================
%  RUN ECU SPLIT
% =========================================================================
[ecu_csv, ecu_drv, ecu_ok, ecu_skip, ecu_fail, ecu_segs] = split_ld_folder(ecu_cfg, driver_map);

% =========================================================================
%  RUN L180 SPLIT
% =========================================================================
if ~isempty(L180_INPUT_DIR) && isfolder(L180_INPUT_DIR)
    l180_cfg              = shared_cfg;
    l180_cfg.input_dir    = L180_INPUT_DIR;
    l180_cfg.output_dir   = L180_OUTPUT_DIR;
    l180_cfg.source_label = 'L180';
    l180_cfg.ecu_format   = L180_ECU_FORMAT;
    l180_cfg.ert_names    = L180_ERT_NAMES;

    [l180_csv, l180_drv, l180_ok, l180_skip, l180_fail, l180_segs] = split_ld_folder(l180_cfg, driver_map);
else
    l180_csv = {};  l180_segs = {};
    l180_drv = struct('filename',{},'raw_driver',{},'canonical',{},'car_num',{},...
                      'team_tla',{},'alias_status',{},'proc_status',{},'sessions_ok',{});
    l180_ok = 0;  l180_skip = 0;  l180_fail = 0;
    fprintf('[INFO] L180 split skipped (L180_INPUT_DIR empty or not found).\n');
end

% =========================================================================
%  RUN TEAMDATA SPLIT
% =========================================================================
if ~isempty(TD_INPUT_DIR) && isfolder(TD_INPUT_DIR)
    td_cfg              = shared_cfg;
    td_cfg.input_dir    = TD_INPUT_DIR;
    td_cfg.output_dir   = TD_OUTPUT_DIR;
    td_cfg.source_label = 'TeamData';
    td_cfg.ecu_format   = TD_ECU_FORMAT;
    td_cfg.ert_names    = TD_ERT_NAMES;

    [td_csv, td_drv, td_ok, td_skip, td_fail, td_segs] = split_ld_folder(td_cfg, driver_map);
else
    td_csv = {};  td_segs = {};
    td_drv = struct('filename',{},'raw_driver',{},'canonical',{},'car_num',{},...
                    'team_tla',{},'alias_status',{},'proc_status',{},'sessions_ok',{});
    td_ok = 0;  td_skip = 0;  td_fail = 0;
    fprintf('[INFO] TeamData split skipped (TD_INPUT_DIR empty or not found).\n');
end

% =========================================================================
%  WRITE ECU SPLIT REPORT CSV
% =========================================================================
if ~isfolder(OUTPUT_DIR), mkdir(OUTPUT_DIR); end
ecu_csv_path = fullfile(OUTPUT_DIR, ...
    sprintf('ecu_split_report_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
fid_rpt = fopen(ecu_csv_path, 'w');
if fid_rpt ~= -1
    for ri = 1 : numel(ecu_csv)
        fprintf(fid_rpt, '%s\n', ecu_csv{ri});
    end
    fclose(fid_rpt);
    fprintf('\nECU split report -> %s\n', ecu_csv_path);
else
    fprintf('\n[WARN] Could not write ECU split report to %s\n', ecu_csv_path);
end

fprintf('=== ECU: %d ok, %d no-ERT, %d mismatch ===\n', ecu_ok, ecu_skip, ecu_fail);

% =========================================================================
%  WRITE L180 SPLIT REPORT CSV
% =========================================================================
if ~isempty(l180_csv)
    if ~isfolder(L180_OUTPUT_DIR), mkdir(L180_OUTPUT_DIR); end
    l180_rpt_path = fullfile(L180_OUTPUT_DIR, ...
        sprintf('l180_split_report_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
    fid_l = fopen(l180_rpt_path, 'w');
    if fid_l ~= -1
        for ri = 1 : numel(l180_csv)
            fprintf(fid_l, '%s\n', l180_csv{ri});
        end
        fclose(fid_l);
        fprintf('L180 split report -> %s\n', l180_rpt_path);
    else
        fprintf('[WARN] Could not write L180 split report to %s\n', l180_rpt_path);
    end
    fprintf('=== L180: %d ok, %d no-ERT, %d mismatch ===\n', l180_ok, l180_skip, l180_fail);
end

% =========================================================================
%  WRITE TEAMDATA SPLIT REPORT CSV
% =========================================================================
if ~isempty(td_csv)
    if ~isfolder(TD_OUTPUT_DIR), mkdir(TD_OUTPUT_DIR); end
    td_rpt_path = fullfile(TD_OUTPUT_DIR, ...
        sprintf('teamdata_split_report_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
    fid_t = fopen(td_rpt_path, 'w');
    if fid_t ~= -1
        for ri = 1 : numel(td_csv)
            fprintf(fid_t, '%s\n', td_csv{ri});
        end
        fclose(fid_t);
        fprintf('TeamData split report -> %s\n', td_rpt_path);
    else
        fprintf('[WARN] Could not write TeamData split report to %s\n', td_rpt_path);
    end
    fprintf('=== TeamData: %d ok, %d no-ERT, %d mismatch ===\n', td_ok, td_skip, td_fail);
end

% =========================================================================
%  DRIVER CHECK EXCEL REPORT
% =========================================================================
xl_path = fullfile(OUTPUT_DIR, ...
    sprintf('driver_check_%s.xlsx', datestr(now, 'yyyymmdd_HHMMSS')));

% --- Sheet: ECU_DriverDetail ---
drv_hdr = {'Filename','RawDriver','CanonicalDriver','CarNum','TeamTLA', ...
            'AliasStatus','ProcStatus','SessionsWritten','SegsRaw','SegsDetected','WarmupSegs','SkipReason'};
drv_xl  = [drv_hdr; cell(numel(ecu_drv), numel(drv_hdr))];
for ri = 1 : numel(ecu_drv)
    r = ecu_drv(ri);
    drv_xl(ri+1,:) = {r.filename, r.raw_driver, r.canonical, r.car_num, ...
                      r.team_tla, r.alias_status, r.proc_status, r.sessions_ok, ...
                      r.n_segs_raw, r.n_segs_detected, r.n_warmup, r.skip_reason};
end
try
    if ~isfolder(OUTPUT_DIR), mkdir(OUTPUT_DIR); end
    writecell(drv_xl, xl_path, 'Sheet', 'ECU_DriverDetail');
    fprintf('ECU driver detail sheet written.\n');
catch err_xl
    fprintf('[WARN] Could not write ECU_DriverDetail sheet: %s\n', err_xl.message);
end

% --- Sheet: L180_DriverDetail ---
if ~isempty(l180_drv)
    l180_drv_xl = [drv_hdr; cell(numel(l180_drv), numel(drv_hdr))];
    for ri = 1 : numel(l180_drv)
        r = l180_drv(ri);
        l180_drv_xl(ri+1,:) = {r.filename, r.raw_driver, r.canonical, r.car_num, ...
                                r.team_tla, r.alias_status, r.proc_status, r.sessions_ok, ...
                                r.n_segs_raw, r.n_segs_detected, r.n_warmup, r.skip_reason};
    end
    try
        writecell(l180_drv_xl, xl_path, 'Sheet', 'L180_DriverDetail');
        fprintf('L180 driver detail sheet written.\n');
    catch err_xl
        fprintf('[WARN] Could not write L180_DriverDetail sheet: %s\n', err_xl.message);
    end
end

% --- Sheet: TeamData_DriverDetail ---
if ~isempty(td_drv)
    td_drv_xl = [drv_hdr; cell(numel(td_drv), numel(drv_hdr))];
    for ri = 1 : numel(td_drv)
        r = td_drv(ri);
        td_drv_xl(ri+1,:) = {r.filename, r.raw_driver, r.canonical, r.car_num, ...
                              r.team_tla, r.alias_status, r.proc_status, r.sessions_ok, ...
                              r.n_segs_raw, r.n_segs_detected, r.n_warmup, r.skip_reason};
    end
    try
        writecell(td_drv_xl, xl_path, 'Sheet', 'TeamData_DriverDetail');
        fprintf('TeamData driver detail sheet written.\n');
    catch err_xl
        fprintf('[WARN] Could not write TeamData_DriverDetail sheet: %s\n', err_xl.message);
    end
end

% --- Sheet 2: DriverCoverage (per canonical driver x session) ---
if ~isempty(driver_map)
    dm_keys   = fieldnames(driver_map);
    n_drivers = numel(dm_keys);

    cov_canon    = cell(n_drivers, 1);
    cov_car_num  = cell(n_drivers, 1);
    cov_team_tla = cell(n_drivers, 1);
    cov_counts   = zeros(n_drivers, numel(SESSION_LABELS));
    for di = 1 : n_drivers
        entry = driver_map.(dm_keys{di});
        cov_canon{di}    = entry.canonical;
        cov_car_num{di}  = entry.num;
        cov_team_tla{di} = entry.team_tla;
    end

    % Scan actual output files to build accurate per-driver per-session counts
    for si = 1 : numel(SESSION_LABELS)
        lbl     = SESSION_LABELS{si};
        out_dir = fullfile(OUTPUT_DIR, lbl);
        if ~isfolder(out_dir), continue; end
        out_ld  = dir(fullfile(out_dir, '*.ld'));
        for oi = 1 : numel(out_ld)
            out_path = fullfile(out_ld(oi).folder, out_ld(oi).name);
            try
                inf2 = motec_ld_info(out_path, false);
                raw2 = strtrim(inf2.driver);
                [canon2, ~, ~, ~] = resolve_driver_info(raw2, driver_map);
                row_idx = find(strcmpi(canon2, cov_canon), 1);
                if ~isempty(row_idx)
                    cov_counts(row_idx, si) = cov_counts(row_idx, si) + 1;
                end
            catch
            end
        end
    end

    % Build coverage table
    cov_hdr = [{'CanonicalDriver','CarNum','TeamTLA'}, SESSION_LABELS(:)', {'Status'}];
    cov_xl  = [cov_hdr; cell(n_drivers, numel(cov_hdr))];
    for di = 1 : n_drivers
        row_counts = cov_counts(di, :);
        if all(row_counts > 0)
            cov_status = 'OK';
        elseif any(row_counts > 0)
            cov_status = 'PARTIAL';
        else
            cov_status = 'MISSING';
        end
        cov_xl(di+1,:) = [cov_canon(di), cov_car_num(di), cov_team_tla(di), ...
                          num2cell(row_counts), {cov_status}];
    end
    try
        writecell(cov_xl, xl_path, 'Sheet', 'DriverCoverage');
        fprintf('Driver coverage sheet written.\n');
    catch err_xl
        fprintf('[WARN] Could not write DriverCoverage sheet: %s\n', err_xl.message);
    end
else
    fprintf('[INFO] Driver alias map not loaded — DriverCoverage sheet skipped.\n');
end
fprintf('Driver check report  -> %s\n', xl_path);

% =========================================================================
%  WRITE SEGMENT LAYOUT EXCEL
% =========================================================================
all_segs = [ecu_segs(:); l180_segs(:); td_segs(:)];
if ~isempty(all_segs)
    seg_hdr = {'SourceType','SourceFile','Driver','CarNum','SegIdx','Session',...
               'T_start_s','T_end_s','Duration_s','IsWarmup','OutputFile'};
    seg_xl  = [seg_hdr; cell(numel(all_segs), numel(seg_hdr))];
    for si = 1 : numel(all_segs)
        s = all_segs{si};
        seg_xl(si+1,:) = {s.source_type, s.source_file, s.driver, s.car_num, ...
                          s.seg_idx, s.session, s.t_start, s.t_end, s.duration, ...
                          s.is_warmup, s.output_file};
    end
    seg_xl_path = fullfile(OUTPUT_DIR, ...
        sprintf('split_layout_%s.xlsx', datestr(now, 'yyyymmdd_HHMMSS')));
    try
        writecell(seg_xl, seg_xl_path, 'Sheet', 'SegmentLayout');
        fprintf('Segment layout Excel -> %s\n', seg_xl_path);
    catch err_xl
        fprintf('[WARN] Could not write segment layout Excel: %s\n', err_xl.message);
    end
end

fprintf('\n=== Done ===\n');

end  % function smp_split_ecu_by_uptime


% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

% -------------------------------------------------------------------------
function [csv_rows, drv_rows, n_ok, n_skip, n_fail, seg_rows] = split_ld_folder(cfg, driver_map)
% Splits all .ld files found recursively in cfg.input_dir by session using
% the uptime/ERT channel.  cfg fields: input_dir, output_dir, source_label,
% ecu_format, ert_names, min_gap_s, min_seg_s, split_on_reset,
% session_labels, session_aliases, rename_output, overwrite, hol_venue, hol_event.

    empty_drv = struct('filename',{},'raw_driver',{},'canonical',{},'car_num',{},...
                       'team_tla',{},'alias_status',{},'proc_status',{},'sessions_ok',{},...
                       'n_segs_raw',{},'n_segs_detected',{},'n_warmup',{},'skip_reason',{});
    if ~isfolder(cfg.input_dir)
        warning('split_ld_folder: %s input_dir not found:\n  %s', cfg.source_label, cfg.input_dir);
        csv_rows = {};  drv_rows = empty_drv;  seg_rows = {};
        n_ok = 0;  n_skip = 0;  n_fail = 0;
        return;
    end

    ld_files = recursive_find_ld_local(cfg.input_dir);
    if isempty(ld_files)
        warning('split_ld_folder: No .ld files found in:\n  %s', cfg.input_dir);
        csv_rows = {};  drv_rows = empty_drv;  seg_rows = {};
        n_ok = 0;  n_skip = 0;  n_fail = 0;
        return;
    end

    fprintf('\n=== %s split: %d file(s) in %s ===\n', cfg.source_label, numel(ld_files), cfg.input_dir);

    n_ok   = 0;
    n_skip = 0;
    n_fail = 0;
    csv_rows = {'SourceFile,Status,Session,T_start_s,T_end_s,Duration_s,OutputFile,ChannelsPatched'};
    drv_rows = struct('filename',{},'raw_driver',{},'canonical',{},'car_num',{},...
                      'team_tla',{},'alias_status',{},'proc_status',{},'sessions_ok',{},...
                      'n_segs_raw',{},'n_segs_detected',{},'n_warmup',{},'skip_reason',{});
    seg_rows = {};  % per-segment layout: {source_type, source_file, driver, car_num, seg_idx, session, t_start, t_end, duration, is_warmup, output_file}

    for fi = 1 : numel(ld_files)

        INPUT_FILE = ld_files{fi};
        [~, src_name, src_ext] = fileparts(INPUT_FILE);
        fprintf('\n========================================\n');
        fprintf('File %d / %d : %s\n', fi, numel(ld_files), [src_name src_ext]);
        fprintf('========================================\n');

        % Skip S3 ECU files — not required for processing
        if strncmpi(src_name, 'S3', 2)
            fprintf('  [SKIP] Filename starts with "S3" — omitted by config.\n');
            continue;
        end

        % Read file header for driver info (fast - header only)
        this_drv = struct('filename',[src_name src_ext],'raw_driver','','canonical','',...
                          'car_num','','team_tla','','alias_status','NOT_READ',...
                          'proc_status','UNKNOWN','sessions_ok','',...
                          'n_segs_raw',0,'n_segs_detected',0,'n_warmup',0,'skip_reason','');
        try
            hdr_inf = motec_ld_info(INPUT_FILE, false);
            this_drv.raw_driver = strtrim(hdr_inf.driver);
            [this_drv.canonical, this_drv.car_num, this_drv.team_tla, this_drv.alias_status] = ...
                resolve_driver_info(this_drv.raw_driver, driver_map);
        catch
        end
        % Fallback: if alias lookup failed, infer car_num from raw_driver prefix (e.g. '26-KA' -> '26')
        if isempty(this_drv.car_num) && ~isempty(this_drv.raw_driver)
            tok = regexp(strtrim(this_drv.raw_driver), '^(\d+)', 'tokens');
            if ~isempty(tok)
                this_drv.car_num = tok{1}{1};
                fprintf('  [INFO] car_num inferred from raw_driver prefix: "%s"\n', this_drv.car_num);
            end
        end
        fprintf('  Driver: "%s"  CarNum: "%s"  Canonical: "%s"\n', ...
            this_drv.raw_driver, this_drv.car_num, this_drv.canonical);

        % Car filter: skip files not in the allowed list
        if isfield(cfg, 'split_car_filter') && ~isempty(cfg.split_car_filter)
            if isempty(this_drv.car_num) || ~ismember(this_drv.car_num, cfg.split_car_filter)
                fprintf('  [SKIP] car_num "%s" not in split_car_filter — skipped\n', this_drv.car_num);
                continue;
            end
        end

        sessions_ok_this_file = {};

        % =====================================================================
        %  PHASE 1 - Detect split boundaries
        % =====================================================================
        fprintf('--- Phase 1: Detect session boundaries ---\n');

        ert          = [];
        ert_read_err = '';
        for k = 1 : numel(cfg.ert_names)
            fprintf('  Trying ERT candidate: "%s"\n', cfg.ert_names{k});
            try
                d  = motec_ld_reader(INPUT_FILE, {cfg.ert_names{k}}, cfg.ecu_format);
                fn = fieldnames(d);
                if ~isempty(fn)
                    ert = d.(fn{1});
                    fprintf('  Found ERT as "%s"  (%d samples @ %g Hz)\n', ...
                        cfg.ert_names{k}, numel(ert.data), ert.sample_rate);
                    break;
                end
            catch err
                ert_read_err = err.message;
                fprintf('  [WARN] Read error: %s\n', err.message);
            end
        end
        if isempty(ert) || isempty(ert.data)
            fprintf('  [SKIP] No ERT channel found - skipping file.\n');
            err_safe = strrep(ert_read_err, ',', ';');
            csv_rows{end+1} = sprintf('%s,SKIP_NO_ERT,,,,,,"%s"', ... %#ok<AGROW>
                [src_name src_ext], err_safe);
            this_drv.proc_status = 'SKIP_NO_ERT';
            drv_rows(end+1) = this_drv; %#ok<AGROW>
            n_skip = n_skip + 1;
            continue;
        end

        % Detect candidate boundaries
        % --- ERT glitch removal: interpolate over brief near-zero pulses ---
        % A run of samples where ERT < GLITCH_ERT_THRESH surrounded by much
        % higher values is a data dropout, not a genuine session event.
        GLITCH_ERT_THRESH  = 30;   % s — ERT values below this in a glitch run
        GLITCH_MAX_SAMPLES = 30;   % max run length to treat as a glitch
        ert_clean = ert.data;
        g_run_start = NaN;
        n_glitches  = 0;
        for gi = 1 : numel(ert_clean)
            if ert_clean(gi) < GLITCH_ERT_THRESH
                if isnan(g_run_start), g_run_start = gi; end
            else
                if ~isnan(g_run_start)
                    run_len = gi - g_run_start;
                    % Only patch if surrounded by high values (before > thresh)
                    % and run is short enough to be a glitch
                    if g_run_start > 1 && run_len <= GLITCH_MAX_SAMPLES && ...
                            ert_clean(g_run_start - 1) >= GLITCH_ERT_THRESH
                        % Linear interpolation from g_run_start-1 to gi
                        pre_val  = ert_clean(g_run_start - 1);
                        post_val = ert_clean(gi);
                        ert_clean(g_run_start : gi-1) = linspace(pre_val, post_val, run_len);
                        n_glitches = n_glitches + 1;
                        fprintf('  [GLITCH] Patched ERT near-zero run at t=%.1f s (len=%d samples)\n', ...
                            ert.time(g_run_start), run_len);
                    end
                    g_run_start = NaN;
                end
            end
        end
        if n_glitches > 0
            fprintf('  Patched %d ERT glitch run(s) before boundary detection.\n', n_glitches);
        end

        dt_data = diff(ert_clean);
        dt_time = diff(ert.time);

        if cfg.split_on_reset
            split_mask = (dt_data > cfg.min_gap_s) | (dt_data < 0) | (dt_time > cfg.min_gap_s);
        else
            split_mask = (dt_data > cfg.min_gap_s) | (dt_time > cfg.min_gap_s);
        end
        split_idx = find(split_mask);

        T_cand  = ert.time(split_idx);
        dt_cand = dt_data(split_idx);

        fprintf('  Raw candidates (%d):\n', numel(T_cand));
        for k = 1 : numel(T_cand)
            fprintf('    Candidate %d  t=%.1f s  ERT %.1f->%.1f  dt=%.1f\n', ...
                k, T_cand(k), ert.data(split_idx(k)), ert.data(split_idx(k)+1), dt_cand(k));
        end

        % Filter boundaries — keep if AT LEAST ONE side is >= min_seg_s.
        % Using max() rather than requiring both sides allows short segments
        % in the middle (inter-session warmup outings) to survive. Those short
        % segments are removed later by duration-based warmup detection.
        % Boundaries where BOTH sides are short (pure noise) are still dropped.
        POWER_CYCLE_ERT_S = 50;    % new ERT < 50 s after reset = cold-start power cycle
        file_end_t = ert.time(end);
        all_bounds = [0; T_cand(:); file_end_t];
        keep = true(numel(T_cand), 1);
        for k = 1 : numel(T_cand)
            seg_before  = all_bounds(k+1) - all_bounds(k);
            seg_after   = all_bounds(k+2) - all_bounds(k+1);
            new_ert_val = ert_clean(split_idx(k) + 1);
            is_power_cycle = (dt_cand(k) < 0) && (new_ert_val < POWER_CYCLE_ERT_S);

            if max(seg_before, seg_after) < cfg.min_seg_s
                % Both sides are short — pure noise, drop
                keep(k) = false;
                fprintf('    [FILTER] boundary %d: both sides short (%.0fs, %.0fs) — dropped\n', ...
                    k, seg_before, seg_after);
            elseif is_power_cycle
                fprintf('    [KEEP]   boundary %d: power-cycle (seg_before=%.0fs, new ERT=%.1fs, seg_after=%.0fs)\n', ...
                    k, seg_before, new_ert_val, seg_after);
            else
                fprintf('    [KEEP]   boundary %d: (seg_before=%.0fs, seg_after=%.0fs)\n', ...
                    k, seg_before, seg_after);
            end
        end
        T_splits = T_cand(keep);
        idx_kept = split_idx(keep);
        dt_kept  = dt_cand(keep);

        fprintf('  Kept %d split(s) after min_seg_s=%.0f s filter:\n', numel(T_splits), cfg.min_seg_s);
        for k = 1 : numel(T_splits)
            fprintf('    Split %d  t=%.1f s  ERT %.1f->%.1f  dt=%.1f\n', ...
                k, T_splits(k), ert.data(idx_kept(k)), ert.data(idx_kept(k)+1), dt_kept(k));
        end

        n_segs = numel(T_splits) + 1;
        this_drv.n_segs_raw      = numel(T_cand) + 1;  % before min_seg_s filter
        this_drv.n_segs_detected = n_segs;              % after filter
        seg_starts_bc = [0;          T_splits(:)];
        seg_ends_bc   = [T_splits(:); Inf       ];

        % ---- Warmup detection via lap beacon channel ----
        % A segment where every beacon sample is <= 0 is treated as a warmup:
        % it is written to output_dir/warmup/ and does not consume a SESSION_LABEL.
        warmup_mask = false(n_segs, 1);
        beacon_chs = {};
        if isfield(cfg, 'warmup_beacon_chs') && ~isempty(cfg.warmup_beacon_chs)
            beacon_chs = cfg.warmup_beacon_chs;
        elseif isfield(cfg, 'warmup_beacon_ch') && ~isempty(cfg.warmup_beacon_ch)
            beacon_chs = {cfg.warmup_beacon_ch};
        end
        bc = []; warmup_ch = '';
        for bci = 1 : numel(beacon_chs)
            try
                d_bc  = motec_ld_reader(INPUT_FILE, {beacon_chs{bci}}, cfg.ecu_format);
                fn_bc = fieldnames(d_bc);
                if ~isempty(fn_bc)
                    bc = d_bc.(fn_bc{1});
                    warmup_ch = beacon_chs{bci};
                    fprintf('  Found warmup beacon as "%s"\n', warmup_ch);
                    break;
                end
            catch
            end
        end
        if isempty(bc) && ~isempty(beacon_chs)
            fprintf('  [WARN] Warmup beacon not found (tried: %s) — beacon detection skipped.\n', ...
                strjoin(beacon_chs, ', '));
            % DIAGNOSTIC: list channel names in the file that look like beacon candidates
            try
                ch_info  = motec_ld_ch_info(INPUT_FILE);
                all_names = {ch_info.raw_name};
                kw = {'beacon','Beacon','lap','Lap'};
                matches = all_names(cellfun(@(n) ...
                    any(cellfun(@(k) ~isempty(strfind(n,k)), kw)), all_names));
                if ~isempty(matches)
                    fprintf('  [DIAG] Candidate beacon/lap channels in file: %s\n', strjoin(matches, ' | '));
                else
                    fprintf('  [DIAG] No beacon/lap channels found. All %d channels: %s\n', ...
                        numel(all_names), strjoin(all_names, ' | '));
                end
            catch err_ci
                fprintf('  [DIAG] Could not list channels: %s\n', err_ci.message);
            end
        end
        if ~isempty(bc)
            % Guard: if beacon is zero throughout the whole file, the channel
            % is not meaningful here — skip to avoid marking everything as warmup.
            if ~any(bc.data > 0)
                fprintf('  [WARN] Warmup beacon "%s" is zero throughout file — beacon detection skipped.\n', warmup_ch);
            else
                fprintf('  [DIAG] Beacon "%s": %d samples, global range [%.0f, %.0f]\n', ...
                    warmup_ch, numel(bc.data), min(bc.data), max(bc.data));
                for si = 1 : n_segs
                    in_seg = bc.time >= seg_starts_bc(si) & ...
                             (isinf(seg_ends_bc(si)) | bc.time < seg_ends_bc(si));
                    n_in = sum(in_seg);
                    if n_in > 0
                        seg_bc_min = min(bc.data(in_seg));
                        seg_bc_max = max(bc.data(in_seg));
                    else
                        seg_bc_min = NaN; seg_bc_max = NaN;
                    end
                    fprintf('  [DIAG]   Seg %d [%.0fs, %.0fs): %d samples  min=%.0f  max=%.0f\n', ...
                        si, seg_starts_bc(si), seg_ends_bc(si), n_in, seg_bc_min, seg_bc_max);
                    if n_in > 0 && seg_bc_max <= 0
                        warmup_mask(si) = true;
                        fprintf('  [WARMUP] Segment %d: all-zero "%s" — will write to warmup/\n', ...
                            si, warmup_ch);
                    end
                end
            end
        end
        fprintf('  [DIAG] warmup_mask after beacon: [%s]  n_real=%d\n', ...
            num2str(warmup_mask(:)'), n_segs - sum(warmup_mask));

        % Pre-mark short segments as warmup BEFORE ride-along uses n_real_segs.
        % This catches inter-session ERT-reset fragments where the beacon fired
        % during the gap (so beacon check didn't mark them), but they are too
        % short to be a real session (e.g. 26-KA's 27s fragment).
        seg_durs_all = diff([0; T_splits(:); ert.time(end)]);
        short_mask   = seg_durs_all < cfg.min_seg_s & ~warmup_mask;
        if any(short_mask)
            for si = 1 : n_segs
                if short_mask(si)
                    warmup_mask(si) = true;
                    fprintf('  [WARMUP-SHORT] Segment %d (%.0fs < %.0fs) — too short, pre-marked warmup\n', ...
                        si, seg_durs_all(si), cfg.min_seg_s);
                end
            end
        end

        % Duration-based warmup fallback: if beacon detection left too many real
        % segments, mark the shortest segment(s) < min_seg_s as warmup.
        % This catches inter-session outings where Lap_Number > 0.
        n_real_segs  = n_segs - sum(warmup_mask);

        % Ride-along detection: for explicitly listed cars, mark the leading
        % non-warmup segments as ride-along until real-seg count matches expected.
        % Positional rule: ride-along always occurs BEFORE the warmup (spin-up outing).
        if isfield(cfg, 'ridealong_car_nums') && ~isempty(cfg.ridealong_car_nums) && ...
                ~isempty(this_drv.car_num) && ...
                ismember(this_drv.car_num, cfg.ridealong_car_nums) && ...
                n_real_segs > numel(cfg.session_labels)
            n_extra = n_real_segs - numel(cfg.session_labels);
            fprintf('  [RIDEALONG] Car %s listed — marking %d leading segment(s) as ride-along\n', ...
                this_drv.car_num, n_extra);
            for si = 1 : n_segs
                if n_extra <= 0, break; end
                if ~warmup_mask(si)
                    warmup_mask(si) = true;
                    n_extra = n_extra - 1;
                    fprintf('  [WARMUP-RIDEALONG] Segment %d (%.0fs) — pre-warmup ride-along dropped\n', ...
                        si, seg_durs_all(si));
                end
            end
            n_real_segs = n_segs - sum(warmup_mask);
        end

        while n_real_segs > numel(cfg.session_labels)
            % Find shortest non-warmup segment
            candidate_si = find(~warmup_mask);
            [min_dur, min_loc] = min(seg_durs_all(candidate_si));
            if min_dur < cfg.min_seg_s
                si_to_mark = candidate_si(min_loc);
                warmup_mask(si_to_mark) = true;
                n_real_segs = n_real_segs - 1;
                fprintf('  [WARMUP-DUR] Segment %d (%.0fs < %.0fs) auto-marked as warmup\n', ...
                    si_to_mark, min_dur, cfg.min_seg_s);
            else
                break;  % shortest remaining segment is long — can't auto-resolve
            end
        end
        n_real_segs = n_segs - sum(warmup_mask);
        this_drv.n_warmup = sum(warmup_mask);

        % Read source header for rename — hoisted before the mismatch check so
        % passthrough copies also get rename_output applied (e.g. DEP_2026_Q14.ld).
        src_year_str = '';
        src_drv_tla  = '';
        if cfg.rename_output
            try
                hdr = motec_ld_info(INPUT_FILE, cfg.ecu_format);
                date_raw = strtrim(hdr.date);
                yr_tok = regexp(date_raw, '(\d{4})', 'tokens');
                for tk = 1:numel(yr_tok)
                    yr = str2double(yr_tok{tk}{1});
                    if yr >= 1990 && yr <= 2100
                        src_year_str = yr_tok{tk}{1};
                        break;
                    end
                end
                drv_raw = strtrim(hdr.driver);
                [~, ~, ~, ~, src_drv_tla] = resolve_driver_info(drv_raw, driver_map);
                if isempty(src_drv_tla)
                    [canon, ~, ~, ~] = resolve_driver_info(drv_raw, driver_map);
                    src_drv_tla = regexprep(strtrim(canon), '[^A-Za-z0-9]+', '_');
                    if ~isempty(src_drv_tla)
                        fprintf('  [WARN] No TLA for driver "%s" - using "%s".\n', drv_raw, src_drv_tla);
                    end
                end
            catch rename_err
                fprintf('  [WARN] rename_output: header read failed (%s) - using source filename.\n', ...
                    rename_err.message);
            end
            if isempty(src_year_str) || isempty(src_drv_tla)
                fprintf('  [WARN] rename_output: year="%s" TLA="%s" - using source filename.\n', ...
                    src_year_str, src_drv_tla);
            end
        end

        if n_real_segs ~= numel(cfg.session_labels)
            % Pass-through: exactly 1 real segment — infer session label from
            % filename tokens, then parent directory tokens, then default to
            % first session_label.  Also applies rename_output.
            if n_real_segs == 1 && sum(warmup_mask) == 0
                name_parts   = strsplit(src_name, '_');
                inferred_lbl = '';
                for sp = numel(name_parts) : -1 : 1
                    if ismember(name_parts{sp}, cfg.session_labels)
                        inferred_lbl = name_parts{sp};
                        break;
                    end
                end
                % Fall back: check parent directory name (forward order so
                % first matching label wins, e.g. Q14 from Q14_Q15_concat).
                if isempty(inferred_lbl)
                    [par_dir, ~, ~] = fileparts(INPUT_FILE);
                    [~, par_name, ~] = fileparts(par_dir);
                    dir_parts = strsplit(par_name, '_');
                    for sp = 1 : numel(dir_parts)
                        if ismember(dir_parts{sp}, cfg.session_labels)
                            inferred_lbl = dir_parts{sp};
                            break;
                        end
                    end
                end
                % Last resort: default to first session label
                if isempty(inferred_lbl)
                    inferred_lbl = cfg.session_labels{1};
                    fprintf('  [PASSTHROUGH] Cannot infer session — defaulting to "%s".\n', inferred_lbl);
                end
                fprintf('  [PASSTHROUGH] Session "%s" — copying.\n', inferred_lbl);
                pt_dir  = fullfile(cfg.output_dir, inferred_lbl);
                if cfg.rename_output && ~isempty(src_year_str) && ~isempty(src_drv_tla)
                    pt_file = fullfile(pt_dir, sprintf('%s_%s_%s.ld', src_drv_tla, src_year_str, inferred_lbl));
                else
                    pt_file = fullfile(pt_dir, [src_name src_ext]);
                end
                if ~isfolder(pt_dir), mkdir(pt_dir); end
                if ld_paths_equal(INPUT_FILE, pt_file)
                    fprintf('  [IN-PLACE] Source is already at destination — no copy needed.\n');
                elseif ~exist(pt_file, 'file') || cfg.overwrite
                    copyfile(INPUT_FILE, pt_file);
                    fprintf('  Copied to: %s\n', pt_file);
                else
                    fprintf('  [SKIP] Already exists: %s\n', pt_file);
                end
                csv_rows{end+1} = sprintf('%s,OK_PASSTHROUGH,%s,0,%.0f,%.0f,"%s",', ... %#ok<AGROW>
                    [src_name src_ext], inferred_lbl, ert.time(end), ert.time(end), pt_file);
                this_drv.proc_status = 'OK_PASSTHROUGH';
                this_drv.sessions_ok = inferred_lbl;
                drv_rows(end+1) = this_drv; %#ok<AGROW>
                n_ok = n_ok + 1;
                continue;
            end
            % Build diagnostic detail: split timestamps + per-segment durations
            seg_durations = diff([0; T_splits(:); ert.time(end)]);
            if ~isempty(T_splits)
                split_parts = cell(numel(T_splits), 1);
                for kk = 1 : numel(T_splits)
                    split_parts{kk} = sprintf('%.0fs', T_splits(kk));
                end
                split_str = ['splits@[' strjoin(split_parts, ',') ']'];
            else
                split_str = 'splits@[]';
            end
            dur_parts = cell(n_segs, 1);
            for si = 1 : n_segs
                if warmup_mask(si)
                    dur_parts{si} = sprintf('%.0fs[W]', seg_durations(si));
                else
                    dur_parts{si} = sprintf('%.0fs', seg_durations(si));
                end
            end
            dur_str = ['durs:[' strjoin(dur_parts, ',') ']'];
            skip_detail = sprintf('%d segs (%d warmup), expected %d | %s | %s', ...
                n_real_segs, sum(warmup_mask), numel(cfg.session_labels), split_str, dur_str);

            fprintf(['  [SKIP] %s\n' ...
                     '         Raw candidates: %d — adjust CONFIG and re-run.\n'], ...
                     skip_detail, numel(T_cand));
            csv_rows{end+1} = sprintf('%s,SKIP_MISMATCH_%dSEG,,,,,""%s"",',...  %#ok<AGROW>
                [src_name src_ext], n_real_segs, skip_detail);
            this_drv.skip_reason = skip_detail;
            this_drv.proc_status = 'SKIP_MISMATCH';
            drv_rows(end+1) = this_drv; %#ok<AGROW>
            n_fail = n_fail + 1;
            continue;
        end

        % =====================================================================
        %  PHASE 2 - Walk binary channel records
        % =====================================================================
        fprintf('--- Phase 2: Walk channel metadata records ---\n');
        try
            records = walk_channel_records(INPUT_FILE);
            fprintf('  Found %d channel records.\n', numel(records));
        catch err
            fprintf('  [ERROR] walk_channel_records failed: %s\n', err.message);
            err_safe = strrep(err.message, ',', ';');
            csv_rows{end+1} = sprintf('%s,ERROR_WALK_RECORDS,,,,,,"%s"', ... %#ok<AGROW>
                [src_name src_ext], err_safe);
            this_drv.proc_status = 'ERROR_WALK';
            drv_rows(end+1) = this_drv; %#ok<AGROW>
            n_fail = n_fail + 1;
            continue;
        end

        % =====================================================================
        %  PHASE 3 - Write one segment file per session
        % =====================================================================
        fprintf('--- Phase 3: Write segment files ---\n');

        seg_starts = [0;          T_splits(:)];
        seg_ends   = [T_splits(:); Inf       ];

        % Print full segment layout so snip boundaries are visible
        fprintf('  Segment layout (%d segs, warmup_mask=[%s]):\n', ...
            n_segs, num2str(warmup_mask(:)'));
        label_idx_pre = 0;
        for si_dbg = 1 : n_segs
            T_s_dbg = seg_starts(si_dbg);
            T_e_dbg = seg_ends(si_dbg);
            dur_dbg = seg_durs_all(si_dbg);
            if warmup_mask(si_dbg)
                lbl_dbg = 'WARMUP';
            else
                label_idx_pre = label_idx_pre + 1;
                if label_idx_pre <= numel(cfg.session_labels)
                    lbl_dbg = cfg.session_labels{label_idx_pre};
                else
                    lbl_dbg = '???';
                end
            end
            fprintf('    Seg %d: [%.1fs, %.1fs)  dur=%.0fs  → %s\n', ...
                si_dbg, T_s_dbg, T_e_dbg, dur_dbg, lbl_dbg);
        end

        label_idx  = 0;
        warmup_idx = 0;
        for i = 1 : n_segs

            is_warmup = warmup_mask(i);
            T_start   = seg_starts(i);
            T_end     = seg_ends(i);
            if is_warmup
                warmup_idx = warmup_idx + 1;
                if warmup_idx == 1
                    label = 'warmup';
                else
                    label = sprintf('warmup_%d', warmup_idx);
                end
                out_dir = fullfile(cfg.output_dir, 'warmup');
            else
                label_idx = label_idx + 1;
                label     = cfg.session_labels{label_idx};
                out_dir   = fullfile(cfg.output_dir, label);
            end
            if cfg.rename_output && ~isempty(src_year_str) && ~isempty(src_drv_tla)
                out_file = fullfile(out_dir, sprintf('%s_%s_%s.ld', src_drv_tla, src_year_str, label));
            else
                out_file = fullfile(out_dir, [src_name src_ext]);
            end

            fprintf('\n  Segment %d / %d : "%s"  [%.1f s, %.1f s)\n', ...
                i, n_segs, label, T_start, T_end);

            if ~isfolder(out_dir)
                mkdir(out_dir);
            end

            if exist(out_file, 'file') && ~cfg.overwrite
                % Compute duration of the new candidate segment
                if isinf(T_end)
                    t_end_new = ert.time(end);
                else
                    t_end_new = T_end;
                end
                dur_new = t_end_new - T_start;

                % Compare against the file already on disk; overwrite only
                % if the new segment is strictly longer (e.g. track session
                % vs short garage session that wrote the file first).
                dur_existing = get_ld_segment_duration(out_file, cfg.ert_names, cfg.ecu_format);

                if ~isnan(dur_existing) && dur_new > dur_existing
                    fprintf('  [OVERWRITE] New segment (%.0fs) > existing (%.0fs) — replacing: %s\n', ...
                        dur_new, dur_existing, out_file);
                    delete(out_file);  % fall through to write new file
                else
                    if isnan(dur_existing)
                        fprintf('  [SKIP] Could not read existing duration — keeping: %s\n', out_file);
                    else
                        fprintf('  [SKIP] Existing (%.0fs) >= new (%.0fs) — keeping: %s\n', ...
                            dur_existing, dur_new, out_file);
                    end
                    csv_rows{end+1} = sprintf('%s,SKIP_EXISTS,%s,%.1f,%.1f,%.1f,"%s",', ... %#ok<AGROW>
                        [src_name src_ext], label, T_start, t_end_new, dur_new, out_file);
                    sessions_ok_this_file{end+1} = label; %#ok<AGROW>
                    continue;
                end
            end

            % Copy, patch, shift header, write session strings
            fid = -1;
            try
                % Copy source file byte-exact
                copyfile(INPUT_FILE, out_file);
                fprintf('  Copied to: %s\n', out_file);

                % Open copy for in-place patching
                fid = fopen(out_file, 'r+b');
                if fid == -1
                    error('fopen failed on output file: %s', out_file);
                end

                % Patch each channel record: data_ptr + data_len
                n_patched = 0;
                for r = 1 : numel(records)
                    rec = records(r);
                    if rec.data_ptr == 0 || rec.data_len == 0 || rec.sample_rate == 0
                        continue;
                    end

                    bps     = datatype_bps(rec.datatype);
                    n_start = min(round(T_start * rec.sample_rate), rec.data_len);
                    if isinf(T_end)
                        n_end = rec.data_len;
                    else
                        n_end = min(rec.data_len, round(T_end * rec.sample_rate));
                    end

                    if n_end <= n_start
                        new_data_ptr = uint32(rec.data_ptr);
                        new_data_len = uint32(0);
                    else
                        new_data_ptr = uint32(rec.data_ptr + n_start * bps);
                        new_data_len = uint32(n_end - n_start);
                    end

                    fseek(fid, rec.meta_ptr + 8,  'bof');
                    fwrite(fid, typecast(new_data_ptr, 'uint8'), 'uint8');
                    fseek(fid, rec.meta_ptr + 12, 'bof');
                    fwrite(fid, typecast(new_data_len, 'uint8'), 'uint8');
                    n_patched = n_patched + 1;
                end
                fprintf('  Patched %d channel records.\n', n_patched);

                % Shift date/time header for segments 2+
                if i > 1
                    shift_header_datetime(fid, T_splits(i-1));
                end

                fclose(fid); fid = -1;

                % Patch session / venue / event header strings
                patch_ld_header(out_file, label, cfg.hol_venue, cfg.hol_event);
                fprintf('  Header: session="%s"  venue="%s"  event="%s"\n', ...
                    label, cfg.hol_venue, cfg.hol_event);
                if ~is_warmup
                    sessions_ok_this_file{end+1} = label; %#ok<AGROW>
                end

                % Accumulate report row
                if isinf(T_end)
                    t_end_s = ert.time(end); dur_s = t_end_s - T_start;
                else
                    t_end_s = T_end;         dur_s = T_end - T_start;
                end
                seg_status = 'OK';
                if is_warmup, seg_status = 'WARMUP'; end
                csv_rows{end+1} = sprintf('%s,%s,%s,%.1f,%.1f,%.1f,"%s",%d', ... %#ok<AGROW>
                    [src_name src_ext], seg_status, label, T_start, t_end_s, dur_s, out_file, n_patched);
                seg_entry.source_type = cfg.source_label;
                seg_entry.source_file = [src_name src_ext];
                seg_entry.driver      = this_drv.canonical;
                seg_entry.car_num     = this_drv.car_num;
                seg_entry.seg_idx     = i;
                seg_entry.session     = label;
                seg_entry.t_start     = T_start;
                seg_entry.t_end       = t_end_s;
                seg_entry.duration    = dur_s;
                seg_entry.is_warmup   = is_warmup;
                seg_entry.output_file = out_file;
                seg_rows{end+1} = seg_entry; %#ok<AGROW>

            catch err
                if fid ~= -1, fclose(fid); fid = -1; end %#ok<NASGU>
                fprintf('  [ERROR] Segment %d (%s): %s\n', i, label, err.message);
                err_safe = strrep(err.message, ',', ';');
                csv_rows{end+1} = sprintf('%s,ERROR_WRITE,%s,%.1f,,,"%s","%s"', ... %#ok<AGROW>
                    [src_name src_ext], label, T_start, out_file, err_safe);
            end

        end  % segment loop

        this_drv.proc_status = 'OK';
        this_drv.sessions_ok = strjoin(unique(sessions_ok_this_file), ';');
        drv_rows(end+1) = this_drv; %#ok<AGROW>
        n_ok = n_ok + 1;

    end  % file loop

end  % function split_ld_folder

% -------------------------------------------------------------------------
function dur_s = get_ld_segment_duration(filepath, ert_names, ecu_format)
% Read the ERT/uptime channel from an existing patched .ld file and return
% its time span.  Returns NaN on any failure.
    dur_s = NaN;
    try
        for k = 1 : numel(ert_names)
            d  = motec_ld_reader(filepath, {ert_names{k}}, ecu_format);
            fn = fieldnames(d);
            if ~isempty(fn)
                t = d.(fn{1}).time;
                if numel(t) >= 2
                    dur_s = t(end) - t(1);
                end
                return;
            end
        end
    catch
    end
end

% -------------------------------------------------------------------------
function [canonical, car_num, team_tla, status, drv_tla] = resolve_driver_info(raw_drv, driver_map)
% Lookup raw_drv against driverAlias entries. Returns canonical name,
% car number string, team TLA, and alias match status ('OK' / 'NOT_IN_ALIAS').
    canonical = raw_drv;
    car_num   = '';
    team_tla  = '';
    drv_tla   = '';
    status    = 'NOT_IN_ALIAS';
    if isempty(raw_drv) || isempty(driver_map)
        return;
    end
    raw_lower = lower(strtrim(raw_drv));
    keys = fieldnames(driver_map);
    for ki = 1 : numel(keys)
        entry = driver_map.(keys{ki});
        if any(strcmp(raw_lower, entry.aliases))
            canonical = entry.canonical;
            car_num   = entry.num;
            team_tla  = entry.team_tla;
            drv_tla   = entry.tla;
            status    = 'OK';
            return;
        end
    end
end

% -------------------------------------------------------------------------
function labels = resolve_session_label(raw, session_labels, session_aliases)
% Return all canonical SESSION_LABELS that raw resolves to (direct match + aliases).
% Returns {} if nothing matches — caller flags as UNEXPECTED_SESSION.
    labels = {};
    raw = strtrim(raw);
    % Direct exact match against SESSION_LABELS
    for si = 1 : numel(session_labels)
        if strcmpi(raw, session_labels{si})
            labels{end+1} = session_labels{si}; %#ok<AGROW>
        end
    end
    % Alias lookup
    if ~isempty(session_aliases)
        for ai = 1 : size(session_aliases, 1)
            canonical = session_aliases{ai, 1};
            aliases   = session_aliases{ai, 2};
            if ischar(aliases), aliases = {aliases}; end
            for ki = 1 : numel(aliases)
                if strcmpi(raw, strtrim(aliases{ki})) && ~any(strcmpi(canonical, labels))
                    labels{end+1} = canonical; %#ok<AGROW>
                end
            end
        end
    end
end

% -------------------------------------------------------------------------
function files = recursive_find_ld_local(folder)
% Find all .ld files in folder (top level only — no recursion).
% Split input is always a flat folder of concat output files.
    files = {};
    if ~isfolder(folder), return; end
    d = dir(fullfile(folder, '*.ld'));
    for i = 1 : numel(d)
        if ~startsWith(d(i).name, '._')
            files{end+1} = fullfile(folder, d(i).name); %#ok<AGROW>
        end
    end
end

% -------------------------------------------------------------------------
function tf = ld_paths_equal(p1, p2)
% Returns true if p1 and p2 resolve to the same file system path.
    try
        c1 = char(java.io.File(p1).getCanonicalPath());
        c2 = char(java.io.File(p2).getCanonicalPath());
        tf = strcmpi(c1, c2);
    catch
        n1 = lower(strrep(p1, '/', filesep));
        n2 = lower(strrep(p2, '/', filesep));
        tf = strcmp(n1, n2);
    end
end

% -------------------------------------------------------------------------
function records = walk_channel_records(filepath)
% Read the channel metadata linked list from a MoTeC .ld file.
% Returns a struct array with fields:
%   meta_ptr    — byte offset of this record in the file (0-indexed)
%   data_ptr    — byte offset of channel sample data
%   data_len    — number of samples
%   sample_rate — Hz
%   datatype    — 1=float16, 2=int16, 3=int32, 4=int16+pad or float32
%   name        — channel name string
%
% Record layout (0-indexed offsets within each 124-byte record):
%   +0x00  prev_ptr    (uint32)
%   +0x04  next_ptr    (uint32)
%   +0x08  data_ptr    (uint32)
%   +0x0C  n_samples   (uint32)
%   +0x10  sr_raw      (uint16)  sample-clock group ID
%   +0x12  unk1        (uint16)
%   +0x14  datatype    (uint16)
%   +0x16  sample_rate (uint16)  true Hz
%   +0x18  offset      (int16)
%   +0x1A  mul         (int16)
%   +0x1C  scale       (int16)
%   +0x1E  dec_places  (int16)
%   +0x20  name        (32 bytes, null-padded ASCII)

    fid = fopen(filepath, 'rb');
    if fid == -1, error('walk_channel_records: cannot open %s', filepath); end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);

    fseek(fid, 0x0008, 'bof');
    first_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    if ~isscalar(first_ptr) || first_ptr == 0 || first_ptr >= file_sz
        error('walk_channel_records: invalid first_meta_ptr in %s', filepath);
    end

    % Pre-allocate as 1×0 struct so the loop can grow it
    records = struct('meta_ptr',    {}, 'data_ptr',    {}, 'data_len', {}, ...
                     'sample_rate', {}, 'datatype',    {}, 'name',     {});

    current_ptr = first_ptr;
    n = 0;
    while current_ptr ~= 0 && current_ptr < file_sz

        fseek(fid, current_ptr, 'bof');

        fread(fid, 1, 'uint32=>double', 0, 'l');               % prev_ptr  (+0x00)
        next_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l'); % next_ptr  (+0x04)
        data_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l'); % data_ptr  (+0x08)
        data_len    = fread(fid, 1, 'uint32=>double', 0, 'l'); % n_samples (+0x0C)
        fread(fid, 1, 'uint16=>double', 0, 'l');               % sr_raw    (+0x10)
        fread(fid, 1, 'uint16=>double', 0, 'l');               % unk1      (+0x12)
        datatype    = fread(fid, 1, 'uint16=>double', 0, 'l'); % datatype  (+0x14)
        sample_rate = fread(fid, 1, 'uint16=>double', 0, 'l'); % Hz        (+0x16)
        fread(fid, 4, 'int16=>double',  0, 'l');               % off/mul/scale/dec (+0x18)
        name_raw    = fread(fid, 32, 'uint8=>double')';        % name      (+0x20)

        % Parse null-terminated name
        nul = find(name_raw == 0, 1);
        if ~isempty(nul) && nul > 1
            name_str = strtrim(char(name_raw(1:nul-1)));
        elseif isempty(nul)
            name_str = strtrim(char(name_raw));
        else
            name_str = '';
        end

        n = n + 1;
        records(n).meta_ptr    = current_ptr;
        records(n).data_ptr    = data_ptr;
        records(n).data_len    = data_len;
        records(n).sample_rate = sample_rate;
        records(n).datatype    = datatype;
        records(n).name        = name_str;

        current_ptr = next_ptr;

        if n > 5000
            warning('walk_channel_records: exceeded 5000 records — stopping.');
            break;
        end
    end
end

% -------------------------------------------------------------------------
function bps = datatype_bps(datatype)
% Bytes per sample for each MoTeC .ld datatype.
% Type 4 is 4 bytes regardless of ECU vs dash interpretation (int16+2pad or float32).
    switch datatype
        case 1,  bps = 2;   % float16 stored as uint16
        case 2,  bps = 2;   % int16
        case 3,  bps = 4;   % int32
        case 4,  bps = 4;   % int16+2pad (dash) or float32 (ECU) — same byte width
        otherwise
            warning('datatype_bps: unknown datatype %d — assuming 2 bytes/sample.', datatype);
            bps = 2;
    end
end

% -------------------------------------------------------------------------
function shift_header_datetime(fid, offset_s)
% Shift the session start date/time in the header of an already-open file
% by offset_s seconds.  Mirrors the logic in smp_shift_ld_time.m (inline
% to avoid an external file dependency).
%
% Header fields (ASCII strings):
%   0x005E  date  16 bytes  "DD/MM/YYYY"
%   0x007E  time  16 bytes  "HH:MM:SS"

    DATE_OFFSET = 0x5E;
    TIME_OFFSET = 0x7E;
    DATE_LEN    = 16;
    TIME_LEN    = 16;

    fseek(fid, DATE_OFFSET, 'bof');
    date_bytes = fread(fid, DATE_LEN, 'uint8=>double')';
    fseek(fid, TIME_OFFSET, 'bof');
    time_bytes = fread(fid, TIME_LEN, 'uint8=>double')';

    date_str = strtrim(char(date_bytes(date_bytes > 0)));
    time_str = strtrim(char(time_bytes(time_bytes > 0)));

    % Parse "DD/MM/YYYY HH:MM:SS" into a MATLAB datenum
    dt = [];
    try
        dt = datenum([strtrim(date_str) ' ' strtrim(time_str)], 'dd/mm/yyyy HH:MM:SS');
    catch
        try
            dt = datenum([strtrim(date_str) ' ' strtrim(time_str)]);
        catch
        end
    end

    if isempty(dt)
        fprintf('  [WARN] shift_header_datetime: cannot parse date="%s" time="%s" — skipping.\n', ...
            date_str, time_str);
        return;
    end

    dt_shifted    = dt + offset_s / 86400;   % datenum unit = days
    new_date_str  = datestr(dt_shifted, 'dd/mm/yyyy');
    new_time_str  = datestr(dt_shifted, 'HH:MM:SS');

    fprintf('  Date/time: "%s %s" -> "%s %s"  (+%.1f s)\n', ...
        date_str, time_str, new_date_str, new_time_str, offset_s);

    write_fixed_str(fid, DATE_OFFSET, new_date_str, DATE_LEN);
    write_fixed_str(fid, TIME_OFFSET, new_time_str, TIME_LEN);
end

% -------------------------------------------------------------------------
function write_fixed_str(fid, offset, str, field_len)
% Write a null-padded fixed-length ASCII string at byte offset (0-indexed).
    fseek(fid, offset, 'bof');
    bytes      = zeros(1, field_len, 'uint8');
    n          = min(numel(str), field_len);
    bytes(1:n) = uint8(str(1:n));
    fwrite(fid, bytes, 'uint8');
end

% -------------------------------------------------------------------------
function patch_ld_header(filepath, session_str, venue_str, event_str)
% Patch session (0x5E4 / 32 b), venue (0x15E / 64 b) and event/run
% (0x624 / 32 b) strings in a MoTeC .ld file in-place.
% Empty strings are silently skipped.
% (Same implementation as in smp_build_merge_map.m — local copy to avoid
%  cross-file dependency.)
    FIELDS = {hex2dec('5E4'), session_str, 32; ...
              hex2dec('15E'), venue_str,   64; ...
              hex2dec('624'), event_str,   32};

    fid = fopen(filepath, 'r+b');
    if fid == -1
        fprintf('  [WARN] patch_ld_header: cannot open %s\n', filepath);
        return;
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    for fi = 1 : size(FIELDS, 1)
        off = FIELDS{fi, 1};
        str = FIELDS{fi, 2};
        len = FIELDS{fi, 3};
        if isempty(str), continue; end
        bytes      = zeros(1, len, 'uint8');
        n          = min(numel(str), len - 1);
        bytes(1:n) = uint8(str(1:n));
        fseek(fid, off, 'bof');
        fwrite(fid, bytes, 'uint8');
    end
end