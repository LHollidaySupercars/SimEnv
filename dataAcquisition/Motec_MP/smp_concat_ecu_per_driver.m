function smp_concat_ecu_per_driver(cfg)
%% smp_concat_ecu_per_driver(cfg)
% Pre-processing step before smp_split_ecu_by_uptime.
%
% When a driver has multiple sequential .ld files in INPUT_DIR (e.g. the ECU
% was restarted mid-session), this concatenates them into a single file per
% driver before splitting.  Drivers with only one file are symlinked (zero
% storage cost) rather than copied.  S3 (dash logger) files are ignored.
%
% Binary concat strategy (no read→scale→write, no format conversion):
%   1. Copy file1 → output (exact byte copy — keeps header, all metadata,
%      all channel data blocks from file1).
%   2. For each channel that exists in both file1 and file2 (matched by
%      channel name): append [f1_bytes; f2_bytes] at EOF; patch data_ptr/data_len.
%   3. Repeat for file3, file4, ... (iterative).
%
% Required cfg fields:
%   cfg.ecu_input_dir     — folder of raw ECU .ld files
%   cfg.ecu_concat_dir    — output folder for concatenated files
%   cfg.ecu_format        — true = M1 ECU logger (float32)
%   cfg.driver_alias_file — path to driverAlias.xlsx ('' = skip)
%   cfg.max_overlap_s     — min allowed gap between files (negative = allow overlap)
%   cfg.overwrite         — true = re-process existing output files
%   cfg.session           — session label for output subfolder e.g. 'Q17'

% =========================================================================
%  SETUP
% =========================================================================
INPUT_DIR         = cfg.ecu_input_dir;
OUTPUT_DIR        = cfg.ecu_concat_dir;
ECU_FORMAT        = cfg.ecu_format;
DRIVER_ALIAS_FILE = cfg.driver_alias_file;
MAX_OVERLAP_S     = cfg.max_overlap_s;
OVERWRITE         = isfield(cfg, 'overwrite') && cfg.overwrite;

ECU_TLA_FILTER = {};
if isfield(cfg, 'ecu_tla_filter') && ~isempty(cfg.ecu_tla_filter)
    ECU_TLA_FILTER = lower(cfg.ecu_tla_filter);
    fprintf('  [fix_filter] ECU TLA filter active: %s\n', strjoin(ECU_TLA_FILTER, ','));
end

% Session label for output subfolder
if isfield(cfg, 'session') && ~isempty(cfg.session)
    ses_label = cfg.session;
elseif isfield(cfg, 'session_filter') && ~isempty(cfg.session_filter)
    ses_label = strjoin(cfg.session_filter, '_');
else
    ses_label = datestr(now, 'yyyymmdd');
end

fprintf('=== smp_concat_ecu_per_driver ===\n');
fprintf('  Input  : %s\n', INPUT_DIR);
fprintf('  Output : %s\n', OUTPUT_DIR);
fprintf('  Session: %s\n\n', ses_label);

if ~isfolder(INPUT_DIR)
    error('INPUT_DIR not found: %s', INPUT_DIR);
end

% Session output subfolder: ECU/HOL/<session>/
ses_out_dir = fullfile(OUTPUT_DIR, ses_label);
if ~isfolder(ses_out_dir)
    mkdir(ses_out_dir);
end

% Load driver alias map
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
%  PHASE 1 — SCAN & GROUP FILES BY DRIVER
%  S3 (dash logger) files are skipped — only S1 (ECU) files processed.
%  HOL subfolders are excluded from scan to avoid reprocessing outputs.
% =========================================================================
fprintf('\n--- Phase 1: Scan and group files ---\n');

ld_files = recursive_find_ld(INPUT_DIR);
if isempty(ld_files)
    fprintf('[WARN] No .ld files found in %s\n', INPUT_DIR);
    return;
end
fprintf('  Found %d .ld file(s) (before S3 filter).\n', numel(ld_files));

file_info = struct('path',{},'group_key',{},'datetime_num',{},'datetime_str',{},'uptime_start',{},'uptime_end',{});

