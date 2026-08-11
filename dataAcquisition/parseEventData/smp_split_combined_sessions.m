function [csv_rows, n_ok, n_skip, n_fail] = smp_split_combined_sessions(cfg)
%% smp_split_combined_sessions(cfg)
% Phase 0 — find raw .ld files whose INTERNAL HEADER session field is
% actually two (or more) sessions joined together (e.g. "P01_P02"), and
% split each one into its constituent sessions using an interactive
% visual tool.
%
% This runs before any concat step, so file naming is still whatever the
% raw logger produced (e.g. "20260307-243060003.ld") — the combined
% session name lives in the MoTeC header (hdr.session via motec_ld_info),
% exactly like smp_sort_l180_to_hol already reads it. Filenames are NOT
% matched against a pattern.
%
% Unlike smp_split_ecu_by_uptime (which auto-splits on ERT gaps/resets),
% this is for the case where the session boundary is NOT a clean ERT
% gap — e.g. two practice sessions run back-to-back with no power cycle
% in between, so the operator needs to pick the boundary by eye.
%
% Required cfg fields:
%   cfg.combined_input_dir     — folder to scan for combined-session .ld
%                                files (typically cfg.td_input_dir /
%                                _TeamData, or an ECU / L180 raw folder)
%   cfg.combined_session_names — cell array of exact header session strings
%                                that represent a combined session, e.g.
%                                {'P01_P02'}. Each entry is split on '_' to
%                                get the individual output labels, in
%                                order, e.g. 'P01_P02' -> {'P01','P02'}.
%                                Add more entries as new combos turn up.
%   cfg.split_aux_ch            — secondary channel name for visual context,
%                                default 'Ground_Speed' (set '' to omit)
%   cfg.ert_names               — cell array of ERT channel candidates
%                                (default {'ECU_Uptime'})
%   cfg.ecu_format              — true = M1 ECU logger float32 (default false)
%   cfg.hol_venue               — venue string patched into output headers
%   cfg.hol_event               — event string patched into output headers
%   cfg.overwrite               — true = overwrite existing output files
%   cfg.split_always_review     — true = always open the visual split tool
%                                for every matching file, even if its
%                                outputs already exist. Still respects
%                                cfg.overwrite for whether anything
%                                actually gets (re)written — with
%                                overwrite=false this just lets you
%                                review/adjust without touching disk;
%                                the per-file write step will still skip
%                                and tell you nothing was written.
%   cfg.min_gap_s               — used only to seed the auto-suggested marker
%   cfg.split_min_file_mb       — minimum file size in MB to process
%                                (default 10; smaller files — garage blips,
%                                truncated logs — are skipped)
%   cfg.driver_alias_file       — path to driverAlias.xlsx (optional). If
%                                provided, resolves header driver -> canonical
%                                name / car number / team TLA for display in
%                                the console and the split tool's title bar.
%   cfg.split_data_type         — '' (default) or 'L180'. Controls output
%                                naming/location convention:
%                                  default: sibling folder next to
%                                    combined_input_dir, original filename
%                                    kept as-is, e.g.
%                                    E:\...\ECU\P01_P02\file.ld ->
%                                    E:\...\ECU\P01\file.ld
%                                  'L180': SAME folder as the input, with
%                                    the filename suffixed by label
%                                    instead of a new subfolder — L180
%                                    files land flat alongside genuine
%                                    single-session files already in that
%                                    folder, and Phase 5a
%                                    (smp_sort_l180_to_hol) scans that
%                                    folder non-recursively, e.g.
%                                    E:\...\L180\file.ld ->
%                                    E:\...\L180\file_P01.ld +
%                                    E:\...\L180\file_P02.ld
%
% Output files are written to sibling folders next to combined_input_dir,
% one per label, preserving the original filename:
%   <combined_input_dir>/../<label>/<original_filename>.ld
% e.g.  E:\2026\E08_PER\ECU\P01_P02\20260307-243060003.ld  (header "P01_P02")
%    -> E:\2026\E08_PER\ECU\P01\20260307-243060003.ld
%    -> E:\2026\E08_PER\ECU\P02\20260307-243060003.ld
% Each output file's header session field is patched to its own label
% (P01 / P02), so downstream steps (smp_concat_teamdata etc, which filter
% by cfg.session_filter) treat them as normal single-session files.
%
% Returns a CSV report (cell array of strings) plus ok/skip/fail counts.

