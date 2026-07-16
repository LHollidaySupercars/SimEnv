function motec_ld_inspect(filepath)
% MOTEC_LD_INSPECT  Dump the first 512 bytes of a MoTeC .ld file as hex
% to help identify the correct header structure and channel pointer offset.
%
% Usage:
%   motec_ld_inspect('C:\path\to\yourfile.ld')

    fid = fopen(filepath, 'rb');
    if fid == -1
        error('Could not open file: %s', filepath);
    end
    c = onCleanup(@() fclose(fid));

    % Read first 512 bytes
    raw = fread(fid, 512, 'uint8')';
    n   = numel(raw);

    fprintf('\n=== HEX DUMP: first %d bytes ===\n', n);
    fprintf('Offset   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  | ASCII\n');
    fprintf('%s\n', repmat('-', 1, 75));

    for row = 0 : 16 : n-1
        idx   = row + 1;
        chunk = raw(idx : min(idx+15, n));
        hex_s = sprintf('%02X ', chunk);
        % Pad to 48 chars if last row is short
        hex_s = [hex_s, repmat('   ', 1, 16 - numel(chunk))]; %#ok
        % ASCII side (printable only)
        asc   = chunk;
        asc(asc < 32 | asc > 126) = uint8('.');
        fprintf('0x%04X   %s | %s\n', row, hex_s, char(asc));
    end

    fprintf('\n=== UINT32 LE values at every 4-byte boundary (first 256 bytes) ===\n');
    fprintf('Offset    Value (decimal)    Value (hex)\n');
    fprintf('%s\n', repmat('-', 1, 45));
    fseek(fid, 0, 'bof');
    u32 = fread(fid, 64, 'uint32', 0, 'l');
    for i = 1:numel(u32)
        offset = (i-1)*4;
        fprintf('0x%04X    %-18d 0x%08X\n', offset, u32(i), u32(i));
    end

    % Also print file size for context
    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);
    fprintf('\nFile size: %d bytes (0x%X)\n', file_sz, file_sz);

    fprintf('\n=== STRINGS found in first 512 bytes ===\n');
    % Find runs of printable ASCII >= 4 chars
    printable = raw >= 32 & raw <= 126;
    in_run    = false;
    run_start = 0;
    for i = 1:n
        if printable(i) && ~in_run
            in_run    = true;
            run_start = i;
        elseif ~printable(i) && in_run
            run_len = i - run_start;
            if run_len >= 4
                fprintf('  0x%04X: "%s"\n', run_start-1, char(raw(run_start:i-1)));
            end
            in_run = false;
        end
    end
end
