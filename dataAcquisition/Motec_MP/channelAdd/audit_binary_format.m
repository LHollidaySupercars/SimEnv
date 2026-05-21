%% audit_binary_format.m
% Focused audit of .ld binary assumptions.
%
% Checks in order:
%   1. File header — all pointer fields at 0x0000-0x001F
%   2. unk1 field — distribution across all channels, flag if non-uniform
%   3. sr_raw map — which channels share values, and what the offset formula predicts
%   4. Short name field — is it actually stored and does it match channel name?
%   5. Scaling round-trip — for every channel, decode raw[0] and compare to reader output
%   6. Known-value cross-check — paste a value from i2 Pro to validate our decode
%
% OUTPUT: paste the console output back for analysis.

clear; clc;

%% =========================================================
%  CONFIG — edit these
%% =========================================================
SOURCE_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890002.ld';

% Pick any channel you can open in i2 Pro and read a value from.
% Set VERIFY_CHANNEL = '' to skip.
VERIFY_CHANNEL  = 'Engine Speed';    % exact name as shown in i2 Pro
VERIFY_VALUE    = 0;                 % physical value you read at any cursor point
VERIFY_SAMPLE   = 1;                 % sample index (1-based) corresponding to that cursor point

%% =========================================================
META_BYTES = 84;

fid = fopen(SOURCE_FILE, 'rb');
if fid < 0, error('Cannot open: %s', SOURCE_FILE); end
c = onCleanup(@() fclose(fid));

fseek(fid, 0, 'eof');
file_sz = ftell(fid);
fprintf('File: %s\n', SOURCE_FILE);
fprintf('Size: %d bytes (0x%X)\n\n', file_sz, file_sz);

%% -----------------------------------------------------------------------
%  1. FILE HEADER — first 32 bytes
%% -----------------------------------------------------------------------
fprintf('============================================================\n');
fprintf('  1. FILE HEADER (0x0000 - 0x001F)\n');
fprintf('============================================================\n');

fseek(fid, 0, 'bof');
hdr_u32 = fread(fid, 8, 'uint32=>double', 0, 'l');   % 8 x uint32 = 32 bytes

labels = {'0x0000', '0x0004 event_ptr?', '0x0008 first_chan_ptr', ...
          '0x000C', '0x0010', '0x0014', '0x0018', '0x001C'};
for i = 1:8
    v = hdr_u32(i);
    in_file = v > 0 && v < file_sz;
    flag = '';
    if in_file, flag = '  <- valid file ptr'; end
    fprintf('  %s  =  0x%08X  (%10d)%s\n', labels{i}, v, v, flag);
end

%% -----------------------------------------------------------------------
%  2. WALK ALL CHANNELS — collect metadata
%% -----------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf('  2. CHANNEL WALK\n');
fprintf('============================================================\n');

fseek(fid, 0x0008, 'bof');
first_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

ch_template = struct('meta_ptr',0,'prev_ptr',0,'next_ptr',0,'data_ptr',0,'n',0, ...
                     'sr_raw',0,'unk1',0,'datatype',0,'sr',0,'offset',0,'mul',0, ...
                     'scale',0,'dec',0,'dur',0,'first_raw',NaN,'first_phys',NaN, ...
                     'name','','short_name','','units','');
channels = ch_template;   % 1x1 with all fields — will be overwritten at idx=1
ptr = first_ptr;
idx = 0;
while ptr ~= 0 && ptr < file_sz
    fseek(fid, ptr, 'bof');
    rec = fread(fid, META_BYTES, 'uint8=>uint8')';
    if numel(rec) < META_BYTES, break; end

    idx = idx + 1;
    ch = ch_template;
    ch.meta_ptr  = ptr;
    ch.prev_ptr  = double(typecast(uint8(rec(1:4)),   'uint32'));
    ch.next_ptr  = double(typecast(uint8(rec(5:8)),   'uint32'));
    ch.data_ptr  = double(typecast(uint8(rec(9:12)),  'uint32'));
    ch.n         = double(typecast(uint8(rec(13:16)), 'uint32'));
    ch.sr_raw    = double(typecast(uint8(rec(17:18)), 'uint16'));
    ch.unk1      = double(typecast(uint8(rec(19:20)), 'uint16'));
    ch.datatype  = double(typecast(uint8(rec(21:22)), 'uint16'));
    ch.sr        = double(typecast(uint8(rec(23:24)), 'uint16'));
    ch.offset    = double(typecast(uint8(rec(25:26)), 'int16'));
    ch.mul       = double(typecast(uint8(rec(27:28)), 'int16'));
    ch.scale     = double(typecast(uint8(rec(29:30)), 'int16'));
    ch.dec       = double(typecast(uint8(rec(31:32)), 'int16'));

    % Name (32 bytes, null-terminated)
    name_raw = strtrim(char(rec(33:64)));
    nul = find(name_raw == char(0), 1);
    if ~isempty(nul), name_raw = name_raw(1:nul-1); end
    ch.name = strtrim(name_raw);

    % Short name (8 bytes at +0x40)
    short_raw = strtrim(char(rec(65:72)));
    nul2 = find(short_raw == char(0), 1);
    if ~isempty(nul2), short_raw = short_raw(1:nul2-1); end
    ch.short_name = strtrim(short_raw);

    % Units (12 bytes at +0x48)
    units_raw = strtrim(char(rec(73:84)));
    nul3 = find(units_raw == char(0), 1);
    if ~isempty(nul3), units_raw = units_raw(1:nul3-1); end
    ch.units = strtrim(units_raw);

    % Duration
    if ch.sr > 0
        ch.dur = ch.n / ch.sr;
    else
        ch.dur = 0;
    end

    % First raw sample (for round-trip check)
    if ch.data_ptr > 0 && ch.data_ptr < file_sz && ch.n > 0
        fseek(fid, ch.data_ptr, 'bof');
        switch ch.datatype
            case 1
                raw = fread(fid, 1, 'uint16=>double', 0, 'l');
                ch.first_raw  = raw;
                ch.first_phys = float16_scalar(raw);
            case 2
                raw = fread(fid, 1, 'int16=>double', 0, 'l');
                ch.first_raw  = raw;
                if ch.scale ~= 0 && ch.mul ~= 0
                    ch.first_phys = raw * (ch.mul/ch.scale) / 10^ch.dec + ch.offset;
                else
                    ch.first_phys = raw / 10^ch.dec + ch.offset;
                end
            case 3
                raw = fread(fid, 1, 'int32=>double', 0, 'l');
                ch.first_raw  = raw;
                if ch.scale ~= 0 && ch.mul ~= 0
                    ch.first_phys = raw * (ch.mul/ch.scale) / 10^ch.dec + ch.offset;
                else
                    ch.first_phys = raw / 10^ch.dec + ch.offset;
                end
            case 4
                raw = fread(fid, 1, 'int16=>double', 0, 'l');
                ch.first_raw  = raw;
                ch.first_phys = raw / 10^ch.dec + ch.offset;
        end
    end

    channels(idx) = ch;
    ptr = ch.next_ptr;
    if idx > 5000, warning('5000 channel limit hit'); break; end
end

n_ch = idx;
channels = channels(1:n_ch);
fprintf('Total channels: %d\n\n', n_ch);

% Print channel table
fprintf('%-4s  %-32s  %-8s  %5s  %8s  %5s  0x%-4s  %-8s  %5s  %5s  %5s  %5s  %5s\n', ...
    '#', 'Name', 'Units', 'Hz', 'dur(s)', 'dtype', 'unk1', 'sr_raw', 'n', 'mul', 'scale', 'dec', 'offset');
fprintf('%s\n', repmat('-', 1, 135));
for i = 1:n_ch
    ch = channels(i);
    fprintf('%-4d  %-32s  %-8s  %5d  %8.2f  %5d  0x%04X  %8d  %5d  %5d  %5d  %5d  %5d\n', ...
        i, ch.name, ch.units, ch.sr, ch.dur, ch.datatype, ch.unk1, ch.sr_raw, ...
        ch.n, ch.mul, ch.scale, ch.dec, ch.offset);
end

%% -----------------------------------------------------------------------
%  3. UNK1 AUDIT
%% -----------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf('  3. UNK1 AUDIT\n');
fprintf('============================================================\n');

unk1_vals = [channels.unk1];
unique_unk1 = unique(unk1_vals);
fprintf('Unique unk1 values found: ');
fprintf('0x%04X  ', unique_unk1);
fprintf('\n');

if numel(unique_unk1) == 1
    fprintf('  All channels share unk1 = 0x%04X — likely a constant format field.\n', unique_unk1);
else
    fprintf('  MULTIPLE unk1 values — may be meaningful. Breakdown:\n');
    for v = unique_unk1
        names_with_v = {channels([channels.unk1] == v).name};
        fprintf('    0x%04X (%d channels): ', v, numel(names_with_v));
        fprintf('%s, ', names_with_v{1:min(5,end)});
        if numel(names_with_v) > 5, fprintf('...'); end
        fprintf('\n');
    end
end

%% -----------------------------------------------------------------------
%  4. SR_RAW AUDIT — groups and predicted offset
%% -----------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf('  4. SR_RAW GROUP AUDIT\n');
fprintf('============================================================\n');

sr_raw_vals = [channels.sr_raw];
unique_sr_raw = unique(sr_raw_vals);
fprintf('Unique sr_raw values: %d\n\n', numel(unique_sr_raw));

fprintf('  %-8s  %5s  %8s  %-32s  %8s  %s\n', 'sr_raw', 'count', 'min_dptr', 'first_chan_name', 'max_dptr', 'predicted_offset_s (appended ~14MB file)');
fprintf('  %s\n', repmat('-', 1, 110));

APPEND_PTR = file_sz + META_BYTES;   % where a new channel's data would land

for v = unique_sr_raw
    mask = sr_raw_vals == v;
    grp  = channels(mask);
    dptrs = [grp.data_ptr];
    dptrs = dptrs(dptrs > 0);
    if isempty(dptrs), continue; end
    min_dptr = min(dptrs);
    max_dptr = max(dptrs);
    first_name = grp(find([grp.data_ptr] == min_dptr, 1)).name;
    % Predicted offset for a channel appended at end-of-file with this sr_raw
    % Assumes datatype=2 (int16, 2 bytes/sample) and median Hz of group
    hz_vals  = [grp.sr];
    hz_vals  = hz_vals(hz_vals > 0);
    med_hz   = median(hz_vals);
    if med_hz > 0
        pred_offset = (APPEND_PTR - min_dptr) / (2 * med_hz);
    else
        pred_offset = NaN;
    end
    fprintf('  %-8d  %5d  %8d  %-32s  %8d  %.1f s\n', ...
        v, sum(mask), min_dptr, first_name, max_dptr, pred_offset);
end

%% -----------------------------------------------------------------------
%  5. SHORT NAME AUDIT
%% -----------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf('  5. SHORT NAME FIELD AUDIT (+0x40)\n');
fprintf('============================================================\n');

empty_short = sum(cellfun(@isempty, {channels.short_name}));
fprintf('  Channels with empty short_name: %d / %d\n', empty_short, n_ch);
fprintf('\n  %-32s  %-12s\n', 'Name', 'Short Name');
fprintf('  %s\n', repmat('-', 1, 50));
for i = 1:min(30, n_ch)
    fprintf('  %-32s  %-12s\n', channels(i).name, channels(i).short_name);
end
if n_ch > 30, fprintf('  ... (%d more)\n', n_ch - 30); end

%% -----------------------------------------------------------------------
%  6. SCALING ROUND-TRIP CHECK (first sample of every channel)
%% -----------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf('  6. FIRST-SAMPLE ROUND-TRIP\n');
fprintf('============================================================\n');

fprintf('  %-32s  %5s  %8s  %10s  %10s\n', 'Name', 'dtype', 'raw[0]', 'phys[0]', 'units');
fprintf('  %s\n', repmat('-', 1, 75));
for i = 1:n_ch
    ch = channels(i);
    if ~isnan(ch.first_phys)
        fprintf('  %-32s  %5d  %8.0f  %10.4f  %s\n', ...
            ch.name, ch.datatype, ch.first_raw, ch.first_phys, ch.units);
    end
end

%% -----------------------------------------------------------------------
%  7. KNOWN-VALUE CROSS-CHECK
%% -----------------------------------------------------------------------
if ~isempty(VERIFY_CHANNEL) && VERIFY_VALUE ~= 0
    fprintf('\n============================================================\n');
    fprintf('  7. KNOWN-VALUE CROSS-CHECK\n');
    fprintf('============================================================\n');

    match = find(strcmpi({channels.name}, VERIFY_CHANNEL), 1);
    if isempty(match)
        fprintf('  Channel "%s" not found.\n', VERIFY_CHANNEL);
    else
        ch = channels(match);
        fprintf('  Channel : %s\n', ch.name);
        fprintf('  dtype=%d  mul=%d  scale=%d  dec=%d  offset=%d\n', ...
            ch.datatype, ch.mul, ch.scale, ch.dec, ch.offset);

        % Read sample at VERIFY_SAMPLE
        bps = bytes_per_sample(ch.datatype);
        seek_pos = ch.data_ptr + (VERIFY_SAMPLE - 1) * bps;
        fseek(fid, seek_pos, 'bof');
        switch ch.datatype
            case 1
                raw = fread(fid, 1, 'uint16=>double', 0, 'l');
                decoded = float16_scalar(raw);
            case 2
                raw = fread(fid, 1, 'int16=>double', 0, 'l');
                if ch.scale ~= 0 && ch.mul ~= 0
                    decoded = raw * (ch.mul/ch.scale) / 10^ch.dec + ch.offset;
                else
                    decoded = raw / 10^ch.dec + ch.offset;
                end
            case 3
                raw = fread(fid, 1, 'int32=>double', 0, 'l');
                if ch.scale ~= 0 && ch.mul ~= 0
                    decoded = raw * (ch.mul/ch.scale) / 10^ch.dec + ch.offset;
                else
                    decoded = raw / 10^ch.dec + ch.offset;
                end
            case 4
                raw = fread(fid, 1, 'int16=>double', 0, 'l');
                decoded = raw / 10^ch.dec + ch.offset;
        end

        fprintf('  Sample index : %d\n', VERIFY_SAMPLE);
        fprintf('  Raw value    : %g\n', raw);
        fprintf('  Our decode   : %.4f %s\n', decoded, ch.units);
        fprintf('  i2 Pro shows : %.4f %s\n', VERIFY_VALUE, ch.units);
        err = abs(decoded - VERIFY_VALUE);
        if err < 0.01
            fprintf('  MATCH  (error = %.6f)\n', err);
        else
            fprintf('  *** MISMATCH (error = %.4f) — scaling assumption wrong?\n', err);
        end
    end
end

fprintf('\n============================================================\n');
fprintf('  AUDIT COMPLETE\n');
fprintf('============================================================\n');

%% -----------------------------------------------------------------------
%  LOCAL FUNCTIONS
%% -----------------------------------------------------------------------
function phys = float16_scalar(u16)
    sgn  = bitshift(bitand(u16, 32768), -15);
    ex   = bitshift(bitand(u16, 31744), -10);
    frac = bitand(u16, 1023);
    if ex > 0 && ex < 31
        phys = (-1)^sgn * 2^(ex-15) * (1 + frac/1024);
    elseif ex == 0 && frac ~= 0
        phys = (-1)^sgn * 2^-14 * (frac/1024);
    elseif ex == 31
        phys = Inf * (-1)^sgn;
    else
        phys = 0;
    end
end

function n = bytes_per_sample(datatype)
    switch datatype
        case {1, 2}, n = 2;
        case {3, 4}, n = 4;
        otherwise,   n = 2;
    end
end
