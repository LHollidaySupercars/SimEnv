function motec_ld_meta_dump(filepath, num_bytes)
% MOTEC_LD_META_DUMP  Dump the metadata block to find correct field offsets.
% Usage:
%   motec_ld_meta_dump('C:\path\to\yourfile.ld')
%   motec_ld_meta_dump('C:\path\to\yourfile.ld', 2048)  % dump more bytes

    if nargin < 2, num_bytes = 1024; end

    fid = fopen(filepath, 'rb');
    if fid == -1, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0x0004, 'bof');
    event_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    fprintf('Metadata block at: 0x%X\n\n', event_ptr);

    fseek(fid, event_ptr, 'bof');
    raw = fread(fid, num_bytes, 'uint8=>double')';
    n   = numel(raw);

    fprintf('Offset   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  | ASCII\n');
    fprintf('%s\n', repmat('-',1,75));
    for row = 0:16:n-1
        idx  = row+1;
        seg  = raw(idx:min(idx+15,n));
        hexs = sprintf('%02X ', seg);
        hexs = [hexs, repmat('   ',1,16-numel(seg))]; %#ok
        asc  = seg; asc(asc<32|asc>126) = double('.');
        fprintf('+0x%03X  %s | %s\n', row, hexs, char(asc));
    end

    fprintf('\n=== Strings (offset relative to metadata block, min length 3) ===\n');
    in_run = false; run_start = 0;
    for i = 1:n
        p = raw(i) >= 32 && raw(i) <= 126;
        if p && ~in_run
            in_run = true; run_start = i;
        elseif ~p && in_run
            if i - run_start >= 3
                fprintf('  +0x%03X: "%s"\n', run_start-1, char(raw(run_start:i-1)));
            end
            in_run = false;
        end
    end
end
