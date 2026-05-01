function investigate_ld_header(filepath)
% INVESTIGATE_LD_HEADER  Verify binary header offsets in a MoTeC .ld file.
%
% Checks whether CarNumber, Venue, Run, Date, and Time are actually present
% at the expected byte offsets BEFORE modifying any reader code.
%
% Usage:
%   investigate_ld_header('E:\TeamData\02_WAU\20260301-1234.ld')
%
% Output:
%   - Field verdict table: PRESENT / EMPTY / REJECTED (non-printable bytes)
%   - Raw byte value at each offset (hex + ASCII)
%   - Hex dump of each critical header region
%   - Comparison: what motec_ld_info currently returns vs what the binary holds
%
% Offsets under investigation (from motec_ld_info.m):
%   0x004A  device_code   char[8]   — car number raw (e.g. "C185")
%   0x005E  date          char[16]  — "DD/MM/YYYY"
%   0x007E  time          char[16]  — "HH:MM:SS"
%   0x009E  driver        char[64]
%   0x00DE  vehicle       char[64]
%   0x011E  engine_id     char[64]
%   0x015E  venue         char[64]  — CRITICAL: often blank in cache
%   0x05E4  session       char[32]
%   0x0624  run           char[32]  — CRITICAL: often blank in cache
%   0x0694  team_name     char[64]

    if nargin < 1
        error('Usage: investigate_ld_header(''path/to/file.ld'')');
    end

    if ~exist(filepath, 'file')
        error('File not found: %s', filepath);
    end

    [~, fname, ext] = fileparts(filepath);
    fprintf('\n');
    fprintf('================================================================\n');
    fprintf('  BINARY HEADER INVESTIGATION\n');
    fprintf('  File: %s%s\n', fname, ext);
    fprintf('================================================================\n\n');

    % ------------------------------------------------------------------
    %  Read entire header region (covers all known offsets)
    % ------------------------------------------------------------------
    fid = fopen(filepath, 'rb');
    if fid == -1, error('Cannot open: %s', filepath); end
    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);
    fseek(fid, 0, 'bof');
    hdr = fread(fid, min(0x06D4 + 64, file_sz), 'uint8=>double')';
    fclose(fid);

    fprintf('File size: %d bytes (0x%X)\n', file_sz, file_sz);
    fprintf('Header bytes read: %d\n\n', numel(hdr));

    % ------------------------------------------------------------------
    %  Fields to investigate
    %  { label, offset, length, note }
    % ------------------------------------------------------------------
    fields = {
        'device_code (car# raw)',  0x4A,  8,  'ECU serial — e.g. C185';
        'date',                    0x5E,  16, 'DD/MM/YYYY';
        'time',                    0x7E,  16, 'HH:MM:SS';
        'driver',                  0x9E,  64, '';
        'vehicle',                 0xDE,  64, '';
        'engine_id',               0x11E, 64, '';
        'venue',                   0x15E, 64, 'CRITICAL — often blank';
        'session',                 0x5E4, 32, '';
        'run',                     0x624, 32, 'CRITICAL — often blank';
        'team_name',               0x694, 64, '';
    };

    % ------------------------------------------------------------------
    %  Field verdict table
    % ------------------------------------------------------------------
    fprintf('--- FIELD VERDICT TABLE ---\n');
    fprintf('%-28s  %-8s  %-10s  %-12s  %s\n', ...
            'Field', 'Offset', 'Status', 'Raw value', 'Note');
    fprintf('%s\n', repmat('-', 1, 90));

    results = struct();
    for i = 1:size(fields, 1)
        label  = fields{i,1};
        offset = fields{i,2};
        len    = fields{i,3};
        note   = fields{i,4};

        [val, status, raw_hex] = read_field(hdr, offset, len);

        safe_label = matlab.lang.makeValidName(label);
        results.(safe_label).value  = val;
        results.(safe_label).status = status;
        results.(safe_label).offset = offset;
        results.(safe_label).len    = len;

        fprintf('%-28s  0x%04X    %-10s  %-12s  %s\n', ...
                label, offset, status, truncate(val, 12), note);
    end

    % ------------------------------------------------------------------
    %  fstr() replication check — matches exactly what motec_ld_info reads
    % ------------------------------------------------------------------
    fprintf('\n--- FSTR() EXACT READS (matches motec_ld_info logic) ---\n');
    fprintf('%-28s  %-8s  %-8s  Result\n', 'Field', 'Offset', 'Len');
    fprintf('%s\n', repmat('-', 1, 70));

    fstr_fields = {
        'device_code',  0x4A,  8;
        'date',         0x5E,  16;
        'time',         0x7E,  16;
        'driver',       0x9E,  64;
        'vehicle',      0xDE,  64;
        'engine_id',    0x11E, 64;
        'venue',        0x15E, 64;
        'session',      0x5E4, 32;
        'run',          0x624, 32;
        'team_name',    0x694, 64;
    };

    for i = 1:size(fstr_fields, 1)
        lbl = fstr_fields{i,1};
        off = fstr_fields{i,2};
        ln  = fstr_fields{i,3};
        val = fstr_exact(hdr, off, ln);
        if isempty(val)
            disp_val = '<EMPTY>';
        else
            disp_val = ['"' val '"'];
        end
        fprintf('%-28s  0x%04X    %-8d  %s\n', lbl, off, ln, disp_val);
    end

    % ------------------------------------------------------------------
    %  Filename-derived fields
    % ------------------------------------------------------------------
    fprintf('\n--- FILENAME-DERIVED FIELDS ---\n');
    tok = regexp(fname, '^(\d{8})-(\d+)(?:_(\d+))?$', 'tokens');
    if ~isempty(tok)
        t = tok{1};
        ds = t{1};
        log_date   = [ds(1:4) '-' ds(5:6) '-' ds(7:8)];
        serial     = t{2};
        run_number = '';
        if numel(t) >= 3 && ~isempty(t{3}), run_number = t{3}; end
        fprintf('  log_date   (from filename): "%s"\n', log_date);
        fprintf('  serial     (from filename): "%s"\n', serial);
        fprintf('  run_number (from filename): "%s"\n', run_number);
    else
        fprintf('  Filename "%s" does not match YYYYMMDD-NNNN[_R] pattern\n', fname);
        fprintf('  log_date, serial, run_number will be empty\n');
    end

    % ------------------------------------------------------------------
    %  Hex dump: device code + date + time block (0x40 – 0x9D)
    % ------------------------------------------------------------------
    fprintf('\n--- HEX DUMP: device_code / date / time (0x0040 – 0x009D) ---\n');
    hex_dump(hdr, 0x40, 0x5E, 'device_code region (0x4A = +0x0A from dump start)');
    hex_dump(hdr, 0x5E, 0x20, 'date (0x005E, 16 bytes)');
    hex_dump(hdr, 0x7E, 0x20, 'time (0x007E, 16 bytes)');

    % ------------------------------------------------------------------
    %  Hex dump: vehicle + engine_id block (0x00DE – 0x015D)
    %  Looking for vehicle/car number field that may sit near vehicle string
    % ------------------------------------------------------------------
    fprintf('\n--- HEX DUMP: vehicle / engine_id region (0x00DE – 0x015D) ---\n');
    hex_dump(hdr, 0x9E,  0x40, 'driver (0x009E, 64 bytes)');
    hex_dump(hdr, 0xDE,  0x40, 'vehicle (0x00DE, 64 bytes)');
    hex_dump(hdr, 0x11E, 0x40, 'engine_id (0x011E, 64 bytes)');
    hex_dump(hdr, 0x15E, 0x20, 'gap before venue — any car# field here? (0x015E)');

    % ------------------------------------------------------------------
    %  Hex dump: scan for unmapped fields between known blocks
    %  Gap 1: 0x00 – 0x003F  (before device_code)
    %  Gap 2: 0x009E – 0x00DD (driver runs to 0x00DD, check for number before it)
    % ------------------------------------------------------------------
    fprintf('\n--- HEX DUMP: header start & unknown gaps ---\n');
    hex_dump(hdr, 0x00, 0x4A, 'bytes 0x0000–0x0049 (before device_code)');

    % ------------------------------------------------------------------
    %  Hex dump: venue block (0x015E – 0x01BE)
    % ------------------------------------------------------------------
    fprintf('\n--- HEX DUMP: venue (0x015E – 0x01BE) ---\n');
    hex_dump(hdr, 0x15E, 0x60, 'venue (0x015E, 64 bytes)');

    % ------------------------------------------------------------------
    %  Hex dump: session + run + team_name (0x05E4 – 0x06D4)
    % ------------------------------------------------------------------
    fprintf('\n--- HEX DUMP: session / run / team_name (0x05E4 – 0x06D4) ---\n');
    hex_dump(hdr, 0x5E4, 0x20, 'session (0x05E4, 32 bytes)');
    hex_dump(hdr, 0x624, 0x20, 'run (0x0624, 32 bytes) EMPTY');
    hex_dump(hdr, 0x694, 0x40, 'team_name (0x0694, 64 bytes) EMPTY');

    % ------------------------------------------------------------------
    %  ASCII car number scan: isolated digit strings in first 0x700 bytes
    % ------------------------------------------------------------------
    fprintf('\n--- CAR NUMBER SCAN: isolated ASCII digit strings ---\n');
    fprintf('Looking for null-flanked digit strings of length 1-6 bytes...\n');
    scan_end = min(0x700, numel(hdr));
    i = 1;
    found_any = false;
    while i <= scan_end
        if hdr(i) >= 48 && hdr(i) <= 57   % ASCII digit
            j = i;
            while j <= scan_end && hdr(j) >= 48 && hdr(j) <= 57
                j = j + 1;
            end
            run_len = j - i;
            if run_len >= 1 && run_len <= 6
                pre_ok  = (i == 1) || hdr(i-1) == 0 || hdr(i-1) < 32;
                post_ok = (j > scan_end) || hdr(j) == 0 || hdr(j) < 32;
                if pre_ok && post_ok
                    num_str = char(hdr(i:j-1));
                    fprintf('  0x%04X  ASCII "%s"\n', i-1, num_str);
                    found_any = true;
                end
            end
            i = j;
        else
            i = i + 1;
        end
    end
    if ~found_any
        fprintf('  (none found)\n');
    end

    % ------------------------------------------------------------------
    %  Binary integer scan: uint16 LE values 1-999 in first 0x700 bytes
    %  Race numbers are often stored as binary uint16, not ASCII
    % ------------------------------------------------------------------
    fprintf('\n--- CAR NUMBER SCAN: uint16 LE values in range 1-999 ---\n');
    fprintf('Offset    uint16 LE   uint16 BE   uint8 pair\n');
    fprintf('%s\n', repmat('-', 1, 55));
    scan_end16 = min(0x700, numel(hdr) - 1);
    found_any = false;
    for k = 1:2:scan_end16
        b0 = hdr(k);
        b1 = hdr(k+1);
        le = b0 + b1*256;
        be = b0*256 + b1;
        if (le >= 1 && le <= 999) || (be >= 1 && be <= 999)
            fprintf('  0x%04X    %-10d  %-10d  [%02X %02X]\n', k-1, le, be, b0, b1);
            found_any = true;
        end
    end
    if ~found_any
        fprintf('  (no uint16 values in 1-999 range found)\n');
    end

    % ------------------------------------------------------------------
    %  Dump bytes 0x00-0x4F (file start through device_code)
    %  This region has not been inspected — any structured fields here?
    % ------------------------------------------------------------------
    fprintf('\n--- HEX DUMP: file start 0x0000 – 0x004F ---\n');
    hex_dump(hdr, 0x00, 0x50, 'bytes 0x0000–0x004F (header preamble)');

    % ------------------------------------------------------------------
    %  Verdict summary
    % ------------------------------------------------------------------
    fprintf('\n--- VERDICT SUMMARY ---\n');
    field_names   = {'device_code',  'date',   'time',   'venue',   'run'};
    field_labels  = {'CarNumber raw','Date',   'Time',   'Venue',   'Run'};
    field_offsets = {0x4A, 0x5E, 0x7E, 0x15E, 0x624};

    for i = 1:numel(field_names)
        lbl = field_labels{i};
        off = field_offsets{i};
        ln_map = containers.Map({0x4A,0x5E,0x7E,0x15E,0x624}, {8,16,16,64,32});
        val = fstr_exact(hdr, off, ln_map(off));
        if isempty(val)
            verdict = 'EMPTY  -> must use fallback';
        else
            verdict = sprintf('PRESENT: "%s"', val);
        end
        fprintf('  %-14s (0x%04X): %s\n', lbl, off, verdict);
    end

    fprintf('\nFallback hierarchy:\n');
    fprintf('  CarNumber : driver_map.(key).num  ->  binary device_code digits\n');
    fprintf('  Venue     : alias.venue.lookup     ->  binary 0x015E\n');
    fprintf('  Run       : filename _N suffix     ->  binary 0x0624\n');
    fprintf('  Date      : filename YYYYMMDD      ->  binary 0x005E\n');
    fprintf('  Time      : binary 0x007E          ->  dir().datenum\n');
    fprintf('\n');
