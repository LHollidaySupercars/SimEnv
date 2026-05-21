%% debug_timing_structure.m
% Find what i2 Pro uses for channel timing.
% Examines: file header, event section, native ride height meta_ptr vs clone.
%
% Run on the SOURCE file (not the output) to understand native structure.

clear; clc;

SOURCE_FILE  = 'E:\2026\T01_QLR\COM\20260505-156890014_combined.ld';
TARGET_CHAN  = 'Laser Ride Height Rear';   % native channel we cloned

fid = fopen(SOURCE_FILE, 'rb');
if fid < 0, error('Cannot open: %s', SOURCE_FILE); end
c = onCleanup(@() fclose(fid));

fseek(fid, 0, 'eof');
file_sz = ftell(fid);
fprintf('File size: %d bytes (0x%X)\n\n', file_sz, file_sz);

%% -----------------------------------------------------------------------
%  1. File header — first 256 bytes
fprintf('=== File header (first 256 bytes) ===\n');
fseek(fid, 0, 'bof');
hdr = fread(fid, 256, 'uint8=>uint8')';
print_hex(hdr, 0);

%% -----------------------------------------------------------------------
%  2. Known pointer fields
fprintf('\n=== Known pointers ===\n');
p0004 = read_u32(fid, 0x0004);
p0008 = read_u32(fid, 0x0008);
p000C = read_u32(fid, 0x000C);
p0010 = read_u32(fid, 0x0010);
fprintf('  0x0004 = 0x%08X (%d)\n', p0004, p0004);
fprintf('  0x0008 = 0x%08X (%d)  [first_chan_ptr]\n', p0008, p0008);
fprintf('  0x000C = 0x%08X (%d)\n', p000C, p000C);
fprintf('  0x0010 = 0x%08X (%d)\n', p0010, p0010);

%% -----------------------------------------------------------------------
%  3. Event section (at p0004)
if p0004 > 0 && p0004 < file_sz
    fprintf('\n=== Event section at 0x%X (first 128 bytes) ===\n', p0004);
    fseek(fid, p0004, 'bof');
    ev = fread(fid, 128, 'uint8=>uint8')';
    print_hex(ev, p0004);
    % read some u32s as potential pointers
    fprintf('\n  First 8 uint32s at event_ptr:\n');
    fseek(fid, p0004, 'bof');
    for i = 1:8
        v = fread(fid, 1, 'uint32=>double', 0, 'l');
        in_file = v > 0 && v < file_sz;
        fprintf('    [%d] 0x%08X (%d)%s\n', i, v, v, iif(in_file, '  <- valid ptr', ''));
    end
end

%% -----------------------------------------------------------------------
%  4. Find native channel's meta_ptr
fprintf('\n=== Walking linked list to find "%s" ===\n', TARGET_CHAN);
fseek(fid, 0x0008, 'bof');
ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
target_meta_ptr = 0;
count = 0;
while ptr ~= 0 && ptr < file_sz
    fseek(fid, ptr, 'bof');
    rec = fread(fid, 84, 'uint8=>uint8')';
    name_raw = strtrim(char(rec(33:64)));
    nul = find(name_raw == char(0), 1);
    if ~isempty(nul), name_raw = name_raw(1:nul-1); end
    if strcmpi(strtrim(name_raw), TARGET_CHAN)
        target_meta_ptr = ptr;
        target_rec = rec;
        break;
    end
    ptr = double(typecast(uint8(rec(5:8)), 'uint32'));
    count = count + 1;
    if count > 5000, break; end
end

if target_meta_ptr == 0
    fprintf('  [NOT FOUND]\n');
