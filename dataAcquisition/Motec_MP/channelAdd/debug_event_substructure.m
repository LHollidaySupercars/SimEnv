%% debug_event_substructure.m
% Explore the event section sub-pointers and the full pre-channel section.
% Focus: find what gives i2 Pro the per-channel timing information.

clear; clc;

SOURCE_FILE = 'E:\2026\T01_QLR\COM\20260505-156890014_combined.ld';

fid = fopen(SOURCE_FILE, 'rb');
if fid < 0, error('Cannot open: %s', SOURCE_FILE); end
c = onCleanup(@() fclose(fid));

fseek(fid, 0, 'eof');
file_sz = ftell(fid);
first_chan_ptr = ru32(fid, 0x0008);

fprintf('file_sz         = 0x%X (%d)\n', file_sz, file_sz);
fprintf('first_chan_ptr  = 0x%X\n\n', first_chan_ptr);

%% -----------------------------------------------------------------------
%  Known target channel values (Laser Ride Height Rear)
target_data_ptr = uint32(hex2dec('C5A7E1'));
target_data_len = uint32(hex2dec('0000B4DC'));   % 46300
target_sr_raw   = uint16(9102);
target_sr_hz    = uint16(100);

%% -----------------------------------------------------------------------
%  1. Read the full pre-channel section as uint32 array
%     (event_ptr=0x76A, pre-section ends at first_chan_ptr)
pre_start = hex2dec('76A');
pre_end   = first_chan_ptr;
pre_bytes = pre_end - pre_start;
fprintf('Pre-channel section: 0x%X to 0x%X = %d bytes\n\n', pre_start, pre_end, pre_bytes);

fseek(fid, pre_start, 'bof');
pre_data = fread(fid, pre_bytes, 'uint8=>uint8');
fprintf('  Actually read: %d bytes\n\n', numel(pre_data));

%% -----------------------------------------------------------------------
%  2. Search pre-section for known channel values (all 4 patterns)
patterns = { ...
    typecast(target_data_ptr, 'uint8'),  'data_ptr   (0xC5A7E1)'; ...
    typecast(target_data_len, 'uint8'),  'data_len   (46300=0xB4DC)'; ...
    typecast(target_sr_raw,   'uint8'),  'sr_raw     (9102=0x238E)'; ...
    typecast(target_sr_hz,    'uint8'),  'sample_hz  (100=0x0064)' ...
};

fprintf('=== Searching %d bytes for known channel values ===\n', numel(pre_data));
for pi = 1:size(patterns,1)
    pat   = double(patterns{pi,1}(:));
    label = patterns{pi,2};
    hits  = [];
    pd    = double(pre_data);
    for i = 1:numel(pd)-numel(pat)+1
        if isequal(pd(i:i+numel(pat)-1), pat)
            hits(end+1) = pre_start + i - 1; %#ok<AGROW>
        end
    end
    if isempty(hits)
        fprintf('  %-35s  NOT FOUND\n', label);
    else
        fprintf('  %-35s  %d hit(s): ', label, numel(hits));
        fprintf('0x%X ', hits(1:min(5,end)));
        fprintf('\n');
    end
end

%% -----------------------------------------------------------------------
%  3. Explore event section sub-pointers
%     event_ptr = 0x76A, uint32[5] = 0x4A90C
fprintf('\n=== Event section sub-pointers ===\n');
fseek(fid, pre_start, 'bof');
ev_u32 = fread(fid, 8, 'uint32=>double', 0, 'l');
for i = 1:8
    v = ev_u32(i);
    in_pre = v >= pre_start && v < pre_end;
    in_chan = v >= first_chan_ptr && v < file_sz;
    tag = '';
    if in_pre,  tag = '  <- in pre-section'; end
    if in_chan, tag = '  <- in chan region'; end
    fprintf('  ev[%d] = 0x%08X (%d)%s\n', i, v, v, tag);
end

