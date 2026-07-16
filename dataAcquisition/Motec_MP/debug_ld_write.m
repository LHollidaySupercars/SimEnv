%% debug_ld_write.m
% Iterative LD write debugger.
%
% PURPOSE
% -------
% Diagnose gaps / time offsets that appear in i2 Pro after writing .ld files.
% The script works in 5 phases:
%
%   Phase 1  Walk every channel metadata record in the SOURCE file.
%            Print a table of: name, Hz, sr_raw, unk1, datatype, data_len,
%            implied_dur.  Compute "canonical session duration" (mode of
%            implied_dur for channels >= 25 Hz).  Flag outliers.
%
%   Phase 2  Print per-Hz donor summary exactly as ld_add_channel picks them.
%            Show what sr_raw / unk1 each new channel will inherit.
%            Flag Hz values where donor_n/Hz diverges from canonical_dur.
%
%   Phase 3  Write 6 synthetic test channels to a copy of the source file.
%            Each channel probes a specific boundary condition.
%
%   Phase 4  Read back the 6 appended channels and print a gap/overshoot
%            diagnosis table + metadata detail (sr_raw, unk1, etc.).
%
%   Phase 5  Single figure with one subplot per test channel.
%            Vertical markers at canonical session end and channel end so
%            gaps/overshoots are immediately visible.
%
% USAGE
% -----
%   Set source_ld_file before running, or define nothing and use the picker.
%
%     source_ld_file = 'E:\2026\T01_QLR\Dash\20260505-156890002.ld';
%     run debug_ld_write
%
% OUTPUT
% ------
%   <source>_debug_output.ld  — copy of source with 6 test channels appended.
%   Open this in i2 Pro to see which test cases are gapped/shifted.

clear; clc; close all;

%% =========================================================
%  CONFIG
%% =========================================================

% Define source_ld_file before running, or leave unset for file picker.
if ~exist('source_ld_file', 'var') || isempty(source_ld_file)
    [fn, fd] = uigetfile('*.ld', 'Select source .ld file');
    if isequal(fn, 0)
        error('No file selected.');
    end
    source_ld_file = fullfile(fd, fn);
end

[src_dir, src_base, ~] = fileparts(source_ld_file);
output_ld_file = fullfile(src_dir, [src_base '_debug_output.ld']);

fprintf('\n============================================================\n');
fprintf('  LD WRITE DEBUGGER\n');
fprintf('  Source : %s\n', source_ld_file);
fprintf('  Output : %s\n', output_ld_file);
fprintf('============================================================\n\n');

% Ensure ld_add_channel is on path
ch_add_dir = fullfile(fileparts(mfilename('fullpath')), 'channelAdd');
if exist(ch_add_dir, 'dir') && ~any(strcmp(strsplit(path, pathsep), ch_add_dir))
    addpath(ch_add_dir);
end

%% =========================================================
%  PHASE 1: Walk source file — channel metadata table
%% =========================================================
fprintf('============================================================\n');
fprintf('  PHASE 1: Source File Metadata\n');
fprintf('============================================================\n\n');

fid = fopen(source_ld_file, 'rb');
if fid < 0, error('Cannot open: %s', source_ld_file); end
fseek(fid, 0, 'eof');
file_sz = ftell(fid);
fseek(fid, 0x0008, 'bof');
first_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
fclose(fid);

channels = walk_metadata(source_ld_file, file_sz, first_ptr);
n_ch = numel(channels);
fprintf('  Total channels in source: %d\n\n', n_ch);

% Print table
fprintf('%-4s  %-35s  %5s  %6s  %6s  %5s  %8s  %8s\n', ...
    'Idx', 'Name', 'Hz', 'sr_raw', 'unk1', 'dtype', 'data_len', 'dur_s');
fprintf('%s\n', repmat('-', 1, 88));

implied_dur = zeros(n_ch, 1);
for i = 1:n_ch
    ch  = channels(i);
    dur = 0;
    if ch.sample_rate > 0
        dur = ch.data_len / ch.sample_rate;
    end
    implied_dur(i) = dur;
    fprintf('%-4d  %-35s  %5g  %6d  0x%04X  %5d  %8d  %8.3f\n', ...
        i, ch.raw_name, ch.sample_rate, ch.sr_raw, ch.unk1, ...
        ch.datatype, ch.data_len, dur);
