function binary_browser(filepath, start_offset, num_bytes)
% BINARY_BROWSER  Browse a binary file as hex + ASCII dump.
%
% Usage:
%   binary_browser('C:\path\to\file.ldx')              % first 512 bytes
%   binary_browser('C:\path\to\file.ldx', 0x200)       % from offset 0x200
%   binary_browser('C:\path\to\file.ldx', 0x200, 1024) % 1024 bytes from 0x200
%
% Tips:
%   - Look for readable strings in the ASCII column on the right
%   - Note the +0xXXX offset where you find the driver name
%   - Re-run with a new start_offset to navigate around the file

    if nargin < 2, start_offset = 0; end
    if nargin < 3, num_bytes    = 512; end

    fid = fopen(filepath, 'rb');
    if fid == -1, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);
    fprintf('File: %s\n', filepath);
    fprintf('File size: %d bytes (0x%X)\n', file_sz, file_sz);
    fprintf('Showing %d bytes from offset 0x%X\n\n', num_bytes, start_offset);

    fseek(fid, start_offset, 'bof');
    raw = fread(fid, num_bytes, 'uint8=>double')';
    n   = numel(raw);

    fprintf('Offset     00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  | ASCII\n');
    fprintf('%s\n', repmat('-', 1, 77));

    for row = 0 : 16 : n-1
        idx  = row + 1;
        seg  = raw(idx : min(idx+15, n));
        hexs = sprintf('%02X ', seg);
        hexs = [hexs, repmat('   ', 1, 16-numel(seg))]; %#ok
        asc  = seg;
        asc(asc < 32 | asc > 126) = double('.');
        fprintf('0x%06X   %s | %s\n', start_offset + row, hexs, char(asc));
    end

    % Print all readable strings found in this region
    fprintf('\n=== Strings found (>= 4 chars) ===\n');
    in_run = false; run_start = 0;
    for i = 1:n
        p = raw(i) >= 32 && raw(i) <= 126;
        if p && ~in_run
            in_run = true; run_start = i;
        elseif ~p && in_run
            run_len = i - run_start;
            if run_len >= 4
                abs_off = start_offset + run_start - 1;
                fprintf('  0x%06X (+0x%04X from start): "%s"\n', ...
                    abs_off, run_start-1, char(raw(run_start:i-1)));
            end
            in_run = false;
        end
    end
end
