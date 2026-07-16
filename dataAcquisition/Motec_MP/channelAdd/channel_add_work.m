SOURCE_FILE = 'E:\2026\02_DUP\_Team Data\01_T8R\20260307-243060003.ld';
MOTEC_FILE  = 'E:\2026\02_DUP\_Team Data\01_T8R\20260307-243060003_MOTEC_EXPORT.ld';

% ---- 1. Header diff: first 512 bytes --------------------------------
fid = fopen(SOURCE_FILE, 'rb');
src_hdr = fread(fid, 512, 'uint8=>uint8');
fclose(fid);

fid = fopen(MOTEC_FILE, 'rb');
mot_hdr = fread(fid, 512, 'uint8=>uint8');
fclose(fid);

fprintf('=== HEADER DIFF (first 512 bytes) ===\n');
any_diff = false;
for i = 1:32
    row_s = src_hdr((i-1)*16+1 : i*16);
    row_m = mot_hdr((i-1)*16+1 : i*16);
    if any(row_s ~= row_m)
        any_diff = true;
        fprintf('0x%04X  SRC: %s\n        MOT: %s\n', ...
            (i-1)*16, sprintf('%02X ',row_s), sprintf('%02X ',row_m));
    end
end
if ~any_diff
    fprintf('No differences in first 512 bytes.\n');
end

% ---- 2. Channel count comparison ------------------------------------
fprintf('\n=== CHANNEL COUNTS ===\n');
fprintf('Source : %d channels\n', count_channels(SOURCE_FILE));
fprintf('MoTeC  : %d channels\n', count_channels(MOTEC_FILE));

% ---- 3. Channel name comparison -------------------------------------
src_names = get_names(SOURCE_FILE);
mot_names = get_names(MOTEC_FILE);
fprintf('\n=== CHANNELS IN MOTEC EXPORT NOT IN SOURCE ===\n');
new_chs = setdiff(mot_names, src_names);
if isempty(new_chs)
    fprintf('  (none — same channels)\n');
else
    for i = 1:numel(new_chs)
        fprintf('  + %s\n', new_chs{i});
    end
end

fprintf('\n=== CHANNELS IN SOURCE NOT IN MOTEC EXPORT ===\n');
gone_chs = setdiff(src_names, mot_names);
if isempty(gone_chs)
    fprintf('  (none)\n');
else
    for i = 1:numel(gone_chs)
        fprintf('  - %s\n', gone_chs{i});
    end
end

% ---- 4. Find the new channel's metadata record in MoTeC export ------
fprintf('\n=== NEW CHANNEL METADATA RECORDS ===\n');
fid = fopen(MOTEC_FILE, 'rb');
fseek(fid, 0, 'eof'); file_sz = ftell(fid);
fseek(fid, 0x0008, 'bof');
ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
while ptr ~= 0 && ptr < file_sz
    fseek(fid, ptr, 'bof');
    rec      = fread(fid, 84, 'uint8=>uint8');
    next_ptr = double(typecast(uint8(rec(5:8)), 'uint32'));
    name_str = strtrim(char(rec(33:64)'));
    nul      = find(name_str==0,1);
    if ~isempty(nul), name_str = name_str(1:nul-1); end
    if ismember(strtrim(name_str), new_chs)
        fprintf('Channel: %s\n', strtrim(name_str));
        fprintf('Raw record:\n');
        for i = 1:84
            fprintf('  %3d  0x%02X\n', i, rec(i));
        end
    end
    ptr = next_ptr;
end
fclose(fid);

% ---- helpers --------------------------------------------------------
function n = count_channels(filepath)
    fid = fopen(filepath, 'rb');
    fseek(fid, 0, 'eof'); fsz = ftell(fid);
    fseek(fid, 0x0008, 'bof');
    ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    n = 0;
    while ptr ~= 0 && ptr < fsz
        fseek(fid, ptr, 'bof');
        rec      = fread(fid, 84, 'uint8=>uint8');
        next_ptr = double(typecast(uint8(rec(5:8)), 'uint32'));
        ptr = next_ptr; n = n + 1;
        if n > 5000, break; end
    end
    fclose(fid);
end

function names = get_names(filepath)
    fid = fopen(filepath, 'rb');
    fseek(fid, 0, 'eof'); fsz = ftell(fid);
    fseek(fid, 0x0008, 'bof');
    ptr   = fread(fid, 1, 'uint32=>double', 0, 'l');
    names = {};
    while ptr ~= 0 && ptr < fsz
        fseek(fid, ptr, 'bof');
        rec      = fread(fid, 84, 'uint8=>uint8');
        next_ptr = double(typecast(uint8(rec(5:8)), 'uint32'));
        name_str = strtrim(char(rec(33:64)'));
        nul      = find(name_str==0,1);
        if ~isempty(nul), name_str = name_str(1:nul-1); end
        names{end+1} = strtrim(name_str); %#ok
        ptr = next_ptr;
        if numel(names) > 5000, break; end
    end
    fclose(fid);
end