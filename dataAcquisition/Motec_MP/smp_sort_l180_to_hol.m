function smp_sort_l180_to_hol(cfg)
%% smp_sort_l180_to_hol(cfg)
% Sort raw L180 .ld files into HOL output folder with TLA-based naming.
%
% Raw L180 files have timestamp-based names (e.g. 20260621-241100000.ld).
% This function reads each file's internal MoTeC header to get the driver
% name, resolves it to a TLA via driverAlias.xlsx, and copies/moves the
% file to:
%   <l180_hol_dir>/<session>/TLA_YEAR_SESSION.ld
%
% Required cfg fields:
%   cfg.l180_input_dir    — folder containing raw L180 .ld files
%   cfg.l180_hol_dir      — root HOL output folder for L180
%   cfg.session           — session label e.g. 'Q19'
%   cfg.driver_alias_file — path to driverAlias.xlsx
%   cfg.ecu_format        — true = M1 ECU logger float32 (default: false)
%   cfg.overwrite         — true = replace existing output files
%   cfg.move              — true = move files, false = copy (default: false)
%   cfg.dry_run           — true = print actions without doing them

% =========================================================================
%  SETUP
% =========================================================================
INPUT_DIR         = cfg.l180_input_dir;
L180_HOL_DIR      = cfg.l180_hol_dir;
SESSION           = cfg.session;
DRIVER_ALIAS_FILE = cfg.driver_alias_file;
ECU_FORMAT        = isfield(cfg, 'ecu_format') && cfg.ecu_format;
OVERWRITE         = isfield(cfg, 'overwrite')  && cfg.overwrite;
DO_MOVE           = isfield(cfg, 'move')       && cfg.move;
DRY_RUN           = isfield(cfg, 'dry_run')    && cfg.dry_run;

% Date filter
if isfield(cfg, 'event_date') && ~isempty(cfg.event_date)
    EVENT_DATE_NUM    = datenum(cfg.event_date, 'yyyy-mm-dd');
else
    EVENT_DATE_NUM    = [];
end
DATE_TOL_DAYS = 0;
if isfield(cfg, 'date_tolerance_days')
    DATE_TOL_DAYS = cfg.date_tolerance_days;
end

% Infer year from input dir or use current year
yr_tok = regexp(INPUT_DIR, '(?:^|[\\/])(\d{4})(?:[\\/]|$)', 'tokens');
if ~isempty(yr_tok)
    YEAR = yr_tok{1}{1};
else
    YEAR = datestr(now, 'yyyy');
end

fprintf('=== smp_sort_l180_to_hol ===\n');
fprintf('  Input  : %s\n', INPUT_DIR);
fprintf('  Output : %s\n', fullfile(L180_HOL_DIR, SESSION));
fprintf('  Session: %s\n', SESSION);
fprintf('  Year   : %s\n', YEAR);
fprintf('  Mode   : %s\n', ternary(DO_MOVE, 'MOVE', 'COPY'));
if DRY_RUN
    fprintf('  [DRY RUN] No files will be moved or copied.\n');
end
fprintf('\n');

if ~isfolder(INPUT_DIR)
    error('smp_sort_l180_to_hol: l180_input_dir not found:\n  %s', INPUT_DIR);
end

% Load driver alias map
driver_map = [];
if ~isempty(DRIVER_ALIAS_FILE) && isfile(DRIVER_ALIAS_FILE)
    try
        driver_map = smp_driver_alias_load(DRIVER_ALIAS_FILE);
        fprintf('Loaded driver aliases: %d entries.\n\n', numel(fieldnames(driver_map)));
    catch err_da
        fprintf('[WARN] Could not load driver aliases: %s\n', err_da.message);
    end
end

% Output session subfolder
ses_out_dir = fullfile(L180_HOL_DIR, SESSION);
if ~isfolder(ses_out_dir) && ~DRY_RUN
    mkdir(ses_out_dir);
    fprintf('Created: %s\n\n', ses_out_dir);
end

% =========================================================================
%  SCAN INPUT
% =========================================================================
fprintf('--- Scanning input folder ---\n');

listing = dir(fullfile(INPUT_DIR, '*.ld'));
listing = listing(~[listing.isdir]);
listing = listing(~startsWith({listing.name}, '._'));

if isempty(listing)
    fprintf('[WARN] No .ld files found in: %s\n', INPUT_DIR);
    return;
end
fprintf('  Found %d .ld file(s)\n', numel(listing));

% --- Date filter (parse YYYYMMDD from filename prefix) ---
if ~isempty(EVENT_DATE_NUM)
    date_tok = regexp({listing.name}, '^(\d{8})', 'tokens', 'once');
    keep_mask = false(size(listing));
    for k = 1:numel(listing)
        if ~isempty(date_tok{k})
            file_date = datenum(date_tok{k}{1}, 'yyyymmdd');
            keep_mask(k) = abs(file_date - EVENT_DATE_NUM) <= DATE_TOL_DAYS;
        end
    end
    n_before = numel(listing);
    listing  = listing(keep_mask);
    fprintf('  Date filter (%s ±%dd): kept %d / %d file(s)\n', ...
        datestr(EVENT_DATE_NUM, 'yyyy-mm-dd'), DATE_TOL_DAYS, numel(listing), n_before);
end
fprintf('\n');

if isempty(listing)
    fprintf('[WARN] No .ld files remain after date filter.\n');
    return;
end

% =========================================================================
%  PROCESS EACH FILE
% =========================================================================
fprintf('--- Processing files ---\n');

n_ok      = 0;
n_skip    = 0;
n_unknown = 0;
n_fail    = 0;

for i = 1:numel(listing)
    src_path = fullfile(listing(i).folder, listing(i).name);
    [~, src_name, src_ext] = fileparts(listing(i).name);

    fprintf('  [%d/%d] %s\n', i, numel(listing), listing(i).name);

    % --- Read internal header ---
    try
        hdr     = motec_ld_info(src_path, ECU_FORMAT);
        raw_drv = strtrim(hdr.driver);
    catch err_hdr
        fprintf('    [ERROR] Cannot read header: %s\n', err_hdr.message);
        n_fail = n_fail + 1;
        continue;
    end

    % --- Session filter (from internal header) ---
    file_session = '';
    if isfield(hdr, 'session'), file_session = strtrim(hdr.session); end
    if ~isempty(file_session) && ~strcmpi(file_session, SESSION)
        fprintf('    [SKIP] Session mismatch: header="%s", expected="%s"\n', ...
            file_session, SESSION);
        n_skip = n_skip + 1;
        continue;
    end

    if isempty(raw_drv)
        fprintf('    [WARN] Empty driver name in header — skipping\n');
        n_unknown = n_unknown + 1;
        continue;
    end

    fprintf('    Header driver: "%s"  Session: "%s"\n', raw_drv, file_session);

    % --- Resolve TLA ---
    [~, ~, ~, ~, tla] = resolve_driver_info(raw_drv, driver_map);

    if isempty(tla)
        fprintf('    [WARN] No TLA found for "%s" — skipping\n', raw_drv);
        n_unknown = n_unknown + 1;
        continue;
    end

    fprintf('    TLA: %s\n', tla);

    % Use session label from header for filename (falls back to cfg SESSION if blank)
    file_ses_label = SESSION;
    if ~isempty(file_session), file_ses_label = file_session; end

    % --- Build output path ---
    out_name = sprintf('%s_%s_%s%s', tla, YEAR, file_ses_label, src_ext);
    out_path = fullfile(ses_out_dir, out_name);

    % --- Overwrite check ---
    if exist(out_path, 'file') && ~OVERWRITE
        fprintf('    [SKIP] Already exists: %s\n', out_name);
        n_skip = n_skip + 1;
        continue;
    end

    % --- Copy or move ---
    action = ternary(DO_MOVE, 'MOVE', 'COPY');
    fprintf('    [%s] -> %s\n', action, out_name);

    if ~DRY_RUN
        try
            if DO_MOVE
                movefile(src_path, out_path);
            else
                copyfile(src_path, out_path);
            end
            n_ok = n_ok + 1;
        catch err_cp
            fprintf('    [ERROR] %s failed: %s\n', action, err_cp.message);
            n_fail = n_fail + 1;
        end
    else
        n_ok = n_ok + 1;
    end
end

% =========================================================================
%  SUMMARY
% =========================================================================
fprintf('\n=== smp_sort_l180_to_hol complete ===\n');
fprintf('  Sorted  : %d\n', n_ok);
fprintf('  Skipped : %d  (already existed)\n', n_skip);
fprintf('  Unknown : %d  (no TLA match)\n', n_unknown);
fprintf('  Failed  : %d  (read/copy error)\n', n_fail);
if DRY_RUN
    fprintf('  [DRY RUN] No files were actually moved/copied.\n');
end
fprintf('\n');

end


% =========================================================================
%  LOCAL HELPERS
% =========================================================================

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end

function [canonical, car_num, team_tla, status, drv_tla] = resolve_driver_info(raw_drv, driver_map)
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