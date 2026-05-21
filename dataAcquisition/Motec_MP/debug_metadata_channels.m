%% debug_metadata_channels.m
% Write ALL session metadata channels to a single test .ld file, then
% read each one back and report encoded vs decoded value and pass/fail.

clear; clc;

%% =========================================================
%  CONFIG — edit these
%% =========================================================
DASH_FILE            = 'E:\2026\T01_QLR\Dash\20260505-156890002.ld';
SESSION_METADATA_FILE = fullfile(fileparts(mfilename('fullpath')), 'channels', 'session_metadata.xlsx');
DEBUG_OUTPUT_FILE    = 'E:\2026\T01_QLR\COM\debug_metadata_all.ld';

%% =========================================================
%  SETUP
%% =========================================================
% Ensure ld_add_channel is on path
ch_add_dir = fullfile(fileparts(mfilename('fullpath')), 'channelAdd');
if ~any(strcmp(strsplit(path, pathsep), ch_add_dir))
    addpath(ch_add_dir);
end

out_dir = fileparts(DEBUG_OUTPUT_FILE);
if ~isempty(out_dir) && ~exist(out_dir, 'dir')
    mkdir(out_dir);
    fprintf('Created: %s\n\n', out_dir);
end

%% =========================================================
%  LOAD SESSION METADATA
%% =========================================================
fprintf('=== Loading session metadata ===\n');
session_meta = smp_session_metadata_load(SESSION_METADATA_FILE, DASH_FILE);

if isempty(fieldnames(session_meta))
    fprintf('\n[FAIL] No session metadata loaded.\n');
    fprintf('  Check that DASH_FILE column in xlsx matches exactly:\n');
    fprintf('    %s\n', DASH_FILE);
    return;
end

meta_fns = fieldnames(session_meta);
fprintf('  Loaded %d channels: %s\n\n', numel(meta_fns), strjoin(meta_fns, ', '));

%% =========================================================
%  NAME COLLISION CHECK — warn if Dash file already has same channel name
%% =========================================================
fprintf('=== Name collision check ===\n');
dash_struct   = motec_ld_reader(DASH_FILE);
dash_fns_san  = fieldnames(dash_struct);   % sanitised field names
% Also collect raw channel names for comparison
dash_raw_names = cellfun(@(f) dash_struct.(f).raw_name, dash_fns_san, 'UniformOutput', false);
san = @(s) lower(regexprep(regexprep(s, '[^a-zA-Z0-9]', '_'), '_+', '_'));
any_collision = false;
for mci = 1:numel(meta_fns)
    msch     = session_meta.(meta_fns{mci});
    name_san = san(msch.name);
    % Check both sanitised field names and original raw channel names
    field_hit = any(strcmpi(dash_fns_san, name_san));
    raw_hit   = any(strcmpi(dash_raw_names, msch.name));
    if field_hit || raw_hit
        fprintf('  [COLLISION] "%s" already exists in Dash file!\n', msch.name);
        fprintf('              i2 will show the Dash channel, not our constant.\n');
        any_collision = true;
    else
        fprintf('  [OK]        "%s"\n', msch.name);
    end
end
if any_collision
    fprintf('\n  FIX: prefix colliding channel names (e.g. "Sess. Wind Direction")\n');
    fprintf('  This is done automatically below.\n\n');
else
    fprintf('  No collisions — names are safe.\n\n');
end
%% =========================================================
%  BUILD CHANNEL LIST + PREDICT ENCODING
%% =========================================================
SESS_PREFIX = 'Sess.';   % prefix to avoid name collisions with Dash channels
META_SR     = 5;        % Hz — 5Hz donor exists in every Dash file

% Compute full session duration so constants span the whole recording
meta_ses_dur = debug_read_session_dur(DASH_FILE);
meta_n       = round(meta_ses_dur * META_SR);
fprintf('Session duration from Dash file: %.1f s  →  n = %d @ %d Hz\n\n', meta_ses_dur, meta_n, META_SR);

ch_list  = {};
pred     = struct();