% Dump 128 bytes at each valid sub-pointer in the pre-section
sub_ptrs = ev_u32(ev_u32 >= pre_start & ev_u32 < pre_end);
for i = 1:numel(sub_ptrs)
    sp = sub_ptrs(i);
    fprintf('\n=== 128 bytes at event sub-ptr 0x%X ===\n', sp);
    fseek(fid, sp, 'bof');
    seg = fread(fid, 128, 'uint8=>uint8')';
    print_hex(seg, sp);
    fseek(fid, sp, 'bof');
    u32s = fread(fid, 8, 'uint32=>double', 0, 'l');
    fprintf('  As uint32: '); fprintf('0x%08X ', u32s); fprintf('\n');
end

%% -----------------------------------------------------------------------
%  4. Try to detect record structure in pre-section.
%     Walk from pre_start in strides of 4,8,16,32,64,128,256,512,1024,1280
%     and look for a pattern that looks like it could encode 46300 (data_len).
fprintf('\n=== Checking strides for data_len=46300 in pre-section ===\n');
b4dc_pat = [0xDC, 0xB4];   % LE bytes of 46300 as uint16
hits16 = [];
pd = double(pre_data);
for i = 1:numel(pd)-1
    if pd(i)==0xDC && pd(i+1)==0xB4
        hits16(end+1) = pre_start + i - 1; %#ok<AGROW>
    end
end
fprintf('  0xB4DC as uint16 LE: %d hits\n', numel(hits16));
if ~isempty(hits16)
    fprintf('  First hits: '); fprintf('0x%X ', hits16(1:min(5,end))); fprintf('\n');
    % Dump around first hit
    rel = hits16(1) - pre_start;
    lo  = max(0, rel-32);
    hi  = min(numel(pd), rel+32);
    fprintf('  Context around first hit:\n');
    print_hex(pre_data(lo+1:hi)', pre_start+lo);
    % Check stride between hits
    if numel(hits16) > 1
        strides = diff(hits16);
        u_strides = unique(strides);
        fprintf('  Strides between hits: ');
        fprintf('%d ', u_strides(1:min(10,end)));
        fprintf('\n');
        if numel(u_strides)==1
            fprintf('  Constant stride = %d bytes\n', u_strides);
        end
    end
end

%% -----------------------------------------------------------------------
%  5. Look for sample_rate=100 (0x0064) at regular intervals in pre-section
%     This might reveal a per-channel index record layout.
fprintf('\n=== Looking for Hz=100 (0x0064 LE) in pre-section ===\n');
hits_hz = [];
for i = 1:numel(pd)-1
    if pd(i)==0x64 && pd(i+1)==0x00
        hits_hz(end+1) = pre_start + i - 1; %#ok<AGROW>
    end
end
fprintf('  0x0064 (Hz=100) as uint16 LE: %d hits\n', numel(hits_hz));
if numel(hits_hz) > 5
    strides_hz = diff(hits_hz);
    u_strides_hz = unique(strides_hz);
    fprintf('  Distinct strides: %d\n', numel(u_strides_hz));
    if numel(u_strides_hz) <= 5
        fprintf('  Values: '); fprintf('%d ', u_strides_hz); fprintf('\n');
    end
end

%% -----------------------------------------------------------------------
%  6. Dump first 256 bytes of pre-section to see structure at the start
fprintf('\n=== First 256 bytes of pre-section (0x%X) ===\n', pre_start);
print_hex(pre_data(1:256)', pre_start);

%% -----------------------------------------------------------------------
%  7. Dump 256 bytes just before first_chan_ptr
fprintf('\n=== Last 256 bytes of pre-section (before 0x%X) ===\n', first_chan_ptr);
tail_idx = numel(pre_data)-255;
print_hex(pre_data(tail_idx:end)', pre_start+tail_idx-1);

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

function v = ru32(fid, offset)
    fseek(fid, offset, 'bof');
    v = fread(fid, 1, 'uint32=>double', 0, 'l');
end
