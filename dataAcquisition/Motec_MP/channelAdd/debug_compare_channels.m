%% debug_compare_channels.m
% Dump the full 84-byte metadata record of two channels side by side.
% Use this to find exactly what's different between a working native
% channel and a failing appended channel.

clear; clc;

FILE_A     = 'E:\2026\T01_QLR\COM\20260505-156890014_rh_offset_test.ld';
CHAN_NAMES  = {'Laser Ride Height Rear', 'Laser Ride Height Rear Offset'};

%% -----------------------------------------------------------------------
fid = fopen(FILE_A, 'rb');
if fid < 0, error('Cannot open %s', FILE_A); end
c = onCleanup(@() fclose(fid));

fseek(fid, 0, 'eof');
file_sz = ftell(fid);

fseek(fid, 0x0008, 'bof');
ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

records = struct();
count = 0;
while ptr ~= 0 && ptr < file_sz
    fseek(fid, ptr, 'bof');
    rec = fread(fid, 84, 'uint8=>uint8')';
    name_raw = strtrim(char(rec(33:64)));
    nul = find(name_raw == char(0), 1);
    if ~isempty(nul), name_raw = name_raw(1:nul-1); end

    for i = 1:numel(CHAN_NAMES)
        if strcmpi(strtrim(name_raw), CHAN_NAMES{i})
            key = matlab.lang.makeValidName(CHAN_NAMES{i});
            records.(key).rec  = rec;
            records.(key).ptr  = ptr;
            records.(key).name = name_raw;
        end
    end

    ptr = double(typecast(uint8(rec(5:8)), 'uint32'));
    count = count + 1;
    if count > 5000, break; end
end

fprintf('Walked %d channels.\n\n', count);

%% -----------------------------------------------------------------------
%  Print all found records
found_keys = fieldnames(records);
fprintf('Found %d / %d channels.\n\n', numel(found_keys), numel(CHAN_NAMES));