end

% --- Canonical session duration ---
% Use MODE of implied_dur for high-Hz channels (>= 25 Hz).
% These channels are densely sampled and tightly representative.
% Contrast with ld_add_channel's session_dur = MAX(ch_n/sr) across all
% channels — that is inflated by low-Hz channels with rounding surplus.
high_hz_mask = [channels.sample_rate] >= 25;
if any(high_hz_mask)
    high_durs    = implied_dur(high_hz_mask);
    rounded      = round(high_durs * 100) / 100;   % 0.01s precision
    canonical_dur = mode(rounded);
else
    canonical_dur = max(implied_dur);
end

% ld_add_channel's actual session_dur = max(ch_n/sr) across ALL channels
session_dur_ldadd = max(implied_dur);

fprintf('\n  Canonical dur    (mode, Hz >= 25Hz) : %.4f s\n', canonical_dur);
fprintf('  session_dur used by ld_add_channel  : %.4f s  (max across all channels)\n', ...
    session_dur_ldadd);
delta_sd = session_dur_ldadd - canonical_dur;
if abs(delta_sd) > 0.05
    fprintf('  *** WARNING: ld_add_channel session_dur is %.4fs longer than canonical.\n', delta_sd);
    fprintf('      Synthetic donors will be given n = round(near_n * Hz/near_Hz)\n');
    fprintf('      which is referenced to the nearest REAL donor, not session_dur.\n');
    fprintf('      But scalar channels get donor_n from the donor channel directly.\n');
    fprintf('      If donor_n/Hz != canonical_dur, scalar channels will have a gap.\n\n');
else
    fprintf('  (session_dur agrees with canonical — no inflation detected)\n\n');
end

fprintf('  Channels with implied_dur deviating > 0.1s from canonical:\n');
any_flag = false;
for i = 1:n_ch
    ch    = channels(i);
    delta = implied_dur(i) - canonical_dur;
    if abs(delta) > 0.1
        fprintf('  [FLAG] %-35s  Hz=%g  dur=%.3fs  delta=%+.3fs\n', ...
            ch.raw_name, ch.sample_rate, implied_dur(i), delta);
        any_flag = true;
    end
end
if ~any_flag
    fprintf('  (none — all channels within 0.1s of canonical)\n');
end

%% =========================================================
%  PHASE 2: Per-Hz donor summary
%% =========================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 2: Per-Hz Donor Summary\n');
fprintf('  (showing what sr_raw / unk1 new channels will INHERIT)\n');
fprintf('============================================================\n\n');

hz_list_all = unique([channels.sample_rate]);
hz_list_all = sort(hz_list_all(hz_list_all > 0));

fprintf('%-6s  %-35s  %6s  %6s  %5s  %8s  %8s  %9s\n', ...
    'Hz', 'Donor name', 'sr_raw', 'unk1', 'dtype', 'data_len', 'dur_s', 'vs_canon');
fprintf('%s\n', repmat('-', 1, 95));

donor_hz_map = struct();   % donor_hz_map.Hz_NNN = channel struct

for k = 1:numel(hz_list_all)
    hz       = hz_list_all(k);
    best_n   = 0;
    best_u1  = 0;
    best_ch  = [];

    for i = 1:n_ch
        ch = channels(i);
        if ch.sample_rate ~= hz || ch.data_len == 0, continue; end
        % Prefer highest data_len; break ties by preferring unk1 == 3
        if ch.data_len > best_n || ...
                (ch.data_len == best_n && ch.unk1 == 3 && best_u1 ~= 3)
            best_n  = ch.data_len;
            best_u1 = ch.unk1;
            best_ch = ch;
        end
    end

    if isempty(best_ch), continue; end

    donor_dur = best_ch.data_len / hz;
    vs_canon  = donor_dur - canonical_dur;
    flag_str  = '';
    if abs(vs_canon) > 1/hz
        flag_str = '  <-- MISMATCH (scalar ch will have gap/overshoot)';
    end

    fprintf('%-6g  %-35s  %6d  0x%04X  %5d  %8d  %8.3f  %+9.4f%s\n', ...
        hz, best_ch.raw_name, best_ch.sr_raw, best_ch.unk1, ...
        best_ch.datatype, best_ch.data_len, donor_dur, vs_canon, flag_str);

    fkey = sprintf('Hz_%d', hz);
    donor_hz_map.(fkey) = best_ch;