for mci = 1:numel(meta_fns)
    mfn  = meta_fns{mci};
    msch = session_meta.(mfn);
    mval = double(msch.value);

    % Compute dec_places (same logic as smp_merge_ecu_dash)
    mdec = 0;
    for d = 4:-1:0
        if abs(mval) * 10^d <= 32767
            mdec = d;
            break;
        end
    end

    % Prefix name if it collides with an existing Dash channel (field name OR raw name)
    display_name = msch.name;
    field_hit = any(strcmpi(dash_fns_san, san(msch.name)));
    raw_hit   = any(strcmpi(dash_raw_names, msch.name));
    if field_hit || raw_hit
        display_name = [SESS_PREFIX msch.name];
    end

    mc.name        = display_name;
    mc.short_name  = display_name(1:min(end,7));
    mc.units       = msch.units;
    mc.value       = repmat(mval, meta_n, 1);   % explicit vector → full session coverage
    mc.sample_rate = META_SR;
    mc.dec_places  = mdec;
    mc.offset      = 0;
    mc.mul         = 1;
    mc.scale       = 1;
    ch_list{end+1} = mc; %#ok<AGROW>

    pred.(mfn).name          = display_name;
    pred.(mfn).value         = mval;
    pred.(mfn).dec_places    = mdec;
    pred.(mfn).raw_predicted = round(mval * 10^mdec);
    pred.(mfn).decoded_pred  = round(mval * 10^mdec) / 10^mdec;
end

%% =========================================================
%  WRITE ALL CHANNELS TO ONE FILE
%% =========================================================
% Delete stale output file so we always write fresh
if exist(DEBUG_OUTPUT_FILE, 'file'), delete(DEBUG_OUTPUT_FILE); end

fprintf('\n=== Writing all %d metadata channels to one file ===\n', numel(ch_list));
fprintf('  %s\n\n', DEBUG_OUTPUT_FILE);
try
    ld_add_channel(DASH_FILE, DEBUG_OUTPUT_FILE, ch_list);
    write_ok = true;
catch e
    fprintf('[ERROR writing] %s\n', e.message);
    write_ok = false;
end

if ~write_ok, return; end

%% =========================================================
%  READ BACK AND VERIFY EACH CHANNEL
%% =========================================================
fprintf('\n=== Reading back and verifying ===\n\n');

out_struct  = motec_ld_reader(DEBUG_OUTPUT_FILE);
out_fns     = fieldnames(out_struct);

fprintf('%-20s  %10s  %5s  %8s  %8s  %8s  %10s  %10s  %s\n', ...
    'Channel', 'Value', 'dec', 'raw_int16', 'decoded', 'error', 't_start(s)', 't_end(s)', 'Status');
fprintf('%s\n', repmat('-', 1, 100));

results = struct();

for mci = 1:numel(meta_fns)
    mfn  = meta_fns{mci};
    mval = pred.(mfn).value;
    mdec = pred.(mfn).dec_places;

    % Match directly by the name we WROTE (after prefix), not setdiff
    target_san = san(pred.(mfn).name);
    match_fn   = '';
    for fi = 1:numel(out_fns)
        if strcmpi(out_fns{fi}, target_san) || ...
           strcmpi(out_fns{fi}, regexprep(target_san, '_+$', ''))
            match_fn = out_fns{fi};
            break;
        end
    end

    readback_val  = NaN;
    readback_t0   = NaN;
    readback_tend = NaN;
    if ~isempty(match_fn)
        readback_val  = out_struct.(match_fn).data(1);
        readback_t0   = out_struct.(match_fn).time(1);
        readback_tend = out_struct.(match_fn).time(end);
    end

    readback_err = abs(readback_val - mval);
    if isnan(readback_val)
        status = 'READ FAIL';
    elseif readback_err <= 0.5 / 10^mdec + 1e-9
        status = 'PASS';
    else
        status = sprintf('FAIL (err=%.4f)', readback_err);
    end

    fprintf('%-20s  %10.4f  %5d  %8d  %8.4f  %8.4f  %10.2f  %10.2f  %s\n', ...
        pred.(mfn).name, mval, mdec, int32(pred.(mfn).raw_predicted), ...
        pred.(mfn).decoded_pred, readback_err, readback_t0, readback_tend, status);

    results.(mfn).readback_val  = readback_val;
    results.(mfn).readback_err  = readback_err;
    results.(mfn).readback_t0   = readback_t0;
    results.(mfn).readback_tend = readback_tend;
    results.(mfn).status        = status;