for i = 1:numel(found_keys)
    k   = found_keys{i};
    rec = records.(k).rec;
    fprintf('=== %s  (meta_ptr=0x%X) ===\n', records.(k).name, records.(k).ptr);

    prev_ptr    = double(typecast(uint8(rec(1:4)),   'uint32'));
    next_ptr    = double(typecast(uint8(rec(5:8)),   'uint32'));
    data_ptr    = double(typecast(uint8(rec(9:12)),  'uint32'));
    data_len    = double(typecast(uint8(rec(13:16)), 'uint32'));
    sr_raw      = double(typecast(uint8(rec(17:18)), 'uint16'));
    unk1        = double(typecast(uint8(rec(19:20)), 'uint16'));
    datatype    = double(typecast(uint8(rec(21:22)), 'uint16'));
    sample_rate = double(typecast(uint8(rec(23:24)), 'uint16'));
    ch_offset   = double(typecast(uint8(rec(25:26)), 'int16'));
    ch_mul      = double(typecast(uint8(rec(27:28)), 'int16'));
    ch_scale    = double(typecast(uint8(rec(29:30)), 'int16'));
    dec_places  = double(typecast(uint8(rec(31:32)), 'int16'));
    name_str    = strtrim(char(rec(33:64)'));  nul=find(name_str==char(0),1); if ~isempty(nul), name_str=name_str(1:nul-1); end
    short_str   = strtrim(char(rec(65:72)'));  nul=find(short_str==char(0),1); if ~isempty(nul), short_str=short_str(1:nul-1); end
    units_str   = strtrim(char(rec(73:84)'));  nul=find(units_str==char(0),1); if ~isempty(nul), units_str=units_str(1:nul-1); end

    fprintf('  prev_ptr    = 0x%08X\n', prev_ptr);
    fprintf('  next_ptr    = 0x%08X\n', next_ptr);
    fprintf('  data_ptr    = 0x%08X\n', data_ptr);
    fprintf('  data_len    = %d  (%.2f s @ %d Hz)\n', data_len, data_len/max(sample_rate,1), sample_rate);
    fprintf('  sr_raw      = %d  (0x%04X)\n', sr_raw, sr_raw);
    fprintf('  unk1        = %d  (0x%04X)\n', unk1, unk1);
    fprintf('  datatype    = %d\n', datatype);
    fprintf('  sample_rate = %d Hz\n', sample_rate);
    fprintf('  offset      = %d\n', ch_offset);
    fprintf('  mul         = %d\n', ch_mul);
    fprintf('  scale       = %d\n', ch_scale);
    fprintf('  dec_places  = %d\n', dec_places);
    fprintf('  name        = "%s"\n', name_str);
    fprintf('  short_name  = "%s"\n', short_str);
    fprintf('  units       = "%s"\n', units_str);
    fprintf('\n  Raw bytes (hex):\n  ');
    for b = 1:84
        fprintf('%02X ', rec(b));
        if mod(b, 16) == 0, fprintf('\n  '); end
    end
    fprintf('\n');

    % ---- Decode formula summary ------------------------------------
    fprintf('\n  Decode formula: phys = raw * (mul/scale) / 10^dec + offset\n');
    fprintf('               = raw * (%d/%d) / 10^%d + %d\n', ...
        ch_mul, ch_scale, dec_places, ch_offset);
    if ch_scale ~= 0 && ch_mul ~= 0
        lsb = (ch_mul / ch_scale) / (10^dec_places);
    else
        lsb = NaN;
    end
    fprintf('  LSB (1 raw unit) = %.6g  %s\n', lsb, units_str);

    % ---- Data section dump -----------------------------------------
    fprintf('\n  Data @ 0x%X  (%d samples, datatype=%d, %d bytes/sample)\n', ...
        data_ptr, data_len, datatype, bytes_per_sample(datatype));
    total_bytes = data_len * bytes_per_sample(datatype);
    fprintf('  Data section size: %d bytes\n', total_bytes);

    if data_ptr > 0 && data_ptr < file_sz && data_len > 0
        fseek(fid, data_ptr, 'bof');
        N_SHOW = min(data_len, 10);
        raw_samples = zeros(1, data_len);
        switch datatype
            case 1
                raw_u16 = fread(fid, data_len, 'uint16=>double', 0, 'l');
                raw_samples = raw_u16;
                phys_vals = float16_arr_to_double(raw_u16);
            case 2
                raw_i16 = fread(fid, data_len, 'int16=>double', 0, 'l');
                raw_samples = raw_i16;
                if ch_scale ~= 0 && ch_mul ~= 0
                    phys_vals = raw_i16 .* (ch_mul/ch_scale) ./ (10^dec_places) + ch_offset;
                else
                    phys_vals = raw_i16 ./ (10^dec_places) + ch_offset;
                end
            case 3
                raw_i32 = fread(fid, data_len, 'int32=>double', 0, 'l');
                raw_samples = raw_i32;
                if ch_scale ~= 0 && ch_mul ~= 0
                    phys_vals = raw_i32 .* (ch_mul/ch_scale) ./ (10^dec_places) + ch_offset;
                else
                    phys_vals = raw_i32 ./ (10^dec_places) + ch_offset;
                end
            case 4
                raw_i16 = fread(fid, data_len, 'int16=>double', 2, 'l');
                raw_samples = raw_i16;
                phys_vals = raw_i16 ./ (10^dec_places) + ch_offset;
            otherwise
                phys_vals = NaN(data_len, 1);
                fprintf('  [WARN] Unknown datatype %d — cannot decode\n', datatype);
        end

        % Raw hex of first 32 data bytes
        fseek(fid, data_ptr, 'bof');
        raw_head = fread(fid, min(32, total_bytes), 'uint8=>uint8')';
        fprintf('\n  First %d raw data bytes (hex):\n  ', numel(raw_head));
        for b = 1:numel(raw_head)
            fprintf('%02X ', raw_head(b));
            if mod(b,16)==0, fprintf('\n  '); end
        end
        fprintf('\n');

        fprintf('\n  First %d samples:\n', N_SHOW);
        fprintf('  %-8s  %-12s  %-12s\n', 'idx', 'raw', 'phys');
        for s = 1:N_SHOW
            fprintf('  %-8d  %-12g  %-12.4f %s\n', s, raw_samples(s), phys_vals(s), units_str);
        end
        if data_len > N_SHOW*2
            fprintf('  ...\n');
            fprintf('  Last %d samples:\n', N_SHOW);
            for s = data_len-N_SHOW+1 : data_len
                fprintf('  %-8d  %-12g  %-12.4f %s\n', s, raw_samples(s), phys_vals(s), units_str);
            end
        end

        fprintf('\n  Statistics (physical):\n');
        fprintf('    min    = %.4f %s\n', min(phys_vals),  units_str);
        fprintf('    max    = %.4f %s\n', max(phys_vals),  units_str);
        fprintf('    mean   = %.4f %s\n', mean(phys_vals), units_str);
        fprintf('    median = %.4f %s\n', median(phys_vals), units_str);
        fprintf('    std    = %.4f %s\n', std(phys_vals),  units_str);
        fprintf('    NaN    = %d\n',      sum(isnan(phys_vals)));

        records.(k).phys = phys_vals;
    else
        fprintf('  [SKIP] data_ptr out of range or data_len=0\n');
        records.(k).phys = [];
    end
    fprintf('\n');
end

%% -----------------------------------------------------------------------
%  Side-by-side byte diff (if both found)
if numel(found_keys) == 2
    r1 = records.(found_keys{1}).rec;
    r2 = records.(found_keys{2}).rec;
    diff_idx = find(r1 ~= r2);
    fprintf('=== Byte diff (%d differences) ===\n', numel(diff_idx));
    fprintf('  %-6s  %-26s  %-6s  %-6s  note\n', 'byte', 'field', found_keys{1}(1:min(8,end)), found_keys{2}(1:min(8,end)));
    field_map = { ...
        1,  4,  'prev_ptr'; ...
        5,  8,  'next_ptr'; ...
        9,  12, 'data_ptr'; ...
        13, 16, 'data_len'; ...
        17, 18, 'sr_raw'; ...
        19, 20, 'unk1'; ...
        21, 22, 'datatype'; ...
        23, 24, 'sample_rate_hz'; ...
        25, 26, 'offset'; ...
        27, 28, 'mul'; ...
        29, 30, 'scale'; ...
        31, 32, 'dec_places'; ...
        33, 64, 'name'; ...
        65, 72, 'short_name'; ...
        73, 84, 'units' ...
    };
    for bi = 1:numel(diff_idx)
        b = diff_idx(bi);
        note = '';
        for fi = 1:size(field_map,1)
            if b >= field_map{fi,1} && b <= field_map{fi,2}
                note = field_map{fi,3};
                break;
            end
        end
        fprintf('  %-6d  %-26s  0x%02X    0x%02X\n', b, note, r1(b), r2(b));
    end
    fprintf('\n');

    % Physical value comparison (if both have data)
    if ~isempty(records.(found_keys{1}).phys) && ~isempty(records.(found_keys{2}).phys)
        p1 = records.(found_keys{1}).phys;
        p2 = records.(found_keys{2}).phys;
        n_cmp = min(numel(p1), numel(p2));
        diff_phys = p2(1:n_cmp) - p1(1:n_cmp);
        fprintf('=== Physical value comparison (first %d samples) ===\n', n_cmp);
        fprintf('  Expected offset: constant shift\n');
        fprintf('  Actual diff  min  = %.4f\n', min(diff_phys));
        fprintf('  Actual diff  max  = %.4f\n', max(diff_phys));
        fprintf('  Actual diff  mean = %.4f\n', mean(diff_phys));
        fprintf('  Actual diff  std  = %.6f\n', std(diff_phys));
    end
end

%% -----------------------------------------------------------------------
%  Helpers

function n = bytes_per_sample(datatype)
    switch datatype
        case 1, n = 2;
        case 2, n = 2;
        case 3, n = 4;
        case 4, n = 4;
        otherwise, n = 2;
    end
end

function out = float16_arr_to_double(u16)
    u16  = double(u16(:));
    sgn  = bitshift(bitand(u16, 32768), -15);
    ex   = bitshift(bitand(u16, 31744), -10);
    frac = bitand(u16, 1023);
    out  = zeros(size(u16));
    nm   = (ex > 0) & (ex < 31);
    out(nm) = (-1).^sgn(nm) .* 2.^(ex(nm)-15) .* (1 + frac(nm)/1024);
    sn   = (ex == 0) & (frac ~= 0);
    out(sn) = (-1).^sgn(sn) .* 2^-14 .* (frac(sn)/1024);
    out(ex==31 & frac==0) = Inf .* (-1).^sgn(ex==31 & frac==0);
    out(ex==31 & frac~=0) = NaN;
end