end

%% =========================================================
%  PHASE 3: Write synthetic test channels
%% =========================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 3: Writing Synthetic Test Channels\n');
fprintf('============================================================\n\n');

% Choose test Hz values that are present in the file.
% High Hz (>= 100 Hz) for tests A-D.  Mid-range for E.  1 Hz for F.
hz_present = hz_list_all;

if any(hz_present >= 100)
    test_hz_high = hz_present(find(hz_present >= 100, 1));
elseif ~isempty(hz_present)
    test_hz_high = max(hz_present);
else
    test_hz_high = 100;
end

if numel(hz_present) >= 2
    test_hz_mid = hz_present(ceil(numel(hz_present) / 2));
else
    test_hz_mid = test_hz_high;
end

% donor_n = data_len from the best donor at that Hz
fkey_high = sprintf('Hz_%d', test_hz_high);
if isfield(donor_hz_map, fkey_high)
    donor_n_high = donor_hz_map.(fkey_high).data_len;
else
    donor_n_high = round(canonical_dur * test_hz_high);
end

fkey_mid = sprintf('Hz_%d', test_hz_mid);
if isfield(donor_hz_map, fkey_mid)
    donor_n_mid = donor_hz_map.(fkey_mid).data_len;
else
    donor_n_mid = round(canonical_dur * test_hz_mid);
end

fprintf('  High-Hz test rate : %g Hz  donor_n=%d  donor_dur=%.4fs  canon=%.4fs\n', ...
    test_hz_high, donor_n_high, donor_n_high/test_hz_high, canonical_dur);
fprintf('  Mid-Hz  test rate : %g Hz  donor_n=%d  donor_dur=%.4fs  canon=%.4fs\n', ...
    test_hz_mid,  donor_n_mid,  donor_n_mid/test_hz_mid,  canonical_dur);
if test_hz_high == test_hz_mid
    fprintf('  (only one Hz rate found in file — mid and high tests use same rate)\n');
end
fprintf('\n');

% ---- Build test channel list ----
test_channels = {};

% Test A: SCALAR at high Hz.
%   ld_add_channel internally uses donor_n for scalars.
%   Gap at end = (canonical_dur - donor_n/Hz).
%   This is the most common culprit when donors are 1 sample long/short.
chA.name        = 'DBG_A_scalar_highHz';
chA.units       = 'unit';
chA.value       = 42.0;           % scalar → ld_add_channel uses donor_n
chA.sample_rate = test_hz_high;
chA.datatype    = 2;
chA.dec_places  = 2;
chA.offset      = 0;
chA.mul         = 1;
chA.scale       = 1;
test_channels{end+1} = chA;

% Test B: VECTOR — exactly donor_n samples at high Hz.
%   Should be identical duration to donor channel.
%   Expected: no gap if donor_n/Hz == canonical_dur.
chB.name        = 'DBG_B_ramp_donorN';
chB.units       = 'unit';
chB.value       = linspace(0, 1, donor_n_high)';
chB.sample_rate = test_hz_high;
chB.datatype    = 2;
chB.dec_places  = 4;
chB.offset      = 0;
chB.mul         = 1;
chB.scale       = 1;
test_channels{end+1} = chB;

% Test C: VECTOR — donor_n - 1 samples (intentionally short by 1).
%   Expected gap = 1/Hz seconds at end.  Use this as a calibration
%   reference — if Test B shows no gap in i2 but Test C does, then
%   your gap is exactly 1 sample.
n_short = max(1, donor_n_high - 1);
chC.name        = 'DBG_C_ramp_short1';
chC.units       = 'unit';
chC.value       = linspace(0, 1, n_short)';
chC.sample_rate = test_hz_high;
chC.datatype    = 2;
chC.dec_places  = 4;
chC.offset      = 0;
chC.mul         = 1;
chC.scale       = 1;
test_channels{end+1} = chC;

