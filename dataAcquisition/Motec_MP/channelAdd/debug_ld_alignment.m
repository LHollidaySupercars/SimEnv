%% debug_ld_alignment.m
% Dumps channel timing + encoding metadata from a .ld file.
% Run this and paste the full output back — used to diagnose:
%   (1) Time alignment: which channel inflates session_dur and by how much
%   (2) Encoding formula: raw bytes + decoded value vs expected physical value
%   (3) donor_n per Hz: what n will be used for each custom channel rate
%   (4) unk1 field per channel (may affect i2 Pro time positioning)
%   (5) Full 84-byte donor record for the custom channel Hz
%   (6) Walk of the OUTPUT file to verify the custom channel as actually written

clear; clc;

%% =========================================================
%  CONFIG
%% =========================================================
SOURCE_FILE    = 'E:\2026\T01_QLR\Dash\20260505-156890002.ld';

% OUTPUT file produced by debug_decimal_encoding / run_metadata_channels.
% Set to '' to skip output-file walk.
OUTPUT_FILE    = 'E:\2026\T01_QLR\COM\debug_decimal_encoding.ld';

% Hz of your custom channel — full donor record will be dumped for this rate.
CUSTOM_HZ      = 5;

% A native channel name whose value you know (for formula ground-truth).
% Set to '' to skip formula check.
KNOWN_CHANNEL  = 'Engine Speed';   % <-- change to any channel you can verify in i2 Pro
KNOWN_EXPECTED = 0;                % <-- physical value you see in i2 Pro at the cursor point
                                   %     (set to 0 if skipping)

%% =========================================================
%  HELPERS
%% =========================================================
META_BYTES = 84;



%% =========================================================
%  WALK SOURCE FILE
%% =========================================================
fprintf('============================================================\n');
fprintf('  SOURCE: %s\n', SOURCE_FILE);
fprintf('============================================================\n\n');

[src, src_count, src_sz] = walk_file(SOURCE_FILE);

fprintf('%-4s  %-32s  %5s  %6s  %8s  %5s  %6s  %5s  %5s  %4s  %6s  %6s\n', ...
    '#', 'Name', 'Hz', 'n', 'dur(s)', 'dtype', 'unk1', 'mul', 'scale', 'dec', 'offset', 'sr_raw');
fprintf('%s\n', repmat('-', 1, 115));

max_dur = 0; max_dur_name = '';
for i = 1:src_count
    s = src(i);
    if s.dur > max_dur, max_dur = s.dur; max_dur_name = s.name; end
    fprintf('%-4d  %-32s  %5d  %6d  %8.2f  %5d  0x%04X  %5d  %5d  %4d  %6d  %6d\n', ...
        i, s.name, s.sr, s.n, s.dur, s.datatype, s.unk1, s.mul, s.scale, s.dec, s.offset, s.sr_raw);
end
fprintf('\n  Total: %d channels    session_dur: %.4f s  ["%s"]\n', src_count, max_dur, max_dur_name);

%% =========================================================
%  DONOR MAP + TIME ALIGNMENT
%% =========================================================
fprintf('\n============================================================\n');
fprintf('  DONOR MAP  (src channels only)\n');
fprintf('============================================================\n');
fprintf('%-6s  %8s  %10s  %6s  %-32s\n', 'Hz', 'donor_n', 'dur(s)', 'unk1', 'donor_name');
fprintf('%s\n', repmat('-', 1, 72));

dn_map  = containers.Map('KeyType','double','ValueType','double');
dname_m = containers.Map('KeyType','double','ValueType','any');
ddur_m  = containers.Map('KeyType','double','ValueType','double');
dunk_m  = containers.Map('KeyType','double','ValueType','double');
drec_m  = containers.Map('KeyType','double','ValueType','any');

for i = 1:src_count
    sr = src(i).sr; n = src(i).n;
    if sr>0 && n>0
        best = 0; if isKey(dn_map,sr), best=dn_map(sr); end
        if n > best
            dn_map(sr)  = n; dname_m(sr) = src(i).name;
            ddur_m(sr)  = n/sr; dunk_m(sr) = src(i).unk1;
            drec_m(sr)  = src(i).rec;
        end
    end
end

hz_list = sort(cell2mat(keys(dn_map)));
for i = 1:numel(hz_list)
    hz = hz_list(i);
    fprintf('%-6d  %8d  %10.3f  0x%04X  %-32s\n', hz, dn_map(hz), ddur_m(hz), dunk_m(hz), dname_m(hz));
end

fprintf('\n  Per-Hz alignment (old session_dur vs donor_n):\n');
fprintf('  %-6s  %10s  %10s  %12s\n', 'Hz', 'old_n', 'donor_n', 'delta_smpl');
fprintf('  %s\n', repmat('-',1,48));
for i = 1:numel(hz_list)
    hz = hz_list(i); dn = dn_map(hz); old_n = round(max_dur*hz);
    delta = old_n - dn; flag = '';
    if abs(delta)>0, flag = sprintf('  *** %+d = %+.3fs', delta, delta/hz); end
    fprintf('  %-6d  %10d  %10d%s\n', hz, old_n, dn, flag);
end

%% =========================================================
%  FULL DONOR RECORD for CUSTOM_HZ
%% =========================================================
fprintf('\n============================================================\n');
fprintf('  DONOR FULL RECORD — %d Hz\n', CUSTOM_HZ);
fprintf('============================================================\n');
if isKey(drec_m, double(CUSTOM_HZ))
    rec_d = drec_m(double(CUSTOM_HZ));
    fprintf('  Byte  Hex   Dec    Field\n');
    field_labels = {'1-4:prev_ptr','5-8:next_ptr','9-12:data_ptr','13-16:data_len', ...
                    '17-18:sr_raw','19-20:unk1','21-22:datatype','23-24:sample_rate', ...
                    '25-26:offset','27-28:mul','29-30:scale','31-32:dec'};
    byte_ranges = {1:4,5:8,9:12,13:16,17:18,19:20,21:22,23:24,25:26,27:28,29:30,31:32};
    for fi = 1:numel(byte_ranges)
        br = byte_ranges{fi};
        hex_s = sprintf('%02X ', rec_d(br));
        switch numel(br)
            case 4; val = double(typecast(uint8(rec_d(br)),'uint32'));
            case 2; val = double(typecast(uint8(rec_d(br)),'uint16'));
            otherwise; val = 0;
        end
        fprintf('  [%5s]  %s  = %d  (%s)\n', sprintf('%d-%d',br(1),br(end)), hex_s, val, field_labels{fi});
    end
    fprintf('  Name  (33-64): "%s"\n', strtrim(char(rec_d(33:64))));
    fprintf('  Short (65-72): "%s"\n', strtrim(char(rec_d(65:72))));
    fprintf('  Units (73-84): "%s"\n', strtrim(char(rec_d(73:84))));
    fprintf('  sr_raw overflow check (uint16 max=65535): %d Hz -> computed_sr_raw=%d  %s\n', ...
        CUSTOM_HZ, round(1e6/CUSTOM_HZ/10), iif(round(1e6/CUSTOM_HZ/10)>65535,'*** OVERFLOW!','OK'));
else
    fprintf('  No donor at %d Hz in source file.\n', CUSTOM_HZ);
end

%% =========================================================
%  WALK OUTPUT FILE (if provided)
%% =========================================================
if ~isempty(OUTPUT_FILE) && exist(OUTPUT_FILE, 'file')
    fprintf('\n============================================================\n');
    fprintf('  OUTPUT FILE WALK — custom channels only\n');
    fprintf('  %s\n', OUTPUT_FILE);
    fprintf('============================================================\n');

    [out, out_count, ~] = walk_file(OUTPUT_FILE);

    % Find channels NOT in source (i.e. custom-added)
    src_names_lc = lower({src(1:src_count).name});
    fprintf('%-4s  %-32s  %5s  %6s  %8s  %5s  %6s  %5s  %5s  %4s  %6s  %6s\n', ...
        '#', 'Name', 'Hz', 'n', 'dur(s)', 'dtype', 'unk1', 'mul', 'scale', 'dec', 'offset', 'sr_raw');
    fprintf('%s\n', repmat('-', 1, 115));

    n_custom = 0;
    for i = 1:out_count
        if ~ismember(lower(out(i).name), src_names_lc)
            n_custom = n_custom + 1;
            o = out(i);
            % Compare n to what donor_n would give
            expected_n = 0;
            if isKey(dn_map, double(o.sr)), expected_n = dn_map(double(o.sr)); end
            delta_n = o.n - expected_n;
            flag = '';
            if abs(delta_n) > 0, flag = sprintf('  *** n delta=%+d vs donor', delta_n); end
            fprintf('%-4d  %-32s  %5d  %6d  %8.2f  %5d  0x%04X  %5d  %5d  %4d  %6d  %6d%s\n', ...
                n_custom, o.name, o.sr, o.n, o.dur, o.datatype, o.unk1, o.mul, o.scale, o.dec, o.offset, o.sr_raw, flag);
        end
    end
    if n_custom == 0
        fprintf('  (no custom channels found — all names match source)\n');
    end

    % Session duration of output vs source
    max_dur_out = max([out(1:out_count).dur]);
    fprintf('\n  Source session_dur : %.4f s\n', max_dur);
    fprintf('  Output session_dur : %.4f s\n', max_dur_out);
    if abs(max_dur_out - max_dur) > 0.01
        fprintf('  *** DURATION MISMATCH: %.4f s difference\n', max_dur_out - max_dur);
    end
else
    if ~isempty(OUTPUT_FILE)
        fprintf('\n  [OUTPUT_FILE not found: %s]\n', OUTPUT_FILE);
    end
end

%% =========================================================
%  FORMULA CHECK
%% =========================================================
if ~isempty(KNOWN_CHANNEL)
    fprintf('\n============================================================\n');
    fprintf('  FORMULA CHECK — "%s"\n', KNOWN_CHANNEL);
    fprintf('============================================================\n');
    match = [];
    for i = 1:src_count
        if strcmpi(src(i).name, KNOWN_CHANNEL), match = src(i); break; end
    end
    if isempty(match)
        fprintf('  [NOT FOUND] Available: %s\n', strjoin({src(1:src_count).name}, ', '));
    else
        fid3 = fopen(SOURCE_FILE, 'rb');
        c3 = onCleanup(@() fclose(fid3));
        fseek(fid3, match.data_ptr, 'bof');
        n_dump = min(10, match.n);
        fprintf('  datatype=%d  Hz=%d  n=%d  mul=%d  scale=%d  dec=%d  offset=%d\n', ...
            match.datatype, match.sr, match.n, match.mul, match.scale, match.dec, match.offset);
        if match.datatype == 2
            raw = fread(fid3, n_dump, 'int16=>double', 0, 'l');
            fprintf('  First %d raw int16 : %s\n', n_dump, num2str(raw(:)','%d '));
            if match.scale~=0 && match.mul~=0
                pA = raw .* (match.mul/match.scale) ./ (10^match.dec) + match.offset;
                pB = (raw + match.offset) .* (match.mul/match.scale) ./ (10^match.dec);
            else
                pA = raw ./ (10^match.dec) + match.offset;
                pB = (raw + match.offset) ./ (10^match.dec);
            end
            fprintf('  Formula A (current): %s\n', num2str(pA(:)','%.4f '));
            fprintf('  Formula B (alt)    : %s\n', num2str(pB(:)','%.4f '));
            if KNOWN_EXPECTED ~= 0
                eA = abs(pA(1)-KNOWN_EXPECTED); eB = abs(pB(1)-KNOWN_EXPECTED);
                fprintf('  Expected: %.4f\n', KNOWN_EXPECTED);
                fprintf('  Formula A err=%.6f %s\n', eA, iif(eA<eB,'<-- BETTER',''));
                fprintf('  Formula B err=%.6f %s\n', eB, iif(eB<eA,'<-- BETTER',''));
            end
        elseif match.datatype == 1
            raw = fread(fid3, n_dump, 'uint16=>double', 0, 'l');
            fprintf('  First %d raw uint16 (float16): %s\n', n_dump, num2str(raw(:)','%d '));
        else
            fprintf('  datatype %d — inspect manually\n', match.datatype);
        end
    end
end

fprintf('\n============================================================\n');
fprintf('  DONE — paste this output back for analysis\n');
fprintf('============================================================\n');
function [ch_data, n_walked, file_sz] = walk_file(filepath)
    fid2 = fopen(filepath, 'rb');
    if fid2 < 0, error('Cannot open: %s', filepath); end
    fseek(fid2, 0, 'eof'); file_sz = ftell(fid2);
    fseek(fid2, 0x0008, 'bof');
    ptr = fread(fid2, 1, 'uint32=>double', 0, 'l');
    fclose(fid2);

    fid2 = fopen(filepath, 'rb');
    c2 = onCleanup(@() fclose(fid2));
    ch_data = struct(); n_walked = 0;
    while ptr ~= 0 && ptr < file_sz
        fseek(fid2, ptr, 'bof');
        rec = fread(fid2, 84, 'uint8=>uint8')';
        next_ptr  = double(typecast(uint8(rec(5:8)),   'uint32'));
        data_ptr  = double(typecast(uint8(rec(9:12)),  'uint32'));
        ch_n      = double(typecast(uint8(rec(13:16)), 'uint32'));
        sr_raw    = double(typecast(uint8(rec(17:18)), 'uint16'));
        unk1      = double(typecast(uint8(rec(19:20)), 'uint16'));
        datatype  = double(typecast(uint8(rec(21:22)), 'uint16'));
        sr        = double(typecast(uint8(rec(23:24)), 'uint16'));
        ch_offset = double(typecast(uint8(rec(25:26)), 'int16'));
        ch_mul    = double(typecast(uint8(rec(27:28)), 'int16'));
        ch_scale  = double(typecast(uint8(rec(29:30)), 'int16'));
        ch_dec    = double(typecast(uint8(rec(31:32)), 'int16'));
        nb = rec(33:64); nul = find(nb==0,1);
        if ~isempty(nul), nb = nb(1:nul-1); end
        name_str = strtrim(char(nb));
        n_walked = n_walked + 1;
        ch_data(n_walked).name     = name_str;
        ch_data(n_walked).sr       = sr;
        ch_data(n_walked).n        = ch_n;
        ch_data(n_walked).dur      = iif(sr>0 && ch_n>0, ch_n/sr, 0);
        ch_data(n_walked).datatype = datatype;
        ch_data(n_walked).mul      = ch_mul;
        ch_data(n_walked).scale    = ch_scale;
        ch_data(n_walked).dec      = ch_dec;
        ch_data(n_walked).offset   = ch_offset;
        ch_data(n_walked).data_ptr = data_ptr;
        ch_data(n_walked).sr_raw   = sr_raw;
        ch_data(n_walked).unk1     = unk1;
        ch_data(n_walked).meta_ptr = ptr;
        ch_data(n_walked).rec      = rec;
        ptr = next_ptr;
        if n_walked > 5000, warning('5000 limit'); break; end
    end
end
% =========================================================
function s = iif(cond, a, b)
    if cond, s = a; else, s = b; end
end