% =========================================================================
%  RESOLVE CONFIG
% =========================================================================
INPUT_DIR       = cfg.combined_input_dir;
SESSION_NAMES   = cfg.combined_session_names;   % cell array, e.g. {'P01_P02'}
ECU_FORMAT      = isfield(cfg, 'ecu_format') && cfg.ecu_format;
HOL_VENUE       = cfg.hol_venue;
HOL_EVENT       = cfg.hol_event;
OVERWRITE       = isfield(cfg, 'overwrite') && cfg.overwrite;
AUX_CH          = cfg.channel;;
if isfield(cfg, 'split_aux_ch'), AUX_CH = cfg.split_aux_ch; end
AUX_LABEL       = 'Ground Speed';

if isempty(SESSION_NAMES)
    fprintf('[INFO] cfg.combined_session_names is empty — Phase 0 has nothing to do.\n');
    csv_rows = {'SourceFile,Status,Labels,SplitTime_s,OutputFileA,OutputFileB'};
    n_ok = 0; n_skip = 0; n_fail = 0;
    return;
end

if isfield(cfg, 'ert_names') && ~isempty(cfg.ert_names)
    ERT_NAMES = cfg.ert_names;
else
    ERT_NAMES = {'ECU_Uptime'};
end

MIN_GAP_S = 60;
if isfield(cfg, 'min_gap_s'), MIN_GAP_S = cfg.min_gap_s; end

MIN_FILE_BYTES = 10 * 1024 * 1024;   % 10 MB default
if isfield(cfg, 'split_min_file_mb'), MIN_FILE_BYTES = cfg.split_min_file_mb * 1024 * 1024; end

DATA_TYPE = '';
if isfield(cfg, 'split_data_type'), DATA_TYPE = cfg.split_data_type; end

ALWAYS_REVIEW = isfield(cfg, 'split_always_review') && cfg.split_always_review;

% ---- Load driver alias map (optional — for display only) ----
driver_map = [];
if isfield(cfg, 'driver_alias_file') && ~isempty(cfg.driver_alias_file) && isfile(cfg.driver_alias_file)
    try
        driver_map = smp_driver_alias_load(cfg.driver_alias_file);
        fprintf('  Loaded driver aliases: %d entries.\n', numel(fieldnames(driver_map)));
    catch err_da
        fprintf('  [WARN] Could not load driver aliases: %s\n', err_da.message);
    end
end

csv_rows = {'SourceFile,Status,Labels,SplitTime_s,OutputFileA,OutputFileB'};
n_ok = 0; n_skip = 0; n_fail = 0;

if ~isfolder(INPUT_DIR)
    warning('smp_split_combined_sessions: input dir not found:\n  %s', INPUT_DIR);
    return;
end

fprintf('\n=== PHASE 0 — Split combined sessions ===\n');
fprintf('  Scanning        : %s\n', INPUT_DIR);
fprintf('  Combined names  : %s\n\n', strjoin(SESSION_NAMES, ', '));

listing = dir(fullfile(INPUT_DIR, '**', '*.ld'));
listing = listing(~[listing.isdir]);
listing = listing(~startsWith({listing.name}, '._'));

if isempty(listing)
    fprintf('[INFO] No .ld files found in %s\n', INPUT_DIR);
    return;
end