% Test D: VECTOR — donor_n + 1 samples (intentionally long by 1).
%   Expected to overshoot canonical_dur by 1/Hz seconds.
n_long = donor_n_high + 1;
chD.name        = 'DBG_D_ramp_long1';
chD.units       = 'unit';
chD.value       = linspace(0, 1, n_long)';
chD.sample_rate = test_hz_high;
chD.datatype    = 2;
chD.dec_places  = 4;
chD.offset      = 0;
chD.mul         = 1;
chD.scale       = 1;
test_channels{end+1} = chD;

% Test E: SINE WAVE at mid Hz with donor_n_mid samples.
%   Tests a different Hz rate and donor.
t_mid = (0 : donor_n_mid - 1)' / test_hz_mid;
chE.name        = 'DBG_E_sine_midHz';
chE.units       = 'unit';
chE.value       = sin(2 * pi * 0.5 * t_mid);  % 0.5 Hz sine
chE.sample_rate = test_hz_mid;
chE.datatype    = 2;
chE.dec_places  = 4;
chE.offset      = 0;
chE.mul         = 1;
chE.scale       = 1;
test_channels{end+1} = chE;

% Test F: CONSTANT at 1 Hz.
%   Exercises the SYNTHETIC DONOR code path in ld_add_channel when 1 Hz
%   channels are not present in the source file.
%   If they ARE present, exercises that real donor.
n_1hz = max(1, round(canonical_dur));
chF.name        = 'DBG_F_const_1Hz';
chF.units       = 'unit';
chF.value       = ones(n_1hz, 1) * 99.0;
chF.sample_rate = 1;
chF.datatype    = 2;
chF.dec_places  = 0;
chF.offset      = 0;
chF.mul         = 1;
chF.scale       = 1;
test_channels{end+1} = chF;

n_test = numel(test_channels);
fprintf('  Test channels: %d\n', n_test);
for i = 1:n_test
    tc = test_channels{i};
    if isscalar(tc.value)
        nc = donor_n_high;
        nstr = sprintf('scalar -> donor_n=%d', nc);
    else
        nc   = numel(tc.value);
        nstr = sprintf('vector n=%d', nc);
    end
    fprintf('  Test %s: %-25s  Hz=%g  %s  dur=%.4fs\n', ...
        char('A' + i - 1), tc.name, tc.sample_rate, nstr, nc/tc.sample_rate);
end
fprintf('\n');

% Write via ld_add_channel (copies source to output internally)
fprintf('  Calling ld_add_channel...\n\n');
ld_add_channel(source_ld_file, output_ld_file, test_channels);

%% =========================================================
%  PHASE 4: Read back appended channels — gap diagnosis
%% =========================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 4: Read-back and Gap Diagnosis\n');
fprintf('============================================================\n\n');

d_out      = dir(output_ld_file);
out_sz     = d_out.bytes;
fid_out    = fopen(output_ld_file, 'rb');
fseek(fid_out, 0x0008, 'bof');
out_first  = fread(fid_out, 1, 'uint32=>double', 0, 'l');
fclose(fid_out);

out_channels = walk_metadata(output_ld_file, out_sz, out_first);
n_out = numel(out_channels);

if n_out < n_test
    warning('Output has %d channels, expected at least %d.', n_out, n_ch + n_test);
    test_written = out_channels;
else
    test_written = out_channels(n_out - n_test + 1 : n_out);
end

% Gap table
fprintf('%-3s  %-25s  %5s  %8s  %8s  %+8s  %8s  %-s\n', ...
    'ID', 'Name', 'Hz', 'n_writ', 'dur_s', 'gap_s', 'n_ideal', 'Status');
fprintf('%s\n', repmat('-', 1, 98));

results(n_test) = struct('name', '', 'sr', 0, 'n_written', 0, ...
    'dur_written', 0, 'gap_s', 0, 'data_ptr', 0, 'datatype', 0, ...
    'dec_places', 0, 'ch_offset', 0, 'ch_mul', 0, 'ch_scale', 0, ...
    'sr_raw', 0, 'unk1', 0);

