%% debug_prechannel_section.m
% The .ld file has ~1.75 MB between the event section (0x76A) and the first
% channel metadata record (0x1BF73D). This diagnostic tries to find what's
% in that section and whether it contains per-channel timing data.

clear; clc;

SOURCE_FILE = 'E:\2026\T01_QLR\COM\20260505-156890014_combined.ld';
TARGET_CHAN = 'Laser Ride Height Rear';

fid = fopen(SOURCE_FILE, 'rb');
if fid < 0, error('Cannot open: %s', SOURCE_FILE); end
c = onCleanup(@() fclose(fid));

fseek(fid, 0, 'eof');
file_sz = ftell(fid);

p0008 = read_u32(fid, 0x0008);   % first_chan_ptr
p000C = read_u32(fid, 0x000C);   % unknown ptr
p0024 = read_u32(fid, 0x0024);
p002C = read_u32(fid, 0x002C);
p0030 = read_u32(fid, 0x0030);

fprintf('first_chan_ptr = 0x%X\n', p0008);
fprintf('ptr@0x000C    = 0x%X\n', p000C);
fprintf('ptr@0x0024    = 0x%X\n', p0024);
fprintf('ptr@0x002C    = 0x%X\n', p002C);
fprintf('ptr@0x0030    = 0x%X\n\n', p0030);

%% -----------------------------------------------------------------------
%  1. Find target channel in linked list
fprintf('=== Finding "%s" ===\n', TARGET_CHAN);
fseek(fid, 0x0008, 'bof');
ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
target_meta_ptr = 0; target_rec = [];
count = 0;
while ptr ~= 0 && ptr < file_sz
    fseek(fid, ptr, 'bof');
    rec = fread(fid, 84, 'uint8=>uint8')';
    name_raw = strtrim(char(rec(33:64)));
    nul = find(name_raw==char(0),1);
    if ~isempty(nul), name_raw=name_raw(1:nul-1); end
    if strcmpi(strtrim(name_raw), TARGET_CHAN)
        target_meta_ptr = ptr;
        target_rec = rec;
        target_chan_idx = count + 1;  % 1-based index in linked list
        break;
    end
    ptr = double(typecast(uint8(rec(5:8)),'uint32'));
    count = count+1;
    if count > 5000, break; end
end

if isempty(target_rec)
    fprintf('[NOT FOUND]\n'); return;
end
target_data_ptr = double(typecast(uint8(target_rec(9:12)),  'uint32'));
target_data_len = double(typecast(uint8(target_rec(13:16)), 'uint32'));
target_sr_raw   = double(typecast(uint8(target_rec(17:18)), 'uint16'));
fprintf('  meta_ptr  = 0x%X  (channel #%d in list)\n', target_meta_ptr, target_chan_idx);
fprintf('  data_ptr  = 0x%X\n', target_data_ptr);
fprintf('  data_len  = %d  (0x%X)\n', target_data_len, target_data_len);
fprintf('  sr_raw    = %d  (0x%X)\n\n', target_sr_raw, target_sr_raw);

%% -----------------------------------------------------------------------
%  2. Dump 64 bytes at each unknown header pointer
ptr_vals  = [p000C, p0024, p002C, p0030];
ptr_names = {'000C', '0024', '002C', '0030'};
for pi2 = 1:numel(ptr_vals)
    pv = ptr_vals(pi2);
    if pv > 0 && pv < file_sz
        fprintf('=== 64 bytes at ptr@0x%s = 0x%X ===\n', ptr_names{pi2}, pv);
        fseek(fid, pv, 'bof');
        seg = fread(fid, 64, 'uint8=>uint8')';
        print_hex(seg, pv);
        fseek(fid, pv, 'bof');
        u32s = fread(fid, 8, 'uint32=>double', 0, 'l');
        fprintf('  As uint32: ');
        fprintf('0x%08X ', u32s); fprintf('\n\n');
    end
end

%% -----------------------------------------------------------------------
%  3. Search pre-channel section for known values
%  data_len = 46300 = 0x0000B4DC  (LE bytes: DC B4 00 00)
%  data_ptr = target_data_ptr     (LE bytes)
%  sr_raw   = 9102 = 0x238E       (LE bytes: 8E 23)