for fi = 1 : numel(ld_files)
    fp = ld_files{fi};
    [~, fn, ext] = fileparts(fp);

    % Skip S3 (dash logger) files — only S1 ECU files belong here
    prefix = regexp(fn, '^([^_]+)', 'match', 'once');
    if strcmpi(prefix, 'S3')
        fprintf('  [SKIP] %s — S3 dash logger prefix\n', [fn ext]);
        continue;
    end

    % Defaults in case header read fails
    group_key    = [fn ext];
    dt_num       = 0;
    dt_str       = '';
    uptime_s     = NaN;
    uptime_end_s = NaN;

    try
        hdr     = motec_ld_info(fp, false);
        raw_drv = strtrim(hdr.driver);

        % Prefer TLA > canonical > raw driver as group key
        [canon, ~, ~, ~, tla] = resolve_driver_info(raw_drv, driver_map);
        if ~isempty(tla)
            drv_key = tla;
        elseif ~isempty(canon)
            drv_key = canon;
        elseif ~isempty(raw_drv)
            drv_key = raw_drv;
        else
            drv_key = fn;
        end

        % Prepend logger prefix (S1) to keep concurrent loggers separate
        if ~isempty(prefix)
            group_key = [prefix '_' drv_key];
        else
            group_key = drv_key;
        end

        dt_num       = parse_ld_datetime(hdr.date, hdr.time);
        dt_str       = sprintf('%s %s', strtrim(hdr.date), strtrim(hdr.time));
        uptime_s     = read_first_ert_sample(fp, ECU_FORMAT);
        uptime_end_s = read_last_ert_sample(fp, ECU_FORMAT);

        fprintf('  %s  |  group: "%s"  |  %s  |  ERT: %.1f -> %.1f\n', ...
            [fn ext], group_key, dt_str, uptime_s, uptime_end_s);
    catch err
        fprintf('  [WARN] Cannot read header of %s: %s\n', [fn ext], err.message);
    end

    file_info(end+1) = struct( ...   %#ok<AGROW>
        'path',         fp,          ...
        'group_key',    group_key,   ...
        'datetime_num', dt_num,      ...
        'datetime_str', dt_str,      ...
        'uptime_start', uptime_s,    ...
        'uptime_end',   uptime_end_s);
end

if isempty(file_info)
    fprintf('[WARN] No ECU files remaining after S3 filter.\n');
    return;
end

all_drivers = unique({file_info.group_key});
fprintf('\n  Unique ECU driver groups: %d\n', numel(all_drivers));

% =========================================================================
%  PHASE 2 — CONCAT OR SYMLINK PER DRIVER
% =========================================================================
fprintf('\n--- Phase 2: Concat or symlink ---\n');

n_symlink = 0;
n_concat  = 0;
n_skip    = 0;
n_fail    = 0;

