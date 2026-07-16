% debug_record_tail.m — Investigate bytes 85-124 of MoTeC .ld channel metadata
%
% Proven record size: 124 bytes (not 84).
%   file[0x0008] = first_chan_ptr = 1764407
%   file[0x000C] = 1883447 (Beacon data_ptr)
%   gap = 119040 = 960 * 124
%
% Known 84-byte layout (1-indexed):
%   1-4:   prev_ptr   (uint32 LE)
%   5-8:   next_ptr   (uint32 LE)
%   9-12:  data_ptr   (uint32 LE)
%   13-16: n_samples  (uint32 LE)
%   17-18: sr_raw     (uint16 LE)
%   19-20: unk1       (uint16 LE)
%   21-22: datatype   (uint16 LE)
%   23-24: Hz         (uint16 LE)
%   25-26: offset     (int16 LE)
%   27-28: mul        (int16 LE)
%   29-30: scale      (int16 LE)
%   31-32: dec_places (int16 LE)
%   33-64: name       (32 bytes)
%   65-72: short_name (8 bytes)
%   73-84: units      (12 bytes)
%   85-124: UNKNOWN   (40 bytes) <-- TARGET

TARGET_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890002.ld';
META_BYTES  = 124;

CHANNELS_TO_INSPECT = {'Beacon', 'Ground Speed', 'Laser Ride Height Rear', ...
    'Laser Ride Height Front L', 'Ignition Cut', 'Engine Speed', ...
    'GPS Altitude', 'VFFMSupplyF1', 'MMDRLMeasured', 'Laser Ride Height Rear Raw'};

% =========================================================
%  OPEN FILE AND WALK LINKED LIST
% =========================================================

fid = fopen(TARGET_FILE, 'rb');
if fid < 0
    error('Cannot open: %s', TARGET_FILE);
end

fseek(fid, 0, 'eof');
file_size = ftell(fid);
fprintf('File size: %d bytes (0x%X)\n', file_size, file_size);

fseek(fid, 0x0008, 'bof');
first_chan_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
fprintf('first_chan_ptr: 0x%X (%d)\n\n', first_chan_ptr, first_chan_ptr);

MAX_CH      = 5000;
ch_names    = cell(MAX_CH, 1);
ch_next_ptr = zeros(MAX_CH, 1);
ch_n_samp   = zeros(MAX_CH, 1);
ch_sr_raw   = zeros(MAX_CH, 1);
ch_dtype    = zeros(MAX_CH, 1);
ch_hz       = zeros(MAX_CH, 1);
ch_data_ptr = zeros(MAX_CH, 1);
ch_tails    = zeros(MAX_CH, 40, 'uint8');

ptr = first_chan_ptr;
idx = 0;
while ptr ~= 0 && ptr < file_size && idx < MAX_CH
    fseek(fid, ptr, 'bof');
    rec = fread(fid, META_BYTES, 'uint8=>uint8');
    if numel(rec) < META_BYTES
        break;
    end
    idx = idx + 1;

    ch_next_ptr(idx) = double(typecast(rec(5:8),   'uint32'));
    ch_data_ptr(idx) = double(typecast(rec(9:12),  'uint32'));
    ch_n_samp(idx)   = double(typecast(rec(13:16), 'uint32'));
    ch_sr_raw(idx)   = double(typecast(rec(17:18), 'uint16'));
    ch_dtype(idx)    = double(typecast(rec(21:22), 'uint16'));
    ch_hz(idx)       = double(typecast(rec(23:24), 'uint16'));

    name_bytes = rec(33:64);
    nz = find(name_bytes == 0, 1);
    if isempty(nz)
        ch_names{idx} = deblank(char(name_bytes(:)'));
    elseif nz == 1
        ch_names{idx} = '';
    else
        ch_names{idx} = char(name_bytes(1:nz-1)');
    end

    ch_tails(idx, :) = rec(85:124);

    ptr = ch_next_ptr(idx);
end
fclose(fid);

n_channels = idx;
fprintf('Total channels found: %d\n\n', n_channels);

ch_names    = ch_names(1:n_channels);
ch_n_samp   = ch_n_samp(1:n_channels);
ch_sr_raw   = ch_sr_raw(1:n_channels);
ch_dtype    = ch_dtype(1:n_channels);
ch_hz       = ch_hz(1:n_channels);
ch_data_ptr = ch_data_ptr(1:n_channels);
ch_tails    = ch_tails(1:n_channels, :);

% =========================================================
%  INDIVIDUAL CHANNEL INSPECTION
% =========================================================

for ci = 1:numel(CHANNELS_TO_INSPECT)
    target = CHANNELS_TO_INSPECT{ci};
    match_idx = find(strcmpi(ch_names, target), 1);

    if isempty(match_idx)
        fprintf('=== CHANNEL NOT FOUND: %s ===\n\n', target);
        continue;
    end

    fprintf('=== CHANNEL: %s (list index %d) ===\n', ch_names{match_idx}, match_idx);
    fprintf('  n_samples : %d\n',   ch_n_samp(match_idx));
    fprintf('  sr_raw    : %d\n',   ch_sr_raw(match_idx));
    fprintf('  datatype  : %d\n',   ch_dtype(match_idx));
    fprintf('  Hz        : %d\n',   ch_hz(match_idx));
    fprintf('  data_ptr  : 0x%X\n', ch_data_ptr(match_idx));

    tail = ch_tails(match_idx, :);  % 1x40 uint8

    % Hex dump — 10 groups of 4 bytes
    hex_groups = cell(1, 10);
    for g = 1:10
        b = tail((g-1)*4+1 : g*4);
        hex_groups{g} = sprintf('%02X %02X %02X %02X', b(1), b(2), b(3), b(4));
    end
    fprintf('  Bytes 85-124 (hex): %s\n', strjoin(hex_groups, ' | '));

    u32 = double(typecast(uint8(tail(:)'), 'uint32'));
    fprintf('  As uint32[10]: ');
    fprintf('%u  ', u32);
    fprintf('\n');

    i32 = double(typecast(uint8(tail(:)'), 'int32'));
    fprintf('  As  int32[10]: ');
    fprintf('%d  ', i32);
    fprintf('\n');

    i16 = double(typecast(uint8(tail(:)'), 'int16'));
    fprintf('  As  int16[20]: ');
    fprintf('%d  ', i16);
    fprintf('\n');

    f32 = double(typecast(uint8(tail(:)'), 'single'));
    fprintf('  As float32[10]: ');
    fprintf('%.6g  ', f32);
    fprintf('\n');

    % Timing analysis
    hz = ch_hz(match_idx);
    n  = ch_n_samp(match_idx);
    if hz > 0
        session_dur_s = n / hz;
        fprintf('  uint32[1]/Hz       = %.4f s  (if start_sample: should be ~0)\n',         u32(1)/hz);
        fprintf('  uint32[2]/Hz       = %.4f s  (if end_sample:   should be ~%.1f s)\n',    u32(2)/hz, session_dur_s);
        fprintf('  uint32[3]/1000     = %.4f s  (if ms timestamp)\n',                        u32(3)/1000);
        if ch_dtype(match_idx) == 4
            bps = 4;
        else
            bps = 2;
        end
        fprintf('  uint32[1]/(bps*Hz) = %.4f s  (bps=%d)\n', u32(1)/(bps*hz), bps);
    else
        fprintf('  (Hz=0, skipping timing analysis)\n');
    end

    fprintf('\n');
end

% =========================================================
%  SUMMARY: TAIL BYTES PATTERN ANALYSIS
% =========================================================

fprintf('=== TAIL BYTES PATTERN ANALYSIS ===\n');
fprintf('  (Analysing %d channels)\n\n', n_channels);

tail_u32 = zeros(n_channels, 10);
for k = 1:n_channels
    tail_u32(k, :) = double(typecast(uint8(ch_tails(k,:)), 'uint32'));
end

fprintf('  Position  min           max           mean          Varies?\n');
fprintf('  %s\n', repmat('-', 1, 62));
for p = 1:10
    col_p  = tail_u32(:, p);
    mn     = min(col_p);
    mx     = max(col_p);
    mu     = mean(col_p);
    if mx == mn
        varies = 'CONSTANT';
    else
        varies = 'VARIES  ';
    end
    fprintf('  %8d  %-13.0f %-13.0f %-13.1f %s\n', p, mn, mx, mu, varies);
end

% Spot-check: uint32[1]/Hz for first 10 channels
fprintf('\n  uint32[1]/Hz spot-check (first 10 channels):\n');
for k = 1:min(10, n_channels)
    hz_k = ch_hz(k);
    if hz_k > 0
        fprintf('    [%3d] %-35s  uint32[1]=%10.0f  /Hz=%.4f s\n', ...
            k, ch_names{k}, tail_u32(k,1), tail_u32(k,1)/hz_k);
    else
        fprintf('    [%3d] %-35s  uint32[1]=%10.0f  Hz=0\n', ...
            k, ch_names{k}, tail_u32(k,1));
    end
end

% =========================================================
%  DELTA FROM BEACON CHANNEL
% =========================================================

fprintf('\n=== DELTA FROM FIRST CHANNEL (Beacon) ===\n');
beacon_idx = find(strcmpi(ch_names, 'Beacon'), 1);
if isempty(beacon_idx)
    fprintf('  Beacon not found — using channel index 1 as reference.\n');
    beacon_idx = 1;
end
beacon_u32 = tail_u32(beacon_idx, :);
fprintf('  Reference: %s (index %d)\n\n', ch_names{beacon_idx}, beacon_idx);

for p = 1:10
    if beacon_u32(p) == 0
        fprintf('  Position %2d: Beacon=0, skipping delta\n', p);
    else
        deltas = tail_u32(:, p) - beacon_u32(p);
        fprintf('  Position %2d: Beacon=%-12.0f  mean_delta=%.2f\n', ...
            p, beacon_u32(p), mean(deltas));
    end
end

fprintf('\ndebug_record_tail complete.\n');
