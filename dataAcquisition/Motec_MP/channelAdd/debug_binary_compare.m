%% debug_binary_compare.m
% Binary comparison of native vs cloned channel in the prepend test output.
% Prints every byte of both 84-byte records plus the file header pointers.
% Run this and share the output — it will reveal what bytes are different.

clear; clc;

FILE     = 'E:\2026\T01_QLR\COM\20260505-156890014_rh_prepend_test.ld';
NATIVE   = 'Laser Ride Height Rear';
CLONE    = 'Laser RH Rear Prepend';

%% -----------------------------------------------------------------------
fid = fopen(FILE, 'rb');
if fid < 0, error('Cannot open %s', FILE); end
c = onCleanup(@() fclose(fid));

fseek(fid, 0, 'eof');
file_sz = ftell(fid);
fprintf('File size: %d bytes (0x%X)\n\n', file_sz, file_sz);

%% === FILE HEADER POINTERS (0x0000 - 0x0040) ===========================
fprintf('=== FILE HEADER (0x0000–0x0040) ===\n');
fseek(fid, 0, 'bof');
hdr = fread(fid, 0x40, 'uint8=>uint8')';
for row = 0:16:numel(hdr)-1
    seg = hdr(row+1:min(row+16,end));
    hex_s = sprintf('%02X ', seg);
    asc = seg; asc(asc < 32 | asc > 126) = uint8('.');
    fprintf('  0x%04X  %s | %s\n', row, hex_s, char(asc));
end
fprintf('\n');

% Print named pointers
fseek(fid, 0x0000, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0000] %-20s = 0x%08X (%d)\n', 'signature/unk0', v, v);
fseek(fid, 0x0004, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0004] %-20s = 0x%08X (%d)\n', 'event_ptr', v, v);
fseek(fid, 0x0008, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0008] %-20s = 0x%08X (%d)\n', 'first_chan_ptr', v, v);
fseek(fid, 0x000C, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x000C] %-20s = 0x%08X (%d)\n', 'ptr@0x000C', v, v);
fseek(fid, 0x0010, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0010] %-20s = 0x%08X (%d)\n', 'ptr@0x0010', v, v);
fseek(fid, 0x0014, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0014] %-20s = 0x%08X (%d)\n', 'ptr@0x0014', v, v);
fseek(fid, 0x0018, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0018] %-20s = 0x%08X (%d)\n', 'ptr@0x0018', v, v);
fseek(fid, 0x001C, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x001C] %-20s = 0x%08X (%d)\n', 'ptr@0x001C', v, v);
fseek(fid, 0x0020, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0020] %-20s = 0x%08X (%d)\n', 'ptr@0x0020', v, v);
fseek(fid, 0x0024, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0024] %-20s = 0x%08X (%d)\n', 'ptr@0x0024', v, v);
fseek(fid, 0x0028, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0028] %-20s = 0x%08X (%d)\n', 'ptr@0x0028', v, v);
fseek(fid, 0x002C, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x002C] %-20s = 0x%08X (%d)\n', 'ptr@0x002C', v, v);
fseek(fid, 0x0030, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0030] %-20s = 0x%08X (%d)\n', 'ptr@0x0030', v, v);
fseek(fid, 0x0034, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0034] %-20s = 0x%08X (%d)\n', 'ptr@0x0034', v, v);
fseek(fid, 0x0038, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x0038] %-20s = 0x%08X (%d)\n', 'ptr@0x0038', v, v);
fseek(fid, 0x003C, 'bof'); v = fread(fid, 1, 'uint32=>double', 0, 'l'); fprintf('  [0x003C] %-20s = 0x%08X (%d)\n', 'ptr@0x003C', v, v);

%% === WALK LINKED LIST: find both channels ==============================
fprintf('\n=== WALKING CHANNEL LINKED LIST ===\n');
fseek(fid, 0x0008, 'bof');
ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

recs  = struct();
count = 0;
while ptr ~= 0 && ptr < file_sz
    fseek(fid, ptr, 'bof');
    rec = fread(fid, 84, 'uint8=>uint8')';
    name_raw = strtrim(char(rec(33:64)));
    nul = find(name_raw == char(0), 1);
    if ~isempty(nul), name_raw = name_raw(1:nul-1); end

    if strcmpi(strtrim(name_raw), NATIVE)
        recs.native.rec  = rec;
        recs.native.ptr  = ptr;
        recs.native.name = name_raw;
        fprintf('  Found NATIVE  "%s"  @ meta_ptr=0x%X  (channel #%d)\n', name_raw, ptr, count+1);
    end
    if strcmpi(strtrim(name_raw), CLONE)
        recs.clone.rec  = rec;
        recs.clone.ptr  = ptr;
        recs.clone.name = name_raw;
        fprintf('  Found CLONE   "%s"  @ meta_ptr=0x%X  (channel #%d)\n', name_raw, ptr, count+1);
    end

    ptr   = double(typecast(uint8(rec(5:8)), 'uint32'));
    count = count + 1;
    if count > 5000, break; end
end
fprintf('  Total channels walked: %d\n', count);

if ~isfield(recs, 'native')
    fprintf('\n[ERROR] Native channel "%s" not found.\n', NATIVE);
    return;
end
if ~isfield(recs, 'clone')
    fprintf('\n[ERROR] Clone channel "%s" not found.\n', CLONE);
    return;