end


% ======================================================================= %
%  LOCAL HELPERS
% ======================================================================= %

function [val, status, raw_hex] = read_field(hdr, offset, len)
% Read field and classify status: PRESENT, EMPTY, or REJECTED.
    idx  = double(offset) + 1;
    last = min(idx + double(len) - 1, numel(hdr));
    if idx > numel(hdr)
        val     = '';
        status  = 'OUT-OF-RANGE';
        raw_hex = '';
        return;
    end
    seg = hdr(idx:last);
    nul = find(seg == 0, 1);
    raw_seg = seg;
    if ~isempty(nul), seg = seg(1:nul-1); end

    raw_hex = sprintf('%02X', raw_seg(1:min(4,end)));

    if isempty(seg)
        val    = '';
        status = 'EMPTY';
    elseif any(seg < 32 | seg > 126)
        % Has non-printable bytes — show sanitised
        sanitised = seg;
        sanitised(sanitised < 32 | sanitised > 126) = double('?');
        val    = strtrim(char(sanitised));
        status = 'REJECTED';   % fstr() would return ''
    else
        val    = strtrim(char(seg));
        status = 'PRESENT';
    end
end


function str = fstr_exact(raw, offset, len)
% Exact replica of fstr() from motec_ld_info.m.
    idx  = double(offset) + 1;
    last = min(idx + double(len) - 1, numel(raw));
    if idx > numel(raw), str = ''; return; end
    seg = raw(idx:last);
    nul = find(seg == 0, 1);
    if ~isempty(nul), seg = seg(1:nul-1); end
    if isempty(seg) || any(seg < 32 | seg > 126)
        str = '';
    else
        str = strtrim(char(seg));
    end
end


function hex_dump(hdr, offset, len, label)
% Print a hex + ASCII dump of a region of hdr.
    fprintf('  [%s]\n', label);
    idx_start = double(offset) + 1;
    idx_end   = min(idx_start + double(len) - 1, numel(hdr));
    if idx_start > numel(hdr)
        fprintf('  (offset 0x%04X beyond header buffer)\n', offset);
        return;
    end
    seg = hdr(idx_start:idx_end);
    n   = numel(seg);
    fprintf('  Offset     00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  | ASCII\n');
    for row = 0 : 16 : n-1
        i   = row + 1;
        s   = seg(i : min(i+15, n));
        hexs = sprintf('%02X ', s);
        hexs = [hexs, repmat('   ', 1, 16-numel(s))]; %#ok
        asc  = s;
        asc(asc < 32 | asc > 126) = double('.');
        fprintf('  0x%06X   %s | %s\n', offset + row, hexs, char(asc));
    end
    fprintf('\n');
end


function s = truncate(str, maxlen)
    if numel(str) <= maxlen
        s = str;
    else
        s = [str(1:maxlen-1) '…'];
    end
end