end

fprintf('%s\n', repmat('-', 1, 100));

%% =========================================================
%  SUMMARY
%% =========================================================
n_pass = sum(cellfun(@(f) strcmp(results.(f).status, 'PASS'), fieldnames(results)));
n_fail = numel(meta_fns) - n_pass;

fprintf('\nSummary: %d / %d PASS', n_pass, numel(meta_fns));
if n_fail > 0
    fprintf('  ← %d FAILED\n', n_fail);
    fprintf('\nFailed channels:\n');
    for mci = 1:numel(meta_fns)
        mfn = meta_fns{mci};
        if ~strcmp(results.(mfn).status, 'PASS')
            fprintf('  %-20s  value=%.4f  dec=%d  readback=%.4f  err=%.4f\n', ...
                pred.(mfn).name, pred.(mfn).value, pred.(mfn).dec_places, ...
                results.(mfn).readback_val, results.(mfn).readback_err);
        end
    end
else
    fprintf(' — all channels encode correctly.\n');
end

fprintf('\nOutput file (open in i2):\n  %s\n', DEBUG_OUTPUT_FILE);

%% =========================================================
%  SESSION TIMING & DONOR CHANNEL CHECK
%% =========================================================
fprintf('\n=== Session timing & donor channel ===\n');
fid_d  = fopen(DASH_FILE, 'rb');
fseek(fid_d, 0, 'eof'); dsz = ftell(fid_d);
fseek(fid_d, 0x0008, 'bof');
dptr          = fread(fid_d, 1, 'uint32=>double', 0, 'l');
n_dash        = 0;
ses_dur       = 0;
donor_25_name = '(none -- synthetic will be used)';
donor_25_n    = 0;
while dptr ~= 0 && dptr < dsz
    fseek(fid_d, dptr, 'bof');
    drec  = fread(fid_d, 84, 'uint8=>uint8')';
    dnext = double(typecast(uint8(drec(5:8)),   'uint32'));
    dsr   = double(typecast(uint8(drec(23:24)), 'uint16'));
    dch_n = double(typecast(uint8(drec(13:16)), 'uint32'));
    dnr   = drec(33:64); dnul = find(dnr==0,1);
    if ~isempty(dnul), dnr = dnr(1:dnul-1); end
    dname = strtrim(char(dnr));
    if dsr > 0 && dch_n > 0
        if dch_n/dsr > ses_dur, ses_dur = dch_n/dsr; end
        if dsr == 25 && dch_n > donor_25_n
            donor_25_name = dname;
            donor_25_n    = dch_n;
        end
    end
    dptr   = dnext;
    n_dash = n_dash + 1;
    if n_dash > 5000, break; end
end
fclose(fid_d);

fprintf('  Session duration (Dash file) : %.2f s\n', ses_dur);
if donor_25_n > 0
    fprintf('  Donor channel at 25Hz        : "%s"\n', donor_25_name);
    fprintf('  Donor covers                 : %.2f s  (%d samples)\n', donor_25_n/25, donor_25_n);
    gap = ses_dur - donor_25_n/25;
    if abs(gap) < 0.5
        fprintf('  Coverage vs session          : OK (gap = %.3f s)\n', gap);
    else
        fprintf('  Coverage vs session          : WARNING gap = %.2f s\n', gap);
    end
else
    fprintf('  Donor channel at 25Hz        : %s\n', donor_25_name);
    fprintf('  Synthetic n will be          : %d  (%.2f s)\n', ...
        round(ses_dur*25), round(ses_dur*25)/25);
end

