%% DEBUG_CHANNEL_HEADER
% Tries multiple starting pointer offsets to find which one gives valid channels.
%
% Usage:
%   fpath = SMP.XMP.meta.Path{1};
%   debug_channel_header

fpath   = SMP.XMP.meta.Path{1};
N_CHANS = 5;

fid = fopen(fpath, 'rb');
if fid == -1, error('Cannot open: %s', fpath); end
c = onCleanup(@() fclose(fid));

fseek(fid, 0, 'eof');
file_sz = ftell(fid);
fprintf('File size: 0x%X\n\n', file_sz);

% Candidate pointer locations in the file header
candidate_offsets = [0x0004, 0x0008, 0x000C, 0x0010, 0x0014, ...
                     0x0018, 0x001C, 0x0020, 0x0024, 0x0028, ...
                     0x002C, 0x0030, 0x0034, 0x0038, 0x003C];

for ci = 1:numel(candidate_offsets)
    hdr_off = candidate_offsets(ci);

    fseek(fid, hdr_off, 'bof');
    start_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

    if start_ptr == 0 || start_ptr >= file_sz
        fprintf('Hdr 0x%04X -> 0x%08X  [out of range]\n\n', hdr_off, start_ptr);
        continue;
    end

    fprintf('=== Hdr 0x%04X -> ptr 0x%08X ===\n', hdr_off, start_ptr);
    fprintf('  %-35s  %8s  %8s  %8s  %8s\n', 'Channel', 'sr_raw', 'unk1', 'unk2', 'data_len');
    fprintf('  %s\n', repmat('-', 1, 71));

    current_ptr = start_ptr;
    valid_names = 0;

    for ch = 1:N_CHANS
        if current_ptr == 0 || current_ptr >= file_sz, break; end

        fseek(fid, current_ptr, 'bof');
        fread(fid, 1, 'uint32=>double', 0, 'l');        % prev_ptr
        next_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
        fread(fid, 1, 'uint32=>double', 0, 'l');         % data_ptr
        data_len = fread(fid, 1, 'uint32=>double', 0, 'l');
        sr_raw   = fread(fid, 1, 'uint16=>double', 0, 'l');
        unk1     = fread(fid, 1, 'uint16=>double', 0, 'l');
        fread(fid, 1, 'uint16=>double', 0, 'l');         % datatype
        unk2     = fread(fid, 1, 'uint16=>double', 0, 'l');
        fread(fid, 1, 'int16=>double',  0, 'l');         % offset
        fread(fid, 1, 'int16=>double',  0, 'l');         % mul
        fread(fid, 1, 'int16=>double',  0, 'l');         % scale
        fread(fid, 1, 'int16=>double',  0, 'l');         % dec
        name_raw = fread(fid, 32, 'uint8=>double')';

        nul = find(name_raw == 0, 1);
        if ~isempty(nul) && nul > 1
            name_str = strtrim(char(name_raw(1:nul-1)));
        else
            name_str = '';
        end

        % Check if name looks like real ASCII text
        printable = all(name_raw(1:max(1,numel(name_str))) >= 32 & ...
                        name_raw(1:max(1,numel(name_str))) <= 126);
        if ~isempty(name_str) && printable
            valid_names = valid_names + 1;
        end

        display_name = name_str;
        if isempty(display_name), display_name = '(empty)'; end

        fprintf('  %-35s  %8d  %8d  %8d  %8d\n', ...
            display_name, sr_raw, unk1, unk2, data_len);

        current_ptr = next_ptr;
    end

    if valid_names >= 3
        fprintf('  *** LOOKS PROMISING (%d/%d valid names) ***\n', valid_names, N_CHANS);
    end
    fprintf('\n');
end