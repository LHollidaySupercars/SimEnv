function old = motec_ld_header_write(filepath, overrides, dry_run)
% MOTEC_LD_HEADER_WRITE  Patch header strings in a MoTeC .ld file in-place.
%
% Usage:
%   old = motec_ld_header_write(filepath, overrides)           % write
%   old = motec_ld_header_write(filepath, overrides, true)     % dry run only
%
% overrides  Struct with any subset of these fields:
%   .vehicle     char[64]   offset 0x00DE  — what i2 Pro shows as "Vehicle"
%   .venue       char[64]   offset 0x015E  — track name
%   .event       char[64]   event_ptr+0x10 — meeting/event name (i2 "Event")
%                           NOTE: offset within event block confirmed from
%                           motec_ld_reader.m. Verify with debug_header_edit.m.
%   .driver      char[64]   offset 0x009E
%   .engine_id   char[64]   offset 0x011E
%   .team_name   char[64]   offset 0x0694
%   .session     char[32]   offset 0x05E4  — e.g. "Qualifying 2"
%   .run         char[32]   offset 0x0624  — e.g. "Run 1"
%
% Returns old  Struct of pre-edit values (same field names as overrides).
%
% WARNING: edits the file in-place. Back up the file before running.

    if nargin < 3, dry_run = false; end

    % ------------------------------------------------------------------
    %  Fixed-offset field table  {fieldname, abs_offset, max_bytes}
    % ------------------------------------------------------------------
    FIXED = {
        'driver',    0x009E, 64;
        'vehicle',   0x00DE, 64;
        'engine_id', 0x011E, 64;
        'venue',     0x015E, 64;
        'team_name', 0x0694, 64;
        'session',   0x05E4, 32;
        'run',       0x0624, 32;
    };

    % ------------------------------------------------------------------
    %  Read current values for return struct + pre-flight reporting
    % ------------------------------------------------------------------
    old = struct();

    fid_r = fopen(filepath, 'rb');
    if fid_r == -1, error('Cannot open for read: %s', filepath); end

    % Read event_ptr first (needed for 'event' field)
    fseek(fid_r, 0x0004, 'bof');
    event_ptr = fread(fid_r, 1, 'uint32=>double', 0, 'l');

    % Read all fixed-offset old values
    for k = 1:size(FIXED, 1)
        fname = FIXED{k,1};
        off   = FIXED{k,2};
        len   = FIXED{k,3};
        fseek(fid_r, off, 'bof');
        raw = fread(fid_r, len, 'uint8=>double')';
        old.(fname) = read_str(raw);
    end

    % Read event block old value
    if event_ptr > 0
        fseek(fid_r, event_ptr + 0x10, 'bof');
        raw = fread(fid_r, 64, 'uint8=>double')';
        old.event = read_str(raw);
    else
        old.event = '';
    end

    fclose(fid_r);

    % ------------------------------------------------------------------
    %  Validate requested overrides
    % ------------------------------------------------------------------
    req_fields = fieldnames(overrides);
    known = [FIXED(:,1); {'event'}];
    for k = 1:numel(req_fields)
        f = req_fields{k};
        if ~any(strcmp(f, known))
            error('Unknown field "%s". Valid fields: %s', f, strjoin(known, ', '));
        end
    end

    % Build write plan: {fieldname, abs_offset, max_bytes, new_string}
    plan = {};
    for k = 1:size(FIXED, 1)
        fname = FIXED{k,1};
        if isfield(overrides, fname)
            plan{end+1,1} = fname;          %#ok
            plan{end,2}   = FIXED{k,2};
            plan{end,3}   = FIXED{k,3};
            plan{end,4}   = overrides.(fname);
        end
    end
    if isfield(overrides, 'event')
        if event_ptr == 0
            error('event_ptr is 0 — cannot write event field.');
        end
        plan{end+1,1} = 'event';
        plan{end,2}   = event_ptr + 0x10;   % offset within event block
        plan{end,3}   = 64;
        plan{end,4}   = overrides.event;
    end

    if isempty(plan)
        fprintf('motec_ld_header_write: overrides struct is empty, nothing to write.\n');
        return;
    end

    % ------------------------------------------------------------------
    %  Report plan
    % ------------------------------------------------------------------
    fprintf('\n=== motec_ld_header_write %s===\n', ternary(dry_run, '[DRY RUN] ', ''));
    fprintf('File: %s\n\n', filepath);
    for k = 1:size(plan, 1)
        fname  = plan{k,1};
        off    = plan{k,2};
        maxlen = plan{k,3};
        newval = plan{k,4};
        oldval = old.(fname);
        nchars = numel(newval);
        if nchars > maxlen - 1
            error('Field "%s": new value (%d chars) exceeds max %d bytes (need null terminator).', ...
                fname, nchars, maxlen);
        end
        fprintf('  %-12s  0x%05X  max=%2dB\n', fname, off, maxlen);
        fprintf('    old: "%s"\n', oldval);
        fprintf('    new: "%s"  (%d chars)\n', newval, nchars);
    end

    if dry_run
        fprintf('\n[Dry run] No changes written.\n');
        return;
    end

    % ------------------------------------------------------------------
    %  Write in-place
    % ------------------------------------------------------------------
    fprintf('\nWriting...\n');
    fid_w = fopen(filepath, 'r+');
    if fid_w == -1, error('Cannot open for write: %s', filepath); end

    ok = true;
    for k = 1:size(plan, 1)
        fname  = plan{k,1};
        off    = plan{k,2};
        maxlen = plan{k,3};
        newval = plan{k,4};

        % Build null-padded byte vector exactly maxlen bytes long
        bytes = zeros(1, maxlen, 'double');
        src   = double(newval(1:min(numel(newval), maxlen-1)));
        bytes(1:numel(src)) = src;

        fseek(fid_w, off, 'bof');
        n = fwrite(fid_w, bytes, 'uint8');
        if n ~= maxlen
            fprintf('  ERROR: %s — wrote %d / %d bytes\n', fname, n, maxlen);
            ok = false;
        else
            fprintf('  OK: %s\n', fname);
        end
    end

    fclose(fid_w);

    % ------------------------------------------------------------------
    %  Verify by re-reading
    % ------------------------------------------------------------------
    fprintf('\nVerifying...\n');
    fid_v = fopen(filepath, 'rb');
    if fid_v == -1
        fprintf('  WARNING: could not re-open for verify.\n');
        return;
    end

    all_ok = true;
    for k = 1:size(plan, 1)
        fname  = plan{k,1};
        off    = plan{k,2};
        maxlen = plan{k,3};
        newval = plan{k,4};

        fseek(fid_v, off, 'bof');
        raw = fread(fid_v, maxlen, 'uint8=>double')';
        got = read_str(raw);

        if strcmp(got, newval)
            fprintf('  OK: %s = "%s"\n', fname, got);
        else
            fprintf('  MISMATCH: %s\n    expected: "%s"\n    got:      "%s"\n', ...
                fname, newval, got);
            all_ok = false;
        end
    end

    fclose(fid_v);

    if ok && all_ok
        fprintf('\nAll fields written and verified.\n');
    else
        fprintf('\nWARNING: one or more fields did not verify correctly.\n');
    end
end

% ======================================================================
function str = read_str(raw)
% Extract null-terminated ASCII string from raw uint8 array.
    nul = find(raw == 0, 1);
    if ~isempty(nul)
        str = char(raw(1:nul-1));
    else
        str = char(raw);
    end
    str = strtrim(str);
end

% ======================================================================
function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