%% =========================================================
%  BINARY VERIFICATION — walk new channels, dump raw metadata
%% =========================================================
fprintf('\n=== Binary verification of new channels ===\n');
fprintf('%-20s  %6s  %8s  %8s  %6s  %6s  %6s  %5s  %10s  %9s  %s\n', ...
    'Name', 'Hz', 'meta_ptr', 'data_ptr', 'n', 'mul', 'scale', 'dec', 'phys[0]', 'covers(s)', 'units');
fprintf('%s\n', repmat('-', 1, 115));

fid_b   = fopen(DEBUG_OUTPUT_FILE, 'rb');
fseek(fid_b, 0, 'eof'); fsz = ftell(fid_b);
fseek(fid_b, 0x0008, 'bof');
ptr = fread(fid_b, 1, 'uint32=>double', 0, 'l');
ch_idx = 0;

while ptr ~= 0 && ptr < fsz
    fseek(fid_b, ptr, 'bof');
    rec      = fread(fid_b, 84, 'uint8=>uint8')';
    next_ptr = double(typecast(uint8(rec(5:8)),   'uint32'));
    data_ptr = double(typecast(uint8(rec(9:12)),  'uint32'));
    n_samp   = double(typecast(uint8(rec(13:16)), 'uint32'));
    datatype = double(typecast(uint8(rec(21:22)), 'uint16'));
    hz       = double(typecast(uint8(rec(23:24)), 'uint16'));
    r_mul    = double(typecast(uint8(rec(27:28)), 'int16'));
    r_scale  = double(typecast(uint8(rec(29:30)), 'int16'));
    r_dec    = double(typecast(uint8(rec(31:32)), 'int16'));
    name_raw = rec(33:64);
    nul      = find(name_raw == 0, 1);
    if ~isempty(nul), name_raw = name_raw(1:nul-1); end
    name_str = strtrim(char(name_raw));

    ch_idx = ch_idx + 1;
    if ch_idx > n_dash
        % Read and decode first sample
        phys0 = NaN; raw0 = NaN;
        if data_ptr > 0 && data_ptr < fsz && n_samp > 0
            fseek(fid_b, data_ptr, 'bof');
            if datatype == 2
                raw0 = fread(fid_b, 1, 'int16=>double', 0, 'l');
            elseif datatype == 3
                raw0 = fread(fid_b, 1, 'int32=>double', 0, 'l');
            end
            if ~isnan(raw0)
                if r_scale ~= 0 && r_mul ~= 0
                    phys0 = raw0 * (r_mul/r_scale) / (10^r_dec);
                else
                    phys0 = raw0 / (10^r_dec);
                end
            end
        end
        covers_s = n_samp / max(hz, 1);
        gap_s    = ses_dur - covers_s;
        if abs(gap_s) < 0.5
            gap_flag = 'OK';
        else
            gap_flag = sprintf('GAP %.1fs', gap_s);
        end
        % Read units bytes directly from record (bytes 73-84, 0-based offset 72)
        units_raw = rec(73:84);
        units_nul = find(units_raw == 0, 1);
        if isempty(units_nul)
            units_str = strtrim(char(units_raw));
        elseif units_nul == 1
            units_str = '(EMPTY)';
        else
            units_str = strtrim(char(units_raw(1:units_nul-1)));
        end
        fprintf('%-20s  %6d  %8X  %8X  %6d  %6d  %6d  %5d  %10.4f  %9s  units=[%s]\n', ...
            name_str, hz, uint32(ptr), uint32(data_ptr), n_samp, ...
            r_mul, r_scale, r_dec, phys0, gap_flag, units_str);
    end
    ptr = next_ptr;
    if ch_idx > 5000, break; end
end
fclose(fid_b);
fprintf('%s\n', repmat('-', 1, 115));
fprintf('\ncovers(s): OK = channel spans full session | GAP Xs = short by X seconds\n');
fprintf('units=(EMPTY): bytes 73-84 are zero in file → motec_ld_reader returns empty string\n');
fprintf('If value looks right but invisible in i2: right-click y-axis -> Fit\n');

