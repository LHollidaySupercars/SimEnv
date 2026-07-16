function ld_prepend_channel(source_ld_file, output_ld_file, new_channels)
% LD_PREPEND_CHANNEL  Insert new channels into the pre-channel zero space.
%
% Unlike ld_add_channel (which appends at EOF), this function writes channel
% metadata + data starting at INSERT_BASE (0x10000) — well within the native
% file body and before first_chan_ptr.  The file header's first_chan_ptr
% (0x0008) is patched so the new records become the HEAD of the linked list.
%
% Hypothesis being tested
% -----------------------
%   i2 Pro uses meta_ptr position (proximity to file start) to anchor channel
%   timing.  Native channels have meta_ptr near 0x1BF73D; appended channels
%   have meta_ptr at EOF (~0x3700000), producing a ~1450 s offset.  Inserting
%   at 0x10000 should eliminate the offset if the hypothesis holds.
%
% Differences from ld_add_channel
% --------------------------------
%   - Writes into pre-channel zero space, NOT at EOF
%   - Updates file[0x0008] (first_chan_ptr) to point to new head
%   - Uses donor's ORIGINAL sr_raw (no unique substitution) — isolates meta_ptr
%   - Raw byte copy only (no ch.value encoding path) — simplest test
%   - Self-contained: no shared helper files
%
% Usage
% -----
%   ch.name        = 'Laser Ride Height Rear Clone';
%   ch.donor_name  = 'Laser Ride Height Rear';
%   ch.sample_rate = 100;
%   ld_prepend_channel('source.ld', 'output.ld', ch)

    narginchk(3, 3);

    META_BYTES  = 84;
    INSERT_BASE = uint32(0x10000);   % first new meta record lands here

    if isstruct(new_channels)
        ch_list = num2cell(new_channels);
    else
        ch_list = new_channels;
    end

    % ------------------------------------------------------------------ %
    %  1. Copy source → output
    % ------------------------------------------------------------------ %
    fprintf('\n[LD_PREPEND_CHANNEL] Copying source → output...\n');
    [ok, msg] = copyfile(source_ld_file, output_ld_file, 'f');
    if ~ok, error('copyfile failed: %s', msg); end
    fprintf('  %s\n\n', output_ld_file);

    % ------------------------------------------------------------------ %
    %  2. Read file header
    % ------------------------------------------------------------------ %
    d = dir(output_ld_file);
    file_sz = d.bytes;

    fid_h = fopen(output_ld_file, 'rb');
    if fid_h < 0, error('Cannot open: %s', output_ld_file); end
    fseek(fid_h, 0x0008, 'bof');
    orig_first_chan_ptr = fread(fid_h, 1, 'uint32=>double', 0, 'l');
    fclose(fid_h);

    if orig_first_chan_ptr == 0 || orig_first_chan_ptr >= file_sz
        error('Invalid first_chan_ptr: 0x%X', orig_first_chan_ptr);
    end
    fprintf('  orig first_chan_ptr : 0x%X\n', orig_first_chan_ptr);
    fprintf('  INSERT_BASE         : 0x%X\n', double(INSERT_BASE));
    fprintf('  Pre-channel space   : %d bytes\n\n', orig_first_chan_ptr - double(INSERT_BASE));

    % ------------------------------------------------------------------ %
    %  3. Walk linked list — build donor map
    % ------------------------------------------------------------------ %
    [donor_map, session_dur] = walk_donors(output_ld_file, file_sz, META_BYTES);
    fprintf('  Session duration    : %.1f s\n', session_dur);
    fprintf('  Donor Hz available  : %s\n\n', ...
        strjoin(arrayfun(@num2str, cell2mat(keys(donor_map)), 'UniformOutput', false), ', '));

    % ------------------------------------------------------------------ %
    %  4. Validate space
    % ------------------------------------------------------------------ %
    total_bytes_needed = 0;
    for ci = 1:numel(ch_list)
        ch = ch_list{ci};
        if ~isfield(ch, 'donor_name') || isempty(ch.donor_name)
            error('ch.donor_name is required for ld_prepend_channel');
        end
        donor_rec = find_named_donor(output_ld_file, ch.donor_name, file_sz, META_BYTES);
        if isempty(donor_rec)
            error('donor_name "%s" not found', ch.donor_name);
        end
        ch_n   = double(typecast(uint8(donor_rec(13:16)), 'uint32'));
        dtype  = double(typecast(uint8(donor_rec(21:22)), 'uint16'));
        bps    = bytes_per_sample(dtype);
        total_bytes_needed = total_bytes_needed + META_BYTES + ch_n * bps;
    end

    space_available = orig_first_chan_ptr - double(INSERT_BASE);
    fprintf('  Total bytes needed  : %d\n', total_bytes_needed);
    fprintf('  Space available     : %d\n\n', space_available);
    if total_bytes_needed > space_available
        error('Not enough pre-channel space: need %d, have %d bytes', ...
            total_bytes_needed, space_available);
    end

    % ------------------------------------------------------------------ %
    %  5. Write each channel into pre-channel space
    % ------------------------------------------------------------------ %
    cursor = double(INSERT_BASE);   % byte offset of next record to write
    first_new_meta_ptr = cursor;    % header will point here

    for ci = 1:numel(ch_list)
        ch = ch_list{ci};
        if ~isfield(ch, 'short_name'), ch.short_name = []; end
        if ~isfield(ch, 'units'),      ch.units      = []; end

        fprintf('[%d/%d] "%s"\n', ci, numel(ch_list), ch.name);

        % -- Find donor ------------------------------------------------
        donor_rec = find_named_donor(output_ld_file, ch.donor_name, file_sz, META_BYTES);
        d_name_raw = strtrim(char(donor_rec(33:64)'));
        nul = find(d_name_raw == char(0), 1);
        if ~isempty(nul), d_name_raw = d_name_raw(1:nul-1); end
        fprintf('   Donor         : "%s"\n', d_name_raw);

        donor_data_ptr   = double(typecast(uint8(donor_rec(9:12)),  'uint32'));
        donor_n          = double(typecast(uint8(donor_rec(13:16)), 'uint32'));
        donor_sr_raw     = double(typecast(uint8(donor_rec(17:18)), 'uint16'));
        donor_datatype   = double(typecast(uint8(donor_rec(21:22)), 'uint16'));
        donor_sr         = double(typecast(uint8(donor_rec(23:24)), 'uint16'));
        bps              = bytes_per_sample(donor_datatype);

        fprintf('   sr_raw        : %d (donor original — no substitution)\n', donor_sr_raw);
        fprintf('   samples       : %d  Hz=%d  dtype=%d  bps=%d\n', donor_n, donor_sr, donor_datatype, bps);

        % -- Pointer layout for this record ----------------------------
        new_meta_ptr = cursor;
        new_data_ptr = cursor + META_BYTES;
        data_bytes   = donor_n * bps;

        % prev_ptr: for the first prepended channel, prev=0.
        %           for subsequent ones, prev = previous new_meta_ptr.
        if ci == 1
            prev_ptr = uint32(0);
        else
            prev_ptr = uint32(prev_new_meta_ptr); %#ok<UNRCH>
        end

        % next_ptr: last prepended channel links back to original first_chan_ptr.
        %           intermediate channels link to the next new_meta_ptr.
        if ci == numel(ch_list)
            next_ptr = uint32(orig_first_chan_ptr);
        else
            % Peek: next slot is immediately after this record's data
            next_ptr = uint32(new_data_ptr + data_bytes);
        end

        fprintf('   new_meta_ptr  : 0x%X\n', new_meta_ptr);
        fprintf('   new_data_ptr  : 0x%X\n', new_data_ptr);
        fprintf('   prev_ptr      : 0x%X\n', double(prev_ptr));
        fprintf('   next_ptr      : 0x%X\n', double(next_ptr));

        % -- Read donor data bytes ------------------------------------
        fid_rd = fopen(output_ld_file, 'rb');
        if fid_rd < 0, error('Cannot open for donor read: %s', output_ld_file); end
        fseek(fid_rd, donor_data_ptr, 'bof');
        raw_bytes = fread(fid_rd, data_bytes, 'uint8=>uint8');
        fclose(fid_rd);
        if numel(raw_bytes) ~= data_bytes
            error('Short read from donor: got %d expected %d bytes', numel(raw_bytes), data_bytes);
        end
        fprintf('   Raw data read : %d bytes from 0x%X\n', numel(raw_bytes), donor_data_ptr);

        % -- Build 84-byte metadata record (from donor template) ------
        rec = donor_rec;
        rec(1:4)   = typecast(prev_ptr,           'uint8');   % prev_ptr
        rec(5:8)   = typecast(next_ptr,           'uint8');   % next_ptr
        rec(9:12)  = typecast(uint32(new_data_ptr),'uint8');  % data_ptr
        rec(13:16) = typecast(uint32(donor_n),    'uint8');   % data_len (unchanged)
        rec(17:18) = typecast(uint16(donor_sr_raw),'uint8');  % sr_raw (donor original)
        rec(33:64) = str_to_bytes(ch.name, 32);
        if ~isempty(ch.short_name)
            rec(65:72) = str_to_bytes(ch.short_name, 8);
        end
        if ~isempty(ch.units)
            rec(73:84) = str_to_bytes(ch.units, 12);
        end

        % -- Write metadata + data into pre-channel space (r+b) -------
        fid_w = fopen(output_ld_file, 'r+b');
        if fid_w < 0, error('Cannot open r+b: %s', output_ld_file); end

        fseek(fid_w, new_meta_ptr, 'bof');
        nw_meta = fwrite(fid_w, rec, 'uint8');
        if nw_meta ~= META_BYTES
            fclose(fid_w);
            error('Metadata write: %d / %d bytes at 0x%X', nw_meta, META_BYTES, new_meta_ptr);
        end

        fseek(fid_w, new_data_ptr, 'bof');
        nw_data = fwrite(fid_w, raw_bytes, 'uint8');
        if nw_data ~= data_bytes
            fclose(fid_w);
            error('Data write: %d / %d bytes at 0x%X', nw_data, data_bytes, new_data_ptr);
        end

        fclose(fid_w);
        fprintf('   Written: meta=%d bytes  data=%d bytes\n', nw_meta, nw_data);

        % -- Pass C: verify raw bytes written --------------------------
        fid_v = fopen(output_ld_file, 'rb');
        if fid_v < 0, error('Cannot open for verify: %s', output_ld_file); end
        fseek(fid_v, new_data_ptr, 'bof');
        rb_check = fread(fid_v, data_bytes, 'uint8=>uint8');
        fclose(fid_v);

        if isequal(raw_bytes(:), rb_check(:))
            fprintf('   Pass C: [PASS] raw copy verified (%d bytes)\n\n', data_bytes);
        else
            fprintf('   Pass C: [FAIL] mismatch at 0x%X\n\n', new_data_ptr);
        end

        % -- Advance cursor for next channel --------------------------
        prev_new_meta_ptr = new_meta_ptr; %#ok<NASGU>
        cursor = new_data_ptr + data_bytes;
    end

    % ------------------------------------------------------------------ %
    %  6. Patch original first channel's prev_ptr → last new meta_ptr
    % ------------------------------------------------------------------ %
    last_new_meta_ptr = cursor - data_bytes - META_BYTES; %#ok<NODEF>
    % Point orig first channel's prev_ptr back to our last inserted channel
    fid_pp = fopen(output_ld_file, 'r+b');
    if fid_pp < 0, error('Cannot open for prev_ptr patch: %s', output_ld_file); end
    fseek(fid_pp, orig_first_chan_ptr, 'bof');   % byte 1 of orig first record = prev_ptr
    fwrite(fid_pp, uint32(last_new_meta_ptr), 'uint32', 0, 'l');
    fclose(fid_pp);
    fprintf('  Orig first channel prev_ptr -> 0x%X\n', last_new_meta_ptr);

    % ------------------------------------------------------------------ %
    %  7. Patch file header: first_chan_ptr → first new meta record
    % ------------------------------------------------------------------ %
    fid_hdr = fopen(output_ld_file, 'r+b');
    if fid_hdr < 0, error('Cannot open for header patch: %s', output_ld_file); end
    fseek(fid_hdr, 0x0008, 'bof');
    fwrite(fid_hdr, uint32(first_new_meta_ptr), 'uint32', 0, 'l');
    fclose(fid_hdr);

    % Verify header patch
    fid_hv = fopen(output_ld_file, 'rb');
    fseek(fid_hv, 0x0008, 'bof');
    check = fread(fid_hv, 1, 'uint32=>double', 0, 'l');
    fclose(fid_hv);
    if check ~= first_new_meta_ptr
        error('Header patch FAILED: wrote 0x%X read 0x%X', first_new_meta_ptr, check);
    end
    fprintf('  file[0x0008] -> 0x%X  [verified]\n', first_new_meta_ptr);

    % ------------------------------------------------------------------ %
    %  8. Delete stale .ldx
    % ------------------------------------------------------------------ %
    [ldx_dir, ldx_base] = fileparts(output_ld_file);
    ldx_path = fullfile(ldx_dir, [ldx_base '.ldx']);
    if exist(ldx_path, 'file')
        delete(ldx_path);
        if ~exist(ldx_path, 'file')
            fprintf('  Deleted stale .ldx\n');
        else
            fprintf('  WARNING: could not delete .ldx (close i2 Pro)\n');
        end
    end

    % ------------------------------------------------------------------ %
    %  9. Summary
    % ------------------------------------------------------------------ %
    fprintf('============================================================\n');
    fprintf('  COMPLETE\n');
    fprintf('  Channels prepended : %d\n',       numel(ch_list));
    fprintf('  File size          : %d bytes (unchanged — wrote into zero space)\n', file_sz);
    fprintf('  New first_chan_ptr : 0x%X\n',      first_new_meta_ptr);
    fprintf('  Output             : %s\n',        output_ld_file);
    fprintf('============================================================\n');
end


% ======================================================================= %
%  WALK DONORS
% ======================================================================= %
function [donor_map, session_dur] = walk_donors(filepath, file_sz, META_BYTES)
    fid = fopen(filepath, 'rb');
    if fid < 0, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0x0008, 'bof');
    ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

    donor_map   = containers.Map('KeyType', 'double', 'ValueType', 'any');
    donor_n_map = containers.Map('KeyType', 'double', 'ValueType', 'double');
    session_dur = 0;
    count       = 0;

    while ptr ~= 0 && ptr < file_sz
        fseek(fid, ptr, 'bof');
        rec      = fread(fid, META_BYTES, 'uint8=>uint8')';
        next_ptr = double(typecast(uint8(rec(5:8)),  'uint32'));
        sr       = double(typecast(uint8(rec(23:24)), 'uint16'));
        ch_n     = double(typecast(uint8(rec(13:16)), 'uint32'));

        if sr > 0 && ch_n > 0
            dur_this = ch_n / sr;
            if dur_this > session_dur, session_dur = dur_this; end

            best_n = 0;
            if isKey(donor_n_map, sr), best_n = donor_n_map(sr); end
            if ch_n > best_n
                donor_map(sr)   = rec;
                donor_n_map(sr) = ch_n;
            end
        end

        ptr   = next_ptr;
        count = count + 1;
        if count > 5000, warning('5000 channel limit hit'); break; end
    end
end


% ======================================================================= %
%  FIND NAMED DONOR
% ======================================================================= %
function rec = find_named_donor(filepath, donor_name, file_sz, META_BYTES)
    rec = [];
    fid = fopen(filepath, 'rb');
    if fid < 0, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0x0008, 'bof');
    ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
    target = lower(strtrim(donor_name));
    count  = 0;

    while ptr ~= 0 && ptr < file_sz
        fseek(fid, ptr, 'bof');
        r = fread(fid, META_BYTES, 'uint8=>uint8')';
        name_raw = strtrim(char(r(33:64)));
        nul = find(name_raw == char(0), 1);
        if ~isempty(nul), name_raw = name_raw(1:nul-1); end
        if strcmpi(strtrim(name_raw), target)
            rec = r;
            return;
        end
        ptr   = double(typecast(uint8(r(5:8)), 'uint32'));
        count = count + 1;
        if count > 5000, break; end
    end
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %
function b = str_to_bytes(str, n)
    b = zeros(1, n, 'uint8');
    bytes = uint8(str(1:min(end, n)));
    b(1:numel(bytes)) = bytes;
end

function n = bytes_per_sample(datatype)
    switch datatype
        case {1, 2}, n = 2;
        case {3, 4}, n = 4;
        otherwise,   n = 2;
    end
end