for fi = 1 : numel(listing)
    src_path = fullfile(listing(fi).folder, listing(fi).name);
    [~, src_name, src_ext] = fileparts(listing(fi).name);

    % Skip S3 files — same convention as smp_split_ecu_by_uptime
    if strncmpi(src_name, 'S3', 2)
        fprintf('  [SKIP] %s: filename starts with "S3" — omitted by config.\n', ...
            [src_name src_ext]);
        continue;
    end

    % Skip files under the minimum size threshold (garage/warmup blips,
    % truncated logs, etc — not worth visualising or splitting)
    if listing(fi).bytes < MIN_FILE_BYTES
        fprintf('  [SKIP] %s: %.1f MB < %.0f MB minimum.\n', ...
            [src_name src_ext], listing(fi).bytes/1e6, MIN_FILE_BYTES/1e6);
        continue;
    end

    % ---- Read internal header to get the session label ----
    try
        hdr = motec_ld_info(src_path, ECU_FORMAT);
        file_session = strtrim(hdr.session);
    catch err_hdr
        fprintf('  [WARN] %s: cannot read header (%s) — skipping.\n', ...
            [src_name src_ext], err_hdr.message);
        continue;
    end

    if isempty(file_session)
        continue;   % no session in header — not our concern here
    end

    match_idx = find(strcmpi(file_session, SESSION_NAMES), 1);
    if isempty(match_idx)
        continue;   % header session isn't a known combined name — leave alone
    end

    labels = strsplit(SESSION_NAMES{match_idx}, '_');   % e.g. 'P01_P02' -> {'P01','P02'}

    % ---- Resolve driver / team / car from header via alias map ----
    raw_driver = '';
    if isfield(hdr, 'driver'), raw_driver = strtrim(hdr.driver); end
    [driver_canonical, car_num, team_tla, driver_tla, alias_status] = ...
        resolve_driver_display(raw_driver, driver_map);
    if isfield(cfg, 'DriverFilter') && ~isempty(cfg.DriverFilter)
        if ~strcmp(driver_tla, cfg.DriverFilter)
            continue
        end
    end
    driver_display = raw_driver;
    if strcmp(alias_status, 'OK')
        driver_display = sprintf('%s (#%s %s)', driver_canonical, car_num, team_tla);
    elseif ~isempty(raw_driver)
        driver_display = sprintf('%s (not in alias file)', raw_driver);
    else
        driver_display = 'unknown driver';
    end

    fprintf('----------------------------------------\n');
    fprintf('Combined file: %s   header session="%s"   ->   %s\n', ...
        [src_name src_ext], file_session, strjoin(labels, ' + '));
    fprintf('  Driver: %s\n', driver_display);
    fprintf('----------------------------------------\n');

    % ---- Output paths ----
    % Default (ECU / TeamData convention): sibling folder next to combined_input_dir
    %   E:\2026\E08_PER\ECU\P01_P02\file.ld
    %   -> E:\2026\E08_PER\ECU\P01\file.ld  +  E:\2026\E08_PER\ECU\P02\file.ld
    %
    % L180 convention (cfg.split_data_type = 'L180'): SAME folder as the
    % input, filename suffixed with the label instead of a new subfolder.
    % L180 files land flat in one folder alongside genuine single-session
    % files (e.g. real standalone P01 files already sitting there), so we
    % can't just write "P01/file.ld" back into that same folder — that
    % would create a subfolder INSIDE the folder smp_sort_l180_to_hol
    % scans non-recursively, and the plain filename would collide with
    % any other P01_P02 file's split output. Suffixing keeps everything
    % flat and disambiguated:
    %   E:\2026\E08_PER\L180\file.ld  (header "P01_P02")
    %   -> E:\2026\E08_PER\L180\file_P01.ld  +  E:\2026\E08_PER\L180\file_P02.ld
    if strcmpi(DATA_TYPE, 'L180')
        out_paths = cell(1, numel(labels));
        for li = 1 : numel(labels)
            out_paths{li} = fullfile(listing(fi).folder, sprintf('%s_%s%s', src_name, labels{li}, src_ext));
        end
    else
        base_dir = fileparts(INPUT_DIR);   % one level up from combined_input_dir

        % Preserve any subfolder structure below INPUT_DIR (relevant if the
        % '**' recursive scan found files nested deeper than INPUT_DIR itself)
        rel_dir = listing(fi).folder;
        if strncmpi(rel_dir, INPUT_DIR, numel(INPUT_DIR))
            rel_dir = rel_dir(numel(INPUT_DIR)+1:end);
            rel_dir = regexprep(rel_dir, '^[\\/]+', '');
        else
            rel_dir = '';
        end

        out_paths = cell(1, numel(labels));
        for li = 1 : numel(labels)
            out_dir = fullfile(base_dir, labels{li}, rel_dir);
            if ~isfolder(out_dir), mkdir(out_dir); end
            out_paths{li} = fullfile(out_dir, [src_name src_ext]);
        end
    end

    if ~OVERWRITE && ~ALWAYS_REVIEW && all(cellfun(@(p) exist(p, 'file') == 2, out_paths))
        fprintf('  [SKIP] All outputs already exist.\n');
        csv_rows{end+1} = sprintf('%s,SKIP_EXISTS,%s,,,', ... %#ok<AGROW>
            [src_name src_ext], strjoin(labels, ';'));
        n_skip = n_skip + 1;
        continue;
    end

    % ---- Read ERT channel for the visual + auto-suggest ----
    ert = [];
    for k = 1 : numel(ERT_NAMES)
        try
            d  = motec_ld_reader(src_path, {ERT_NAMES{k}}, ECU_FORMAT);
            fn = fieldnames(d);
            if ~isempty(fn)
                ert = d.(fn{1});
                break;
            end
        catch
        end
    end
    if isempty(ert) || isempty(ert.data)
        fprintf('  [FAIL] No ERT channel found (tried: %s) — cannot visualise.\n', ...
            strjoin(ERT_NAMES, ', '));
        csv_rows{end+1} = sprintf('%s,FAIL_NO_ERT,%s,,,', ... %#ok<AGROW>
            [src_name src_ext], strjoin(labels, ';'));
        n_fail = n_fail + 1;
        continue;
    end

    % ---- Optional aux channel (Ground_Speed by default) purely for the visual ----
    aux = [];
    if ~isempty(AUX_CH)
        try
            d_aux = motec_ld_reader(src_path, {AUX_CH}, ECU_FORMAT);
            fn_aux = fieldnames(d_aux);
            if ~isempty(fn_aux), aux = d_aux.(fn_aux{1}); end
        catch
        end
    end

    % ---- Auto-suggested split: largest forward gap / reset in ERT ----
    dt_data = diff(ert.data);
    dt_time = diff(ert.time);
    split_mask = (dt_data > MIN_GAP_S) | (dt_data < 0) | (dt_time > MIN_GAP_S);
    idx = find(split_mask);
    if ~isempty(idx)
        [~, biggest] = max(abs(dt_data(idx)));
        suggested_t = ert.time(idx(biggest));
    else
        suggested_t = ert.time(round(numel(ert.time)/2));  % fallback: midpoint
    end

    % ---- Launch visual split tool ----
    result = smp_combined_split_ui(ert, aux, AUX_LABEL, labels, suggested_t, ...
        sprintf('%s — %s', [src_name src_ext], driver_display));

    if ischar(result) && strcmp(result, 'SKIP')
        fprintf('  [SKIP] User skipped.\n');
        csv_rows{end+1} = sprintf('%s,SKIP_USER,%s,,,', ... %#ok<AGROW>
            [src_name src_ext], strjoin(labels, ';'));
        n_skip = n_skip + 1;
        continue;
    end
    if isempty(result)
        fprintf('  [FAIL] Split tool closed with no result.\n');
        csv_rows{end+1} = sprintf('%s,FAIL_NO_RESULT,%s,,,', ... %#ok<AGROW>
            [src_name src_ext], strjoin(labels, ';'));
        n_fail = n_fail + 1;
        continue;
    end

    split_times = result;   % sorted vector of numel(labels)-1 boundary times
    if numel(split_times) ~= numel(labels) - 1
        fprintf('  [FAIL] Expected %d marker(s) for %d label(s), got %d.\n', ...
            numel(labels)-1, numel(labels), numel(split_times));
        csv_rows{end+1} = sprintf('%s,FAIL_MARKER_COUNT,%s,,,', ... %#ok<AGROW>
            [src_name src_ext], strjoin(labels, ';'));
        n_fail = n_fail + 1;
        continue;
    end

    % ---- Write the segments using the byte-patch approach ----
    seg_starts = [0, split_times];
    seg_ends   = [split_times, Inf];

    try
        records = walk_channel_records_local(src_path);
    catch err_rec
        fprintf('  [FAIL] Could not read channel records: %s\n', err_rec.message);
        csv_rows{end+1} = sprintf('%s,FAIL_READ_RECORDS,%s,,,', ... %#ok<AGROW>
            [src_name src_ext], strjoin(labels, ';'));
        n_fail = n_fail + 1;
        continue;
    end

    write_ok = true;
    for li = 1 : numel(labels)
        T_start = seg_starts(li);
        T_end   = seg_ends(li);
        out_path = out_paths{li};

        if exist(out_path, 'file') && ~OVERWRITE
            fprintf('  [SKIP] Exists, overwrite=false: %s\n', out_path);
            continue;
        end
        if exist(out_path, 'file')
            delete(out_path);
        end

        try
            copyfile(src_path, out_path);
            fid = fopen(out_path, 'r+b');
            if fid == -1, error('fopen failed on %s', out_path); end

            n_patched = 0;
            for r = 1 : numel(records)
                rec = records(r);
                if rec.data_ptr == 0 || rec.data_len == 0 || rec.sample_rate == 0
                    continue;
                end
                bps     = datatype_bps_local(rec.datatype);
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

            % Shift header date/time for every segment after the first
            if li > 1
                shift_header_datetime_local(fid, T_start);
            end

            fclose(fid); fid = -1;

            patch_ld_header_local(out_path, labels{li}, HOL_VENUE, HOL_EVENT);

            % Also scan the whole file for any OTHER literal occurrences
            % of the combined session string (e.g. a secondary metadata
            % block at a variable, data-dependent offset that the fixed
            % 0x5E4 header patch doesn't reach) and null-pad-overwrite
            % each one with this segment's label.
            n_extra_patched = patch_all_string_occurrences_local(out_path, file_session, labels{li});
            if n_extra_patched > 0
                fprintf('  [PATCH] Found and rewrote %d additional occurrence(s) of "%s" -> "%s"\n', ...
                    n_extra_patched, file_session, labels{li});
            end

            fprintf('  [OK] %s  [%.1fs, %s)  -> %s  (%d channels patched)\n', ...
                labels{li}, T_start, ternary_local(isinf(T_end), 'end', sprintf('%.1fs', T_end)), ...
                out_path, n_patched);

        catch err_w
            if exist('fid', 'var') && fid ~= -1, fclose(fid); end %#ok<NASGU>
            fprintf('  [ERROR] Writing %s: %s\n', out_path, err_w.message);
            write_ok = false;
        end
    end

    if write_ok
        csv_rows{end+1} = sprintf('%s,OK,%s,%s,%s,%s', ... %#ok<AGROW>
            [src_name src_ext], strjoin(labels, ';'), ...
            strjoin(arrayfun(@(x) sprintf('%.1f', x), split_times, 'UniformOutput', false), ';'), ...
            out_paths{1}, out_paths{min(2,numel(out_paths))});
        n_ok = n_ok + 1;
    else
        csv_rows{end+1} = sprintf('%s,FAIL_WRITE,%s,,,', ... %#ok<AGROW>
            [src_name src_ext], strjoin(labels, ';'));
        n_fail = n_fail + 1;
    end
end

fprintf('\n=== Phase 0 complete: %d ok, %d skipped, %d failed ===\n\n', n_ok, n_skip, n_fail);

end


% =========================================================================
%  LOCAL HELPERS (self-contained copies — no cross-file dependency)
% =========================================================================
function out = ternary_local(cond, a, b)
    if cond, out = a; else, out = b; end
end

function records = walk_channel_records_local(filepath)
    fid = fopen(filepath, 'rb');
    if fid == -1, error('walk_channel_records_local: cannot open %s', filepath); end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);
    fseek(fid, 0x0008, 'bof');
    first_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    if ~isscalar(first_ptr) || first_ptr == 0 || first_ptr >= file_sz
        error('walk_channel_records_local: invalid first_meta_ptr in %s', filepath);
    end
    records = struct('meta_ptr', {}, 'data_ptr', {}, 'data_len', {}, ...
                     'sample_rate', {}, 'datatype', {}, 'name', {});
    current_ptr = first_ptr;
    n = 0;
    while current_ptr ~= 0 && current_ptr < file_sz
        fseek(fid, current_ptr, 'bof');
        fread(fid, 1, 'uint32=>double', 0, 'l');               % prev_ptr
        next_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l'); % next_ptr
        data_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l'); % data_ptr
        data_len    = fread(fid, 1, 'uint32=>double', 0, 'l'); % n_samples
        fread(fid, 1, 'uint16=>double', 0, 'l');               % sr_raw
        fread(fid, 1, 'uint16=>double', 0, 'l');               % unk1
        datatype    = fread(fid, 1, 'uint16=>double', 0, 'l'); % datatype
        sample_rate = fread(fid, 1, 'uint16=>double', 0, 'l'); % Hz
        fread(fid, 4, 'int16=>double',  0, 'l');               % off/mul/scale/dec
        name_raw    = fread(fid, 32, 'uint8=>double')';        % name
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
            warning('walk_channel_records_local: exceeded 5000 records — stopping.');
            break;
        end
    end