%% =========================================================
%  LINKED LIST INTEGRITY CHECK
%  Walk every channel, verify next_ptr and prev_ptr are self-consistent
%% =========================================================
fprintf('\n=== Linked list integrity check ===\n');
fid_b  = fopen(DEBUG_OUTPUT_FILE, 'rb');
fseek(fid_b, 0, 'eof'); fsz = ftell(fid_b);
fseek(fid_b, 0x0008, 'bof');
ptr       = fread(fid_b, 1, 'uint32=>double', 0, 'l');
prev_expected = 0;
ch_idx    = 0;
chain_ok  = true;

while ptr ~= 0 && ptr < fsz
    fseek(fid_b, ptr, 'bof');
    rec       = fread(fid_b, 84, 'uint8=>uint8')';
    prev_ptr  = double(typecast(uint8(rec(1:4)),  'uint32'));
    next_ptr  = double(typecast(uint8(rec(5:8)),  'uint32'));
    data_ptr  = double(typecast(uint8(rec(9:12)), 'uint32'));
    n_samp    = double(typecast(uint8(rec(13:16)),'uint32'));
    hz        = double(typecast(uint8(rec(23:24)),'uint16'));
    name_raw  = rec(33:64); nul = find(name_raw==0,1);
    if ~isempty(nul), name_raw = name_raw(1:nul-1); end
    name_str  = strtrim(char(name_raw));
    ch_idx    = ch_idx + 1;

    % Flag broken only if next_ptr goes backward or is invalid
    % Original Dash channels use non-contiguous layout (metadata packed,
    % data stored separately) so we cannot predict next_ptr from data_ptr.
    % We only care that the chain is walkable and monotonically forward.
    if next_ptr == 0
        next_ok   = true;
        next_flag = 'LAST';
    elseif next_ptr > ptr && next_ptr < fsz
        next_ok   = true;
        next_flag = 'OK';
    else
        next_ok   = false;
        next_flag = sprintf('BAD(ptr=%X next=%X)', uint32(ptr), uint32(next_ptr));
        chain_ok  = false;
    end

    % prev_ptr should point back to the previous channel's meta ptr
    if prev_ptr == prev_expected
        prev_flag = 'OK';
    else
        prev_flag = sprintf('BAD(exp=%X got=%X)', uint32(prev_expected), uint32(prev_ptr));
        chain_ok  = false;
    end

    fprintf('  [%3d] %-20s  ptr=%8X  prev=%s  next=%s\n', ...
        ch_idx, name_str, uint32(ptr), prev_flag, next_flag);

    prev_expected = ptr;
    ptr = next_ptr;
    if ch_idx > 5000, break; end
end
fclose(fid_b);

if chain_ok
    fprintf('\n  Chain INTACT — all prev/next pointers are self-consistent.\n');
    fprintf('  Invisible channels in i2 = y-axis range issue, not a pointer problem.\n');
    fprintf('  Fix: right-click y-axis on each blank row in i2 → Fit\n');
else
    fprintf('\n  Chain BROKEN — pointer mismatch found above.\n');
end

%% =========================================================
%  LOCAL HELPERS
%% =========================================================
function dur = debug_read_session_dur(filepath)
% Binary walk of .ld channel linked list — return max(n/Hz) over all channels.
    fid = fopen(filepath, 'rb');
    if fid < 0, error('debug_read_session_dur: cannot open %s', filepath); end
    c = onCleanup(@() fclose(fid));
    fseek(fid, 0, 'eof');
    fsz = ftell(fid);
    fseek(fid, 0x0008, 'bof');
    ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    dur   = 0;
    count = 0;
    while ptr ~= 0 && ptr < fsz
        fseek(fid, ptr, 'bof');
        rec  = fread(fid, 24, 'uint8=>uint8')';
        next = double(typecast(uint8(rec(5:8)),  'uint32'));
        n    = double(typecast(uint8(rec(13:16)), 'uint32'));
        sr   = double(typecast(uint8(rec(23:24)), 'uint16'));
        if sr > 0 && n > 0
            dur = max(dur, n / sr);
        end
        ptr = next;
        count = count + 1;
        if count > 5000, break; end
    end
end