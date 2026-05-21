%% run_metadata_channels.m
% Write ALL session metadata channels (from Excel) to a single test .ld file,
% using the RUN_LD_ADD_CHANNEL struct-array + scalar-value approach.
% Read back each channel and report encoded vs decoded value and pass/fail.

clear; clc;

%% =========================================================
%  CONFIG — edit these
%% =========================================================
DASH_FILE             = 'E:\2026\T01_QLR\Dash\20260505-156890005.ld';
SESSION_METADATA_FILE = fullfile(fileparts(mfilename('fullpath')), 'channels', 'session_metadata.xlsx');
DEBUG_OUTPUT_FILE     = 'E:\2026\T01_QLR\COM\run_metadata_all.ld';

%% =========================================================
%  SETUP
%% =========================================================
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
dash_struct  = motec_ld_reader(DASH_FILE);
dash_fns_san = fieldnames(dash_struct);
dash_raw_names = cellfun(@(f) dash_struct.(f).raw_name, dash_fns_san, 'UniformOutput', false);
san = @(s) lower(regexprep(regexprep(s, '[^a-zA-Z0-9]', '_'), '_+', '_'));
any_collision = false;
for mci = 1:numel(meta_fns)
    msch     = session_meta.(meta_fns{mci});
    name_san = san(msch.name);
    field_hit = any(strcmpi(dash_fns_san, name_san));
    raw_hit   = any(strcmpi(dash_raw_names, msch.name));
    if field_hit || raw_hit
        fprintf('  [COLLISION] "%s" already exists in Dash file!\n', msch.name);
        any_collision = true;
    else
        fprintf('  [OK]        "%s"\n', msch.name);
    end
end
if any_collision
    fprintf('\n  FIX: prefix colliding channel names (e.g. "Sess. Wind Direction")\n\n');
else
    fprintf('  No collisions — names are safe.\n\n');
end

%% =========================================================
%  BUILD CHANNEL STRUCT ARRAY  (RUN_LD_ADD_CHANNEL style)
%% =========================================================
SESS_PREFIX = 'Sess.';
META_SR     = 5;   % Hz

ch = struct([]);

for mci = 1:numel(meta_fns)
    mfn  = meta_fns{mci};
    msch = session_meta.(mfn);
    mval = double(msch.value);

    % Prefix name if it collides with an existing Dash channel
    display_name = msch.name;
    field_hit = any(strcmpi(dash_fns_san, san(msch.name)));
    raw_hit   = any(strcmpi(dash_raw_names, msch.name));
    if field_hit || raw_hit
        display_name = [SESS_PREFIX msch.name];
    end

    % Compute dec_places: max 3 decimal places, must keep int16 in range
    mdec = 0;
    for d = 3:-1:0
        if abs(mval) * 10^d <= 32767
            mdec = d;
            break;
        end
    end

    ch(mci).name        = display_name;
    ch(mci).short_name  = display_name(1:min(end,7));
    ch(mci).units       = msch.units;
    ch(mci).value       = mval;          % scalar — ld_add_channel expands via donor
    ch(mci).sample_rate = META_SR;
    ch(mci).dec_places  = mdec;
    ch(mci).mul         = 1;
    ch(mci).scale       = 1;
    ch(mci).offset      = 0;
    ch(mci).datatype    = 2;   % force int16 — prevents float16 donor from silently dropping dec_places
end

%% =========================================================
%  WRITE ALL CHANNELS TO ONE FILE
%% =========================================================
if exist(DEBUG_OUTPUT_FILE, 'file'), delete(DEBUG_OUTPUT_FILE); end

fprintf('=== Writing %d metadata channels ===\n', numel(ch));
fprintf('  %s\n\n', DEBUG_OUTPUT_FILE);
try
    ld_add_channel(DASH_FILE, DEBUG_OUTPUT_FILE, ch);
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

out_struct = motec_ld_reader(DEBUG_OUTPUT_FILE);
out_fns    = fieldnames(out_struct);

fprintf('%-20s  %10s  %8s  %8s  %s\n', 'Channel', 'Value', 'readback', 'error', 'Status');
fprintf('%s\n', repmat('-', 1, 70));

results = struct();

for mci = 1:numel(meta_fns)
    mfn  = meta_fns{mci};
    mval = ch(mci).value;

    target_san = san(ch(mci).name);
    match_fn   = '';
    for fi = 1:numel(out_fns)
        if strcmpi(out_fns{fi}, target_san) || ...
           strcmpi(out_fns{fi}, regexprep(target_san, '_+$', ''))
            match_fn = out_fns{fi};
            break;
        end
    end

    readback_val = NaN;
    if ~isempty(match_fn)
        readback_val = out_struct.(match_fn).data(1);
    end

    readback_err = abs(readback_val - mval);
    if isnan(readback_val)
        status = 'READ FAIL';
    elseif readback_err <= 0.5 / 10^ch(mci).dec_places + 1e-9
        status = 'PASS';
    else
        status = sprintf('FAIL (err=%.4f)', readback_err);
    end

    fprintf('%-20s  %10.4f  %8.4f  %8.4f  %s\n', ch(mci).name, mval, readback_val, readback_err, status);

    results.(mfn).readback_val = readback_val;
    results.(mfn).readback_err = readback_err;
    results.(mfn).status       = status;
end

fprintf('%s\n', repmat('-', 1, 70));

%% =========================================================
%  SUMMARY
%% =========================================================
n_pass = sum(cellfun(@(f) strcmp(results.(f).status, 'PASS'), fieldnames(results)));
n_fail = numel(meta_fns) - n_pass;

fprintf('\nSummary: %d / %d PASS', n_pass, numel(meta_fns));
if n_fail > 0
    fprintf('  ← %d FAILED\n', n_fail);
    for mci = 1:numel(meta_fns)
        mfn = meta_fns{mci};
        if ~strcmp(results.(mfn).status, 'PASS')
            fprintf('  %-20s  value=%.4f  readback=%.4f  err=%.4f\n', ...
                ch(mci).name, ch(mci).value, results.(mfn).readback_val, results.(mfn).readback_err);
        end
    end
else
    fprintf(' — all channels encode correctly.\n');
end

fprintf('\nOutput file (open in i2):\n  %s\n', DEBUG_OUTPUT_FILE);