pre_start = 0x76A;
pre_end   = p0008;   % first_chan_ptr
pre_len   = pre_end - pre_start;
fprintf('=== Pre-channel section: 0x%X to 0x%X (%d bytes) ===\n', pre_start, pre_end, pre_len);

fseek(fid, pre_start, 'bof');
pre_data = fread(fid, pre_len, 'uint8=>uint8')';

% Search patterns
data_len_b = typecast(uint32(target_data_len), 'uint8');
data_ptr_b = typecast(uint32(target_data_ptr), 'uint8');
sr_raw_b   = typecast(uint16(target_sr_raw),   'uint8');
meta_ptr_b = typecast(uint32(target_meta_ptr), 'uint8');

patterns = {data_len_b, 'data_len'; data_ptr_b, 'data_ptr'; ...
            meta_ptr_b, 'meta_ptr'; sr_raw_b(1:2), 'sr_raw'};

for pi = 1:size(patterns, 1)
    pat   = patterns{pi,1};
    label = patterns{pi,2};
    hits  = [];
    for i = 1 : numel(pre_data) - numel(pat) + 1
        if isequal(pre_data(i:i+numel(pat)-1), pat')
            hits(end+1) = pre_start + i - 1; %#ok
        end
    end
    if isempty(hits)
        fprintf('  %-12s [%s]: NOT FOUND\n', label, sprintf('%02X ',pat));
    else
        fprintf('  %-12s [%s]: found %d time(s) at: ', label, sprintf('%02X ',pat), numel(hits));
        fprintf('0x%X ', hits(1:min(5,end)));
        fprintf('\n');
    end
end

%% -----------------------------------------------------------------------
%  4. If data_ptr is found, show structure around it
fprintf('\n=== If data_len or data_ptr found, dump surrounding bytes ===\n');
for pi = 1:2  % just data_len and data_ptr
    pat   = patterns{pi,1};
    label = patterns{pi,2};
    for i = 1 : numel(pre_data) - numel(pat) + 1
        if isequal(pre_data(i:i+numel(pat)-1), pat')
            abs_off = pre_start + i - 1;
            look_start = max(0, abs_off - 32);
            look_len   = 80;
            fseek(fid, look_start, 'bof');
            seg = fread(fid, look_len, 'uint8=>uint8')';
            fprintf('\n  [%s found at 0x%X] surrounding bytes:\n', label, abs_off);
            print_hex(seg, look_start);
            break  % just show first hit
        end
    end
end

%% -----------------------------------------------------------------------
%  5. Try to detect record size in pre-channel section
%  If there's a per-channel table, adjacent entries should have a fixed stride.
%  Look for repeated occurrence of sr_raw=9102 (0x8E23) at a fixed interval.
fprintf('\n=== Checking for regular stride pattern (sr_raw repeats) ===\n');
hits_sr = [];
for i = 1:numel(pre_data)-1
    if pre_data(i)==sr_raw_b(1) && pre_data(i+1)==sr_raw_b(2)
        hits_sr(end+1) = i; %#ok
    end
end
if numel(hits_sr) >= 2
    strides = diff(hits_sr);
    fprintf('  sr_raw (0x%02X%02X) found at %d locations\n', sr_raw_b(1), sr_raw_b(2), numel(hits_sr));
    fprintf('  Strides: '); fprintf('%d ', strides(1:min(10,end))); fprintf('\n');
    if numel(unique(strides)) == 1
        fprintf('  Constant stride = %d bytes — likely a per-channel record\n', strides(1));
    else
        fprintf('  Non-constant strides — not a simple per-channel table, or sr_raw not in table\n');
    end
else
    fprintf('  sr_raw 0x%02X%02X not found in pre-channel section\n', sr_raw_b(1), sr_raw_b(2));
end

fprintf('\nDone.\n');

%% -----------------------------------------------------------------------
function print_hex(bytes, base_offset)
    for row = 0:16:numel(bytes)-1
        idx = row+1;
        seg = bytes(idx:min(idx+15,end));
        hexs = sprintf('%02X ', seg);
        hexs = [hexs, repmat('   ',1,16-numel(seg))]; %#ok
        asc = seg; asc(asc<32|asc>126) = uint8('.');
        fprintf('  0x%06X  %s | %s\n', base_offset+row, hexs, char(asc));
    end
end

function v = read_u32(fid, offset)
    fseek(fid, offset, 'bof');
    v = fread(fid, 1, 'uint32=>double', 0, 'l');
end