for di = 1 : numel(all_drivers)
    drv = all_drivers{di};

    % Skip S3 groups (belt-and-suspenders — Phase 1 should have excluded them)
    drv_prefix = regexp(drv, '^([^_]+)', 'match', 'once');
    if strcmpi(drv_prefix, 'S3')
        continue;
    end

    mask  = strcmp({file_info.group_key}, drv);
    group = file_info(mask);

    % Apply TLA filter
    if ~isempty(ECU_TLA_FILTER)
        drv_tla_part = regexp(drv, '[^_]+$', 'match', 'once');
        if ~ismember(lower(drv_tla_part), ECU_TLA_FILTER) && ~ismember(lower(drv), ECU_TLA_FILTER)
            fprintf('\n  [SKIP] "%s" not in fix_filter\n', drv);
            continue;
        end
    end

    % Sort by header datetime (wall-clock order)
    dt_vals = [group.datetime_num];
    dt_vals(isnan(dt_vals)) = Inf;
    [~, order] = sort(dt_vals);
    group = group(order);

    % Build output filename: TLA_YYYY_SESSION.ld
    [~, ~, first_ext] = fileparts(group(1).path);
    tla_part = regexprep(drv, '^[^_]+_', '');   % 'S1_MOS' -> 'MOS'

    if group(1).datetime_num > 0
        ecu_yr = datestr(group(1).datetime_num, 'yyyy');
    else
        ecu_yr = datestr(now, 'yyyy');
    end

    hol_stem = sprintf('%s_%s_%s', tla_part, ecu_yr, ses_label);
    out_file = fullfile(ses_out_dir, [hol_stem first_ext]);

    fprintf('\n  Driver: "%s"  (%d file(s))  ->  %s\n', drv, numel(group), [hol_stem first_ext]);
    for k = 1 : numel(group)
        [~, fn, ex] = fileparts(group(k).path);
        fprintf('    [%d] %s  (%s)  ERT: %.1f\n', k, [fn ex], group(k).datetime_str, group(k).uptime_start);
    end

    % Check overwrite
    if isfile(out_file) && ~OVERWRITE
        fprintf('  -> Exists (skip): %s\n', out_file);
        n_skip = n_skip + 1;
        continue;
    end

    % ---- Single file: symlink instead of copy ----
    if numel(group) == 1
        make_symlink_or_copy(group(1).path, out_file);
        n_symlink = n_symlink + 1;
        continue;
    end

    % ---- Multi-file: build concat list with ERT/overlap deduplication ----
    SESSION_SPLIT_S = 3600;

    files_to_concat = {};
    acc_ert_min = NaN;
    acc_ert_max = NaN;
    acc_dt_num  = NaN;

    for k = 1 : numel(group)
        f = group(k);
        [~, fn_k, ex_k] = fileparts(f.path);
        label_k = [fn_k ex_k];

        if isnan(acc_dt_num)
            is_new_epoch = true;
            gap_wc = 0;
        else
            gap_wc   = (f.datetime_num - acc_dt_num) * 86400;
            ecu_reset = ~isnan(f.uptime_start) && ~isnan(acc_ert_max) && ...
                        f.uptime_start < 60 && acc_ert_max > 600;
            is_new_epoch = (gap_wc > SESSION_SPLIT_S) || ecu_reset;
        end

        if is_new_epoch
            files_to_concat{end+1} = f.path; %#ok<AGROW>
            acc_ert_min = f.uptime_start;
            acc_ert_max = f.uptime_end;
            acc_dt_num  = f.datetime_num;
            if k == 1
                fprintf('    [KEEP] %s  (base, ERT %.0f->%.0f)\n', label_k, f.uptime_start, f.uptime_end);
            else
                fprintf('    [KEEP] %s  (new epoch, gap=%.0fs, ERT %.0f->%.0f)\n', ...
                    label_k, gap_wc, f.uptime_start, f.uptime_end);
            end
            continue;
        end

        % Subset check: skip if ERT fully within accumulated range
        ert_known = ~isnan(f.uptime_start) && ~isnan(f.uptime_end) && ...
                    ~isnan(acc_ert_min)    && ~isnan(acc_ert_max);
        if ert_known && f.uptime_start >= acc_ert_min && f.uptime_end <= acc_ert_max
            fprintf('    [SKIP] %s  (ERT %.0f->%.0f subset of acc %.0f->%.0f)\n', ...
                label_k, f.uptime_start, f.uptime_end, acc_ert_min, acc_ert_max);
            continue;
        end

        % Wall-clock overlap guard
        if gap_wc < MAX_OVERLAP_S
            fprintf('    [SKIP] %s  (wall-clock gap=%.0fs < %.0fs)\n', ...
                label_k, gap_wc, MAX_OVERLAP_S);
            continue;
        end

        % Include
        if ~isnan(f.uptime_start) && ~isnan(acc_ert_max)
            if f.uptime_start >= acc_ert_max
                ert_note = sprintf('ERT +%.0fs', f.uptime_start - acc_ert_max);
            else
                ert_note = sprintf('ERT RESET %.0f->%.0f', acc_ert_max, f.uptime_start);
            end
        else
            ert_note = 'ERT unknown';
        end
        fprintf('    [KEEP] %s  (gap=%.0fs, %s)\n', label_k, gap_wc, ert_note);

        files_to_concat{end+1} = f.path; %#ok<AGROW>
        if ~isnan(f.uptime_start), acc_ert_min = min(acc_ert_min, f.uptime_start); end
        if ~isnan(f.uptime_end),   acc_ert_max = max(acc_ert_max, f.uptime_end);   end
        acc_dt_num = f.datetime_num;
    end

    if numel(files_to_concat) == 0
        fprintf('  [WARN] All files subset-skipped for "%s" — nothing written.\n', drv);
        n_fail = n_fail + 1;
    elseif numel(files_to_concat) == 1
        % After deduplication only one file remains — symlink it
        make_symlink_or_copy(files_to_concat{1}, out_file);
        n_symlink = n_symlink + 1;
    else
        fprintf('  -> Concatenating %d/%d files...\n', numel(files_to_concat), numel(group));
        try
            concat_ld_files(files_to_concat{1}, files_to_concat(2:end), out_file);
            fprintf('  -> Concat OK : %s\n', out_file);
            n_concat = n_concat + 1;
        catch err
            fprintf('  [ERROR] Concat failed for "%s": %s\n', drv, err.message);
            n_fail = n_fail + 1;
        end
    end
end

fprintf('\n=== Done  |  %d symlinked  |  %d concatenated  |  %d skipped  |  %d failed ===\n', ...
    n_symlink, n_concat, n_skip, n_fail);
fprintf('ECU concat output: %s\n', ses_out_dir);

end  % function smp_concat_ecu_per_driver


% =========================================================================
%  LOCAL FUNCTIONS
% =========================================================================

% -------------------------------------------------------------------------
function make_symlink_or_copy(src, dst)
% Symlink src -> dst (zero storage cost). Falls back to copy on failure.
    if isfile(dst), delete(dst); end
    [status, msg] = system(sprintf('ln -s "%s" "%s"', src, dst));
    if status == 0
        fprintf('  -> Symlinked : %s\n', dst);
    else
        fprintf('  [WARN] Symlink failed (%s) — falling back to copy\n', strtrim(msg));
        try
            copyfile(src, dst, 'f');
            fprintf('  -> Copied    : %s\n', dst);
        catch err
            fprintf('  [ERROR] Copy also failed: %s\n', err.message);
        end
    end
end

% -------------------------------------------------------------------------
function concat_ld_files(file1, extra_files, output_file)
% Concatenate file1 with each of extra_files{:} into output_file.
    if ischar(extra_files)
        extra_files = {extra_files};
    end

    [ok, msg] = copyfile(file1, output_file, 'f');
    if ~ok
        error('copyfile failed for "%s": %s', file1, msg);
    end
    fprintf('    Copied file1 -> output (%s)\n', format_bytes(get_file_bytes(output_file)));

    for ki = 1 : numel(extra_files)
        file_k = extra_files{ki};
        [~, fn, ex] = fileparts(file_k);
        fprintf('    Appending file %d: %s\n', ki + 1, [fn ex]);
        append_ld_to_output(output_file, file_k);
        fprintf('    Output size after append: %s\n', format_bytes(get_file_bytes(output_file)));
    end
end

% -------------------------------------------------------------------------
function append_ld_to_output(output_file, source_file)
% Append all matching channels from source_file onto output_file.

    recs_out = walk_channel_records_local(output_file);
    recs_src = walk_channel_records_local(source_file);

    if isempty(recs_out) || isempty(recs_src)
        error('append_ld_to_output: no channel records found.');
    end

    src_map = containers.Map('KeyType','char','ValueType','any');
    for k = 1 : numel(recs_src)
        nm = lower(strtrim(recs_src(k).name));
        if ~isempty(nm)
            src_map(nm) = recs_src(k);
        end
    end

    fid_out = fopen(output_file, 'r+b');
    if fid_out == -1, error('Cannot open for write: %s', output_file); end
    fid_src = fopen(source_file, 'rb');
    if fid_src == -1, fclose(fid_out); error('Cannot open source: %s', source_file); end

    n_appended = 0;
    n_skipped  = 0;
    n_src_only = 0;

    patch_mptr = zeros(numel(recs_out), 1);
    patch_dptr = zeros(numel(recs_out), 1, 'uint32');
    patch_dlen = zeros(numel(recs_out), 1, 'uint32');
    n_patches  = 0;

    for k = 1 : numel(recs_out)
        rec_out = recs_out(k);
        if rec_out.data_ptr == 0 || rec_out.data_len == 0 || rec_out.datatype == 0
            continue;
        end

        nm = lower(strtrim(rec_out.name));
        if ~isKey(src_map, nm)
            n_skipped = n_skipped + 1;
            continue;
        end

        rec_src = src_map(nm);
        if rec_src.data_ptr == 0 || rec_src.data_len == 0
            n_skipped = n_skipped + 1;
            continue;
        end

        bps = ld_datatype_bps(rec_out.datatype);
        n1  = rec_out.data_len;
        n2  = rec_src.data_len;

        fseek(fid_out, rec_out.data_ptr, 'bof');
        buf1 = fread(fid_out, n1 * bps, '*uint8');

        fseek(fid_src, rec_src.data_ptr, 'bof');
        buf2 = fread(fid_src, n2 * bps, '*uint8');

        if numel(buf1) ~= n1 * bps || numel(buf2) ~= n2 * bps
            fprintf('    [WARN] Short read for channel "%s" — skipping\n', rec_out.name);
            n_skipped = n_skipped + 1;
            continue;
        end

        fseek(fid_out, 0, 'eof');
        new_data_ptr = ftell(fid_out);
        fwrite(fid_out, [buf1; buf2], 'uint8');

        n_patches = n_patches + 1;
        patch_mptr(n_patches) = rec_out.meta_ptr;
        patch_dptr(n_patches) = uint32(new_data_ptr);
        patch_dlen(n_patches) = uint32(n1 + n2);

        n_appended = n_appended + 1;
    end

    fclose(fid_out);
    fclose(fid_src);

    % Pass 2: patch channel metadata
    fid_patch = fopen(output_file, 'r+b');
    if fid_patch == -1, error('Cannot reopen for patching: %s', output_file); end
    for k = 1 : n_patches
        fseek(fid_patch, patch_mptr(k) + 8, 'bof');
        fwrite(fid_patch, typecast([patch_dptr(k), patch_dlen(k)], 'uint8'), 'uint8');
    end
    fclose(fid_patch);

    for k = 1 : numel(recs_src)
        if ~any(strcmpi({recs_out.name}, recs_src(k).name))
            n_src_only = n_src_only + 1;
        end
    end

    fprintf('      Channels appended: %d  |  skipped: %d  |  source-only: %d\n', ...
        n_appended, n_skipped, n_src_only);
end