else
    data_ptr   = double(typecast(uint8(target_rec(9:12)),  'uint32'));
    data_len   = double(typecast(uint8(target_rec(13:16)), 'uint32'));
    sr_raw     = double(typecast(uint8(target_rec(17:18)), 'uint16'));
    sample_hz  = double(typecast(uint8(target_rec(23:24)), 'uint16'));
    fprintf('  Found at meta_ptr  = 0x%08X (%d)  [walked %d channels]\n', target_meta_ptr, target_meta_ptr, count);
    fprintf('  data_ptr           = 0x%08X (%d)\n', data_ptr, data_ptr);
    fprintf('  data_ptr - meta_ptr = %d bytes\n', data_ptr - target_meta_ptr);
    fprintf('  data_len           = %d samples  (%.2f s @ %d Hz)\n', data_len, data_len/sample_hz, sample_hz);
    fprintf('  sr_raw             = %d\n', sr_raw);

    %% -------------------------------------------------------------------
    %  5. Bytes just BEFORE the channel's meta_ptr (is there a per-channel header?)
    LOOK_BACK = 64;
    if target_meta_ptr >= LOOK_BACK
        fprintf('\n=== %d bytes BEFORE meta_ptr (0x%X - %d) ===\n', LOOK_BACK, target_meta_ptr, LOOK_BACK);
        fseek(fid, target_meta_ptr - LOOK_BACK, 'bof');
        pre = fread(fid, LOOK_BACK, 'uint8=>uint8')';
        print_hex(pre, target_meta_ptr - LOOK_BACK);
    end

    %% -------------------------------------------------------------------
    %  6. Bytes just AFTER the channel's data section
    data_bytes = data_len * 2;   % assume int16
    data_end   = data_ptr + data_bytes;
    fprintf('\n=== 64 bytes AFTER channel data (at 0x%X) ===\n', data_end);
    if data_end + 64 <= file_sz
        fseek(fid, data_end, 'bof');
        post = fread(fid, 64, 'uint8=>uint8')';
        print_hex(post, data_end);
    end

    %% -------------------------------------------------------------------
    %  7. Does anything in the header REFERENCE this channel's meta_ptr or data_ptr?
    fprintf('\n=== Searching header for references to meta_ptr=0x%X or data_ptr=0x%X ===\n', ...
        target_meta_ptr, data_ptr);
    search_bytes = min(p0008, file_sz);   % search the pre-channel section
    fseek(fid, 0, 'bof');
    hdr_all = fread(fid, search_bytes, 'uint8=>uint8')';
    meta_b = typecast(uint32(target_meta_ptr), 'uint8');
    data_b = typecast(uint32(data_ptr),        'uint8');
    for i = 1:numel(hdr_all)-3
        chunk = hdr_all(i:i+3);
        if isequal(chunk, meta_b)
            fprintf('  meta_ptr found at header offset 0x%X\n', i-1);
        end
        if isequal(chunk, data_b)
            fprintf('  data_ptr found at header offset 0x%X\n', i-1);
        end
    end
    fprintf('  (search complete over %d bytes)\n', search_bytes);
end

%% -----------------------------------------------------------------------
%  8. Channel count — does the header store this anywhere obvious?
fprintf('\n=== Checking header uint32s for channel count (1393) ===\n');
fseek(fid, 0, 'bof');
for off = 0:4:256
    fseek(fid, off, 'bof');
    v = fread(fid, 1, 'uint32=>double', 0, 'l');
    if v == 1393
        fprintf('  Found 1393 at header offset 0x%X\n', off);
    end
end

fprintf('\nDone.\n');

%% -----------------------------------------------------------------------
function print_hex(bytes, base_offset)
    for row = 0:16:numel(bytes)-1
        idx = row+1;
        seg = bytes(idx:min(idx+15,end));
        hexs = sprintf('%02X ', seg);
        hexs = [hexs, repmat('   ', 1, 16-numel(seg))]; %#ok
        asc = seg; asc(asc<32|asc>126) = uint8('.');
        fprintf('  0x%06X  %s | %s\n', base_offset+row, hexs, char(asc));
    end
end

function v = read_u32(fid, offset)
    fseek(fid, offset, 'bof');
    v = fread(fid, 1, 'uint32=>double', 0, 'l');
end

function s = iif(cond, a, b)
    if cond, s = a; else, s = b; end
end