end

function bps = datatype_bps_local(datatype)
    switch datatype
        case 1,  bps = 2;
        case 2,  bps = 2;
        case 3,  bps = 4;
        case 4,  bps = 4;
        otherwise
            warning('datatype_bps_local: unknown datatype %d — assuming 2 bytes/sample.', datatype);
            bps = 2;
    end
end

function shift_header_datetime_local(fid, offset_s)
    DATE_OFFSET = 0x5E; TIME_OFFSET = 0x7E; DATE_LEN = 16; TIME_LEN = 16;
    fseek(fid, DATE_OFFSET, 'bof');
    date_bytes = fread(fid, DATE_LEN, 'uint8=>double')';
    fseek(fid, TIME_OFFSET, 'bof');
    time_bytes = fread(fid, TIME_LEN, 'uint8=>double')';
    date_str = strtrim(char(date_bytes(date_bytes > 0)));
    time_str = strtrim(char(time_bytes(time_bytes > 0)));
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
        fprintf('  [WARN] shift_header_datetime_local: cannot parse date/time — skipping.\n');
        return;
    end
    dt_shifted   = dt + offset_s / 86400;
    new_date_str = datestr(dt_shifted, 'dd/mm/yyyy');
    new_time_str = datestr(dt_shifted, 'HH:MM:SS');
    write_fixed_str_local(fid, DATE_OFFSET, new_date_str, DATE_LEN);
    write_fixed_str_local(fid, TIME_OFFSET, new_time_str, TIME_LEN);