for i = 1:numel(test_written)
    tw = test_written(i);
    sr = tw.sample_rate;

    if sr > 0
        dur_written = tw.data_len / sr;
        n_ideal     = round(canonical_dur * sr);
        gap_s       = canonical_dur - dur_written;
        tol_s       = 0.5 / sr;   % half a sample = rounding tolerance

        if abs(gap_s) <= tol_s
            status = 'OK';
        elseif gap_s > 0
            status = sprintf('GAP  %+.4fs  (%.1f samp)', gap_s, gap_s * sr);
        else
            status = sprintf('OVER %+.4fs  (%.1f samp)', gap_s, gap_s * sr);
        end
    else
        dur_written = 0;
        n_ideal     = 0;
        gap_s       = 0;
        status      = 'Hz=0?';
    end

    fprintf('%-3s  %-25s  %5g  %8d  %8.3f  %+8.4f  %8d  %s\n', ...
        char('A' + i - 1), tw.raw_name, sr, tw.data_len, ...
        dur_written, gap_s, n_ideal, status);

    results(i).name        = tw.raw_name;
    results(i).sr          = sr;
    results(i).n_written   = tw.data_len;
    results(i).dur_written = dur_written;
    results(i).gap_s       = gap_s;
    results(i).data_ptr    = tw.data_ptr;
    results(i).datatype    = tw.datatype;
    results(i).dec_places  = tw.dec_places;
    results(i).ch_offset   = tw.ch_offset;
    results(i).ch_mul      = tw.ch_mul;
    results(i).ch_scale    = tw.ch_scale;
    results(i).sr_raw      = tw.sr_raw;
    results(i).unk1        = tw.unk1;
end

fprintf('\n  Canonical duration used as reference: %.4f s\n', canonical_dur);

% Metadata detail — sr_raw and unk1 are the fields i2 Pro likely uses
fprintf('\n  --- Metadata detail (sr_raw / unk1 are INHERITED from donor) ---\n\n');
fprintf('%-3s  %-25s  %6s  %6s  %5s  %5s  %5s  %5s\n', ...
    'ID', 'Name', 'sr_raw', 'unk1', 'dtype', 'mul', 'scale', 'dec');
fprintf('%s\n', repmat('-', 1, 75));
for i = 1:numel(test_written)
    tw = test_written(i);
    fprintf('%-3s  %-25s  %6d  0x%04X  %5d  %5d  %5d  %5d\n', ...
        char('A' + i - 1), tw.raw_name, tw.sr_raw, tw.unk1, ...
        tw.datatype, tw.ch_mul, tw.ch_scale, tw.dec_places);
end

% Cross-reference sr_raw against what's present in the source
fprintf('\n  --- sr_raw cross-reference (should match source channels at same Hz) ---\n\n');
for i = 1:numel(results)
    r   = results(i);
    fkey = sprintf('Hz_%d', r.sr);
    if isfield(donor_hz_map, fkey)
        d_sr_raw = donor_hz_map.(fkey).sr_raw;
        if r.sr_raw == d_sr_raw
            match = 'MATCH donor';
        else
            match = sprintf('MISMATCH  donor_sr_raw=%d  ch_sr_raw=%d  <-- may cause i2 offset', ...
                d_sr_raw, r.sr_raw);
        end
    else
        match = sprintf('(synthetic donor — no real %g Hz channel in source)', r.sr);
    end
    fprintf('  Test %s  %-25s  sr_raw=%-6d  %s\n', ...
        char('A' + i - 1), r.name, r.sr_raw, match);
end

%% =========================================================
%  PHASE 5: Diagnostic figure
%% =========================================================
fprintf('\n============================================================\n');
fprintf('  PHASE 5: Diagnostic Figure\n');
fprintf('============================================================\n\n');

n_plots = numel(results);
n_cols  = 2;
n_rows  = ceil(n_plots / n_cols);

fig = figure('Color', 'white', ...
    'Position', [40 40 1400 max(180 * n_rows, 400)], ...
    'Name', 'LD Write Debug');
sgtitle(fig, ...
    sprintf('LD Write Debug  |  Canon dur = %.4fs  |  %s', canonical_dur, src_base), ...
    'Interpreter', 'none', 'FontSize', 10);

col_ok   = [0.07 0.50 0.12];
col_gap  = [0.80 0.08 0.08];
col_over = [0.70 0.35 0.00];

for i = 1:n_plots
    r  = results(i);
    ax = subplot(n_rows, n_cols, i);
    hold(ax, 'on');
    box(ax,  'on');
    grid(ax, 'on');
    set(ax, 'GridAlpha', 0.25, 'GridLineStyle', '--');

    % Read data back from output file
    [rb_data, rb_ok] = read_channel_data(output_ld_file, r.data_ptr, r.n_written, ...
        r.datatype, r.ch_offset, r.ch_mul, r.ch_scale, r.dec_places);

    if rb_ok && ~isempty(rb_data)
        t_rb = (0 : r.n_written - 1)' / r.sr;
        plot(ax, t_rb, rb_data, 'Color', [0.15 0.45 0.75], 'LineWidth', 1.0);
    else
        text(ax, 0.5, 0.5, 'readback error', 'Units', 'normalized', ...
            'HorizontalAlignment', 'center', 'Color', col_gap);
    end

    % Canonical end line (solid black)
    xl = xline(ax, canonical_dur, '-k', 'LineWidth', 1.4);
    xl.Label              = 'Canon end';
    xl.LabelVerticalAlignment = 'bottom';
    xl.LabelHorizontalAlignment = 'right';

    % Channel end line — only if it differs by > 0.5 samples
    ch_end = r.n_written / r.sr;
    if abs(ch_end - canonical_dur) > 0.5 / r.sr
        xl2 = xline(ax, ch_end, '--r', 'LineWidth', 1.2);
        xl2.Label                    = 'Ch end';
        xl2.LabelVerticalAlignment   = 'top';
        xl2.LabelHorizontalAlignment = 'left';
    end

    % Title colour reflects gap status
    tol_s = 0.5 / r.sr;
    if abs(r.gap_s) <= tol_s
        tclr  = col_ok;
        tstr  = 'OK';
    elseif r.gap_s > 0
        tclr  = col_gap;
        tstr  = sprintf('GAP %.4fs  (%.1f samp)', r.gap_s, r.gap_s * r.sr);
    else
        tclr  = col_over;
        tstr  = sprintf('OVER %.4fs  (%.1f samp)', -r.gap_s, -r.gap_s * r.sr);
    end

    title(ax, sprintf('Test %s: %s  [%s]', char('A' + i - 1), r.name, tstr), ...
        'Interpreter', 'none', 'Color', tclr, 'FontSize', 8, 'FontWeight', 'bold');
    xlabel(ax, 'Time (s)', 'FontSize', 8);
    ylabel(ax, 'Value', 'FontSize', 8);
end

fprintf('  Figure ready.\n');
fprintf('\n  Next steps:\n');
fprintf('  1. Check figure — Test B should be "OK" if donors are clean.\n');
fprintf('  2. Test C should show GAP ~%.4fs (1 sample).\n', 1/test_hz_high);
fprintf('  3. Test D should show OVER ~%.4fs (1 sample).\n', 1/test_hz_high);
fprintf('  4. If Test A (scalar) shows a gap, the donor_n for %g Hz is wrong.\n', test_hz_high);
fprintf('  5. If sr_raw MISMATCH was reported in Phase 4, that is a likely i2 cause.\n');
fprintf('\n  Open in i2 Pro: %s\n\n', output_ld_file);
fprintf('============================================================\n');
fprintf('  DONE\n');
fprintf('============================================================\n');


%% =========================================================
%  LOCAL FUNCTIONS
%% =========================================================

function channels = walk_metadata(filepath, file_sz, first_ptr)
% Walk all channel metadata records and return a struct array.
% Reads 84 bytes per record exactly as the binary spec defines.
    fid = fopen(filepath, 'rb');
    if fid < 0, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    channels    = struct([]);
    current_ptr = first_ptr;
    idx         = 0;

    while current_ptr ~= 0 && current_ptr < file_sz
        fseek(fid, current_ptr, 'bof');

        fread(fid, 1, 'uint32=>double', 0, 'l');               % prev_ptr (unused here)
        next_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_len    = fread(fid, 1, 'uint32=>double', 0, 'l');
        sr_raw      = fread(fid, 1, 'uint16=>double', 0, 'l');
        unk1        = fread(fid, 1, 'uint16=>double', 0, 'l');
        datatype    = fread(fid, 1, 'uint16=>double', 0, 'l');
        sample_rate = fread(fid, 1, 'uint16=>double', 0, 'l');
        ch_offset   = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_mul      = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_scale    = fread(fid, 1, 'int16=>double',  0, 'l');
        dec_places  = fread(fid, 1, 'int16=>double',  0, 'l');
        name_raw    = fread(fid, 32, 'uint8=>double')';
        fread(fid, 8,  'uint8=>double');                        % short_name
        fread(fid, 12, 'uint8=>double');                        % units

        idx = idx + 1;
        channels(idx).meta_ptr    = current_ptr;
        channels(idx).data_ptr    = data_ptr;
        channels(idx).data_len    = data_len;
        channels(idx).sr_raw      = sr_raw;
        channels(idx).unk1        = unk1;
        channels(idx).datatype    = datatype;
        channels(idx).sample_rate = sample_rate;
        channels(idx).ch_offset   = ch_offset;
        channels(idx).ch_mul      = ch_mul;
        channels(idx).ch_scale    = ch_scale;
        channels(idx).dec_places  = dec_places;
        channels(idx).raw_name    = raw_to_str(name_raw);

        current_ptr = next_ptr;
        if idx > 5000
            warning('walk_metadata: 5000 channel limit reached.');
            break;
        end
    end
end


function str = raw_to_str(d)
% Convert uint8 double-array to null-terminated string.
    nul = find(d == 0, 1);
    if isempty(nul)
        str = strtrim(char(d));
    elseif nul == 1
        str = '';
    else
        str = strtrim(char(d(1 : nul - 1)));
    end
end


function [phys, ok] = read_channel_data(filepath, data_ptr, n, ...
        datatype, offset, mul, scale, dec)
% Read n samples of physical data from an ld file at data_ptr.
    phys = [];
    ok   = false;
    if n == 0 || data_ptr == 0, return; end
    try
        fid = fopen(filepath, 'rb');
        if fid < 0, return; end
        cl = onCleanup(@() fclose(fid));
        fseek(fid, data_ptr, 'bof');
        switch datatype
            case 1
                u16  = fread(fid, n, 'uint16=>double', 0, 'l');
                phys = float16_to_double(u16);
            case 2
                raw  = fread(fid, n, 'int16=>double', 0, 'l');
                if scale ~= 0 && mul ~= 0
                    phys = raw .* (mul / scale) ./ (10^dec) + offset;
                else
                    phys = raw ./ (10^dec) + offset;
                end
            case 3
                raw  = fread(fid, n, 'int32=>double', 0, 'l');
                if scale ~= 0 && mul ~= 0
                    phys = raw .* (mul / scale) ./ (10^dec) + offset;
                else
                    phys = raw ./ (10^dec) + offset;
                end
            case 4
                raw  = fread(fid, n, 'int16=>double', 2, 'l');
                phys = raw ./ (10^dec) + offset;
            otherwise
                return;
        end
        ok = true;
    catch
        ok = false;
    end
end


function out = float16_to_double(u16)
% Decode IEEE 754 half-precision uint16 array to double.
    sign_b = bitshift(bitand(u16, uint16(32768)), -15);
    exp_b  = bitshift(bitand(u16, uint16(31744)), -10);
    frac_b = double(bitand(u16, uint16(1023)));
    out    = zeros(size(u16));

    nm = (exp_b > 0) & (exp_b < 31);
    out(nm) = (-1).^double(sign_b(nm)) .* 2.^(double(exp_b(nm)) - 15) .* ...
              (1 + frac_b(nm) / 1024);

    sn = (exp_b == 0) & (frac_b ~= 0);
    out(sn) = (-1).^double(sign_b(sn)) .* 2^-14 .* (frac_b(sn) / 1024);

    inf_mask = (exp_b == 31) & (frac_b == 0);
    out(inf_mask) = Inf .* (-1).^double(sign_b(inf_mask));

    out((exp_b == 31) & (frac_b ~= 0)) = NaN;
end
