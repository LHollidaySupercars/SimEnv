function motec_ld_probe(filepath)
% MOTEC_LD_PROBE  Probe candidate header pointer locations to identify
% the correct channel metadata pointer in a MoTeC .ld file.
%
% Usage:
%   motec_ld_probe('C:\path\to\yourfile.ld')

    fid = fopen(filepath, 'rb');
    if fid == -1, error('Could not open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);
    fprintf('File size: %d bytes (0x%X)\n\n', file_sz, file_sz);

    % Candidate pointer offsets from the header (from hex dump analysis)
    candidates = [0x0004, 0x0008, 0x000C, 0x0024, 0x002C, 0x0030];

    fprintf('Probing candidate header offsets...\n');
    fprintf('%-10s  %-12s  %-12s  %s\n', 'Hdr Offset', 'Ptr Value', 'Ptr (hex)', 'First 64 bytes at that location');
    fprintf('%s\n', repmat('-', 1, 110));

    for i = 1:numel(candidates)
        hdr_off = candidates(i);
        fseek(fid, hdr_off, 'bof');
        ptr_val = fread(fid, 1, 'uint32', 0, 'l');

        if ptr_val == 0 || ptr_val >= file_sz
            fprintf('0x%04X      %-12d  0x%08X  [out of range or zero]\n', hdr_off, ptr_val, ptr_val);
            continue;
        end

        % Jump to that pointer and read 64 bytes
        fseek(fid, ptr_val, 'bof');
        chunk = fread(fid, 64, 'uint8')';

        hex_s = sprintf('%02X ', chunk(1:min(32,end)));
        % Try to read what looks like a channel name (bytes 0x20..0x3F of the block)
        if numel(chunk) >= 48
            name_bytes = chunk(33:min(48, end));
            name_bytes(name_bytes < 32 | name_bytes > 126) = uint8('.');
            name_str = char(name_bytes);
        else
            name_str = '???';
        end

        % Also read the first 3 uint32s at this location (prev, next, data ptr)
        fseek(fid, ptr_val, 'bof');
        u32s = fread(fid, 4, 'uint32', 0, 'l');
        fprintf('0x%04X      %-12d  0x%08X  prev=0x%08X next=0x%08X data=0x%08X len=%d  name~="%s"\n', ...
            hdr_off, ptr_val, ptr_val, u32s(1), u32s(2), u32s(3), u32s(4), strtrim(name_str));
    end

    fprintf('\n--- Also dumping 64 bytes at each candidate target ---\n');
    for i = 1:numel(candidates)
        hdr_off = candidates(i);
        fseek(fid, hdr_off, 'bof');
        ptr_val = fread(fid, 1, 'uint32', 0, 'l');
        if ptr_val == 0 || ptr_val >= file_sz, continue; end

        fprintf('\n[Hdr 0x%04X -> 0x%08X]\n', hdr_off, ptr_val);
        fseek(fid, ptr_val, 'bof');
        chunk = fread(fid, 96, 'uint8')';
        for row = 0 : 16 : numel(chunk)-1
            idx   = row+1;
            seg   = chunk(idx:min(idx+15,end));
            hexs  = sprintf('%02X ', seg);
            hexs  = [hexs, repmat('   ', 1, 16-numel(seg))]; %#ok
            asc   = seg; asc(asc<32|asc>126) = uint8('.');
            fprintf('  +0x%02X  %s | %s\n', row, hexs, char(asc));
        end
    end
end