end

function write_fixed_str_local(fid, offset, str, field_len)
    fseek(fid, offset, 'bof');
    bytes      = zeros(1, field_len, 'uint8');
    n          = min(numel(str), field_len);
    bytes(1:n) = uint8(str(1:n));
    fwrite(fid, bytes, 'uint8');
end

function n_patched = patch_all_string_occurrences_local(filepath, old_str, new_str)
% Scans the whole file for every literal ASCII occurrence of old_str and
% overwrites each one in place with new_str, null-padding the remainder
% of the original field length so nothing shifts and no surrounding
% bytes are disturbed. Safe for null-padded metadata fields; do NOT use
% this against literal strings that might coincidentally appear inside
% binary channel sample data without null-padding either side, since
% there's no length-prefix to know a field boundary — the caller is
% responsible for using a distinctive enough old_str (a full combined
% session name like "P01_P02" is safe; a bare "P01" would not be, since
% it could coincidentally match binary data or the already-patched
% output of another segment).
    if numel(new_str) > numel(old_str)
        error('patch_all_string_occurrences_local: new_str must not be longer than old_str');
    end

    fid = fopen(filepath, 'r+b');
    if fid == -1
        fprintf('  [WARN] patch_all_string_occurrences_local: cannot open %s\n', filepath);
        n_patched = 0;
        return;
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);
    fseek(fid, 0, 'bof');
    raw = fread(fid, file_sz, 'uint8=>uint8')';

    offsets = strfind(char(raw), old_str);   % 1-indexed
    n_patched = numel(offsets);
    if n_patched == 0
        return;
    end

    pad_len   = numel(old_str) - numel(new_str);
    new_bytes = [uint8(new_str), zeros(1, pad_len, 'uint8')];

    for i = 1 : n_patched
        off0 = offsets(i) - 1;   % 0-indexed byte offset
        fseek(fid, off0, 'bof');
        fwrite(fid, new_bytes, 'uint8');
    end
end

function patch_ld_header_local(filepath, session_str, venue_str, event_str)
    FIELDS = {hex2dec('5E4'), session_str, 32; ...
              hex2dec('15E'), venue_str,   64; ...
              hex2dec('624'), event_str,   32};
    fid = fopen(filepath, 'r+b');
    if fid == -1
        fprintf('  [WARN] patch_ld_header_local: cannot open %s\n', filepath);
        return;
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for fi = 1 : size(FIELDS, 1)
        off = FIELDS{fi, 1}; str = FIELDS{fi, 2}; len = FIELDS{fi, 3};
        if isempty(str), continue; end
        bytes      = zeros(1, len, 'uint8');
        n          = min(numel(str), len - 1);
        bytes(1:n) = uint8(str(1:n));
        fseek(fid, off, 'bof');
        fwrite(fid, bytes, 'uint8');
    end
end