end

%% === SIDE-BY-SIDE 84-BYTE RECORD COMPARISON ===========================
fprintf('\n=== SIDE-BY-SIDE RECORD COMPARISON ===\n');
fprintf('  (rows with * have byte differences)\n\n');
field_labels = { ...
    1,  4, 'prev_ptr       '; ...
    5,  8, 'next_ptr       '; ...
    9, 12, 'data_ptr       '; ...
   13, 16, 'data_len       '; ...
   17, 18, 'sr_raw         '; ...
   19, 20, 'unk1           '; ...
   21, 22, 'datatype       '; ...
   23, 24, 'sample_rate_hz '; ...
   25, 26, 'ch_offset      '; ...
   27, 28, 'ch_mul         '; ...
   29, 30, 'ch_scale       '; ...
   31, 32, 'dec_places     '; ...
   33, 64, 'name[32]       '; ...
   65, 72, 'short_name[8]  '; ...
   73, 84, 'units[12]      '; ...
};

nr = recs.native.rec;
cr = recs.clone.rec;

for i = 1:size(field_labels, 1)
    a  = field_labels{i,1};
    b  = field_labels{i,2};
    lbl = field_labels{i,3};
    nb  = nr(a:b);
    cb  = cr(a:b);
    diff_flag = ~isequal(nb, cb);
    hex_n = sprintf('%02X', nb);
    hex_c = sprintf('%02X', cb);
    mark  = '';
    if diff_flag, mark = ' ***'; end
    fprintf('  [+%02d..+%02d] %-16s  N: %-32s  C: %-32s%s\n', ...
        a-1, b-1, lbl, hex_n, hex_c, mark);
end

%% === INTERPRETED FIELDS ===============================================
fprintf('\n=== INTERPRETED FIELDS ===\n');
for tag = {'native','clone'}
    t = tag{1};
    rec = recs.(t).rec;
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
    bps = 2 + 2*(datatype >= 3);
    dur = data_len / max(sample_rate, 1);
    fprintf('  [%s]\n', upper(t));
    fprintf('    meta_ptr    = 0x%X\n',  recs.(t).ptr);
    fprintf('    data_ptr    = 0x%X (%d)\n', data_ptr, data_ptr);
    fprintf('    data_len    = %d samples = %.2f s @ %d Hz\n', data_len, dur, sample_rate);
    fprintf('    sr_raw      = %d (0x%04X)\n', sr_raw, sr_raw);
    fprintf('    unk1        = %d (0x%04X)\n', unk1, unk1);
    fprintf('    datatype    = %d  bps=%d\n', datatype, bps);
    fprintf('    scaling     = mul=%d scale=%d dec=%d offset=%d\n', ch_mul, ch_scale, dec_places, ch_offset);
    fprintf('    data end    = 0x%X (%d)\n', data_ptr + data_len*bps, data_ptr + data_len*bps);
    % Hypothesis: if i2 Pro uses (last_data_ptr - data_ptr) / (bps*Hz) as time offset:
    fseek(fid, 0x0008, 'bof');
    fc = fread(fid, 1, 'uint32=>double', 0, 'l');
    fprintf('    (data_ptr - first_chan_ptr) / (bps*Hz) = %.2f s  [timing hypothesis]\n', ...
        (double(data_ptr) - double(fc)) / (bps * sample_rate));
    fprintf('\n');
end

%% === FIRST 10 DATA VALUES =============================================
fprintf('=== FIRST 10 PHYSICAL VALUES ===\n');
for tag = {'native','clone'}
    t = tag{1};
    rec = recs.(t).rec;
    data_ptr    = double(typecast(uint8(rec(9:12)),  'uint32'));
    data_len    = double(typecast(uint8(rec(13:16)), 'uint32'));
    sr_raw      = double(typecast(uint8(rec(17:18)), 'uint16')); %#ok
    unk1_v      = double(typecast(uint8(rec(19:20)), 'uint16')); %#ok
    datatype    = double(typecast(uint8(rec(21:22)), 'uint16'));
    ch_offset   = double(typecast(uint8(rec(25:26)), 'int16'));
    ch_mul      = double(typecast(uint8(rec(27:28)), 'int16'));
    ch_scale    = double(typecast(uint8(rec(29:30)), 'int16'));
    dec_places  = double(typecast(uint8(rec(31:32)), 'int16'));

    if data_ptr > 0 && data_ptr < file_sz && data_len > 0
        fseek(fid, data_ptr, 'bof');
        n_read = min(data_len, 10);
        switch datatype
            case 2
                raw = fread(fid, n_read, 'int16=>double', 0, 'l');
                if ch_scale ~= 0 && ch_mul ~= 0
                    phys = raw .* (ch_mul/ch_scale) ./ (10^dec_places) + ch_offset;
                else
                    phys = raw ./ (10^dec_places) + ch_offset;
                end
            otherwise
                phys = fread(fid, n_read, 'uint8=>double');
        end
        fprintf('  [%s] first %d values: %s\n', upper(t), n_read, mat2str(phys', 4));
    else
        fprintf('  [%s] data_ptr invalid or out of range\n', upper(t));
    end
end

fprintf('\n=== DONE. Share this output to diagnose the time offset. ===\n');