% -------------------------------------------------------------------------
function records = walk_channel_records_local(filepath)
% Read the channel metadata linked list from a MoTeC .ld file.
    records = struct('meta_ptr',{},'data_ptr',{},'data_len',{}, ...
                     'sample_rate',{},'datatype',{},'name',{});
    fid = fopen(filepath, 'rb');
    if fid == -1, error('walk_channel_records_local: cannot open %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);

    fseek(fid, 0x0008, 'bof');
    first_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

    % Guard against empty read (corrupt/truncated file)
    if ~isscalar(first_ptr) || first_ptr == 0 || first_ptr >= file_sz
        warning('walk_channel_records_local: invalid first_meta_ptr in %s', filepath);
        return;
    end

    current_ptr = first_ptr;
    n = 0;
    while current_ptr ~= 0 && current_ptr < file_sz
        fseek(fid, current_ptr, 'bof');

        fread(fid, 1, 'uint32=>double', 0, 'l');               % prev_ptr
        next_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_len    = fread(fid, 1, 'uint32=>double', 0, 'l');
        fread(fid, 1, 'uint16=>double', 0, 'l');               % sr_raw
        fread(fid, 1, 'uint16=>double', 0, 'l');               % unk1
        datatype    = fread(fid, 1, 'uint16=>double', 0, 'l');
        sample_rate = fread(fid, 1, 'uint16=>double', 0, 'l');
        fread(fid, 4, 'int16=>double',  0, 'l');               % offset/mul/scale/dec
        name_raw    = fread(fid, 32, 'uint8=>double')';

        nul = find(name_raw == 0, 1);
        if ~isempty(nul) && nul > 1
            name_str = strtrim(char(name_raw(1:nul-1)));
        elseif isempty(nul)
            name_str = strtrim(char(name_raw));
        else
            name_str = '';
        end

        % Guard against bad next_ptr
        if ~isscalar(next_ptr)
            break;
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
            warning('walk_channel_records_local: exceeded 5000 records — stopping.');
            break;
        end
    end
end

% -------------------------------------------------------------------------
function bps = ld_datatype_bps(datatype)
    switch datatype
        case 1,  bps = 2;
        case 2,  bps = 2;
        case 3,  bps = 4;
        case 4,  bps = 4;
        otherwise
            warning('ld_datatype_bps: unknown datatype %d — assuming 2.', datatype);
            bps = 2;
    end
end

% -------------------------------------------------------------------------
function dt_num = parse_ld_datetime(date_str, time_str)
    dt_num = 0;
    try
        d = strtrim(date_str);
        t = strtrim(time_str);
        if isempty(d), return; end
        dt_num = datenum([d ' ' t], 'dd/mm/yyyy HH:MM:SS');
    catch
        try
            dt_num = datenum(strtrim(date_str), 'dd/mm/yyyy');
        catch
        end
    end
end

% -------------------------------------------------------------------------
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

% -------------------------------------------------------------------------
function files = recursive_find_ld(folder)
% Find all .ld files recursively, skipping HOL subfolders to avoid
% reprocessing previously written output files.
    files = {};
    if ~isfolder(folder), return; end
    d = dir(fullfile(folder, '*.ld'));
    for i = 1 : numel(d)
        if ~startsWith(d(i).name, '._')
            files{end+1} = fullfile(folder, d(i).name); %#ok<AGROW>
        end
    end
    sub = dir(folder);
    for i = 1 : numel(sub)
        if sub(i).isdir && sub(i).name(1) ~= '.' && ~strcmpi(sub(i).name, 'HOL')
            files = [files, recursive_find_ld(fullfile(folder, sub(i).name))]; %#ok<AGROW>
        end
    end
end

% -------------------------------------------------------------------------
function n = get_file_bytes(filepath)
    d = dir(filepath);
    if isempty(d), n = 0; return; end
    n = d.bytes;
end

% -------------------------------------------------------------------------
function s = format_bytes(n)
    if n >= 1e9,     s = sprintf('%.2f GB', n/1e9);
    elseif n >= 1e6, s = sprintf('%.1f MB', n/1e6);
    elseif n >= 1e3, s = sprintf('%.0f KB', n/1e3);
    else,            s = sprintf('%d B', n);
    end
end

% -------------------------------------------------------------------------
function val = read_first_ert_sample(filepath, ecu_format)
    val = NaN;
    ERT_NAMES = {'ecu_uptime', 'ecu.uptime'};
    try
        recs = walk_channel_records_local(filepath);
    catch
        return;
    end
    if isempty(recs), return; end
    rec = [];
    for k = 1 : numel(recs)
        nm = lower(strtrim(recs(k).name));
        if any(strcmp(nm, ERT_NAMES)) && recs(k).data_ptr > 0 && recs(k).data_len > 0
            rec = recs(k);
            break;
        end
    end
    if isempty(rec), return; end
    if rec.datatype == 0, return; end
    fid = fopen(filepath, 'rb');
    if fid == -1, return; end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fseek(fid, rec.data_ptr, 'bof');
    if ecu_format
        raw = fread(fid, 1, 'float32=>double', 0, 'l');
    else
        raw = fread(fid, 1, 'int16=>double', 0, 'l');
    end
    if ~isempty(raw), val = raw; end
end

% -------------------------------------------------------------------------
function val = read_last_ert_sample(filepath, ecu_format)
    val = NaN;
    ERT_NAMES = {'ecu_uptime', 'ecu.uptime'};
    try
        recs = walk_channel_records_local(filepath);
    catch
        return;
    end
    if isempty(recs), return; end
    rec = [];
    for k = 1 : numel(recs)
        nm = lower(strtrim(recs(k).name));
        if any(strcmp(nm, ERT_NAMES)) && recs(k).data_ptr > 0 && recs(k).data_len > 0
            rec = recs(k);
            break;
        end
    end
    if isempty(rec), return; end
    if rec.datatype == 0, return; end
    bps         = ld_datatype_bps(rec.datatype);
    last_offset = rec.data_ptr + (rec.data_len - 1) * bps;
    fid = fopen(filepath, 'rb');
    if fid == -1, return; end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fseek(fid, last_offset, 'bof');
    if ecu_format
        raw = fread(fid, 1, 'float32=>double', 0, 'l');
    else
        raw = fread(fid, 1, 'int16=>double', 0, 'l');
    end
    if ~isempty(raw), val = raw; end
end