function motec_ld_writer(source_ld_file, output_ld_file, progress_file, force_restart)
% MOTEC_LD_WRITER  Write a MoTeC .ld binary file from a motec_ld_reader struct.
%
% Strategy
% --------
%   1.  Read the MASTER .ld file using motec_ld_reader (all channels).
%   2.  Copy master file byte-exact to output path as the baseline.
%   3.  Walk every channel in the binary linked list, one at a time.
%       For each channel:
%         a. Reverse-scale phys data back to raw integers (exact inverse
%            of the reader's scaling math).
%         b. Patch the output file: overwrite the data block at data_ptr.
%         c. Patch the metadata record at meta_ptr (preserve all unknown
%            fields verbatim from the source binary).
%         d. Immediately read back that channel from the patched file.
%         e. Compare read-back phys vs original within FLOAT_TOL.
%         f. Log any pointer or data mismatch as an invalid entry.
%   4.  Every 100 channels: save progress + print a full report of all
%       invalid entries found so far, then pause for user inspection.
%   5.  On re-run: resumes from where it left off via progress .mat file.
%       Set FORCE_RESTART = true to wipe state and start over.
%
% Usage
% -----
%   motec_ld_writer('C:\data\master.ld', 'C:\data\output.ld')
%   motec_ld_writer('C:\data\master.ld', 'C:\data\output.ld', 'progress.mat')
%   motec_ld_writer('C:\data\master.ld', 'C:\data\output.ld', 'progress.mat', true)
%
% Binary layout (from motec_ld_reader.m)
% ---------------------------------------
%   File header:
%     0x0008  uint32  first_meta_ptr  <- pointer to first channel metadata record
%
%   Channel metadata record = 84 bytes (0x54), little-endian:
%     +0x00  uint32  prev_ptr
%     +0x04  uint32  next_ptr
%     +0x08  uint32  data_ptr
%     +0x0C  uint32  data_len     (n_samples)
%     +0x10  uint16  sr_raw       (preserved verbatim)
%     +0x12  uint16  unk1         (preserved verbatim)
%     +0x14  uint16  datatype     (1=float16, 2=int16, 3=int32, 4=int16+2pad)
%     +0x16  uint16  sample_rate  (true Hz)
%     +0x18  int16   ch_offset
%     +0x1A  int16   ch_mul
%     +0x1C  int16   ch_scale
%     +0x1E  int16   dec_places
%     +0x20  char[32] name
%     +0x40  char[8]  short_name
%     +0x48  char[12] units
%     = 84 bytes total
%
%   Datatype scaling (reader forward pass):
%     type 1: phys = float16(uint16_raw)          -- already physical
%     type 2: phys = int16_raw*(mul/scale)/10^dec + offset
%     type 3: phys = int32_raw*(mul/scale)/10^dec + offset
%     type 4: phys = int16_raw/10^dec + offset    (+ 2 zero-pad bytes per sample)

    META_BYTES  = 84;    % bytes per channel metadata record
    PAUSE_EVERY = 100;   % pause + report interval
    FLOAT_TOL   = 1e-3;  % read-back match tolerance

    % ------------------------------------------------------------------ %
    %  Arguments
    % ------------------------------------------------------------------ %
    if nargin < 3 || isempty(progress_file)
        [od, ~, ~] = fileparts(output_ld_file);
        progress_file = fullfile(od, 'ld_writer_progress.mat');
    end
    if nargin < 4
        force_restart = false;
    end

    % ------------------------------------------------------------------ %
    %  Load or initialise progress
    % ------------------------------------------------------------------ %
    if ~force_restart && exist(progress_file, 'file')
        fprintf('\n[RESUME] Loading progress: %s\n', progress_file);
        load(progress_file, 'prog');
        fprintf('  Resuming at channel %d / %d\n', prog.ch_idx, prog.n_ch);
    else
        fprintf('\n[INIT] Building channel list from master file...\n');
        prog = build_progress(source_ld_file, output_ld_file, META_BYTES, FLOAT_TOL);
        save(progress_file, 'prog', '-v7');
        fprintf('[Progress saved: %s]\n\n', progress_file);
    end

    % ------------------------------------------------------------------ %
    %  Open output file for patching (r+b = read+write, no truncate)
    % ------------------------------------------------------------------ %
    fid = fopen(output_ld_file, 'r+b');
    if fid < 0
        error('Cannot open output file for writing: %s', output_ld_file);
    end
    oc = onCleanup(@() fclose(fid));

    % ------------------------------------------------------------------ %
    %  Main loop — one channel per iteration
    % ------------------------------------------------------------------ %
    while prog.ch_idx <= prog.n_ch

        ci   = prog.ch_idx;
        meta = prog.channels(ci);

        fprintf('[%d/%d] %-35s  dt=%d  ptr=0x%X  n=%d\n', ...
            ci, prog.n_ch, meta.raw_name, meta.datatype, meta.data_ptr, meta.data_len);

        % -------------------------------------------------------------- %
        %  A. Reverse-scale: phys → raw bytes
        % -------------------------------------------------------------- %
        [raw_bytes, n_samp, ok, err] = encode_channel(meta);

        if ~ok
            prog = log_fail(prog, ci, meta, 'ENCODE', err, meta.data_ptr);
            prog.ch_idx = ci + 1;
            prog = maybe_checkpoint(prog, progress_file, ci, PAUSE_EVERY);
            continue;
        end

        % -------------------------------------------------------------- %
        %  B. Patch data block at data_ptr
        % -------------------------------------------------------------- %
        if meta.data_ptr == 0 || meta.data_ptr >= prog.file_sz
            err = sprintf('data_ptr=0x%X out of range (file_sz=0x%X)', ...
                meta.data_ptr, prog.file_sz);
            prog = log_fail(prog, ci, meta, 'PTR', err, meta.data_ptr);
            prog.ch_idx = ci + 1;
            prog = maybe_checkpoint(prog, progress_file, ci, PAUSE_EVERY);
            continue;
        end

        fseek(fid, meta.data_ptr, 'bof');
        nw = fwrite(fid, raw_bytes, 'uint8');
        if nw ~= numel(raw_bytes)
            err = sprintf('fwrite: wrote %d / %d bytes', nw, numel(raw_bytes));
            prog = log_fail(prog, ci, meta, 'WRITE', err, meta.data_ptr);
            prog.ch_idx = ci + 1;
            prog = maybe_checkpoint(prog, progress_file, ci, PAUSE_EVERY);
            continue;
        end

        % -------------------------------------------------------------- %
        %  C. Patch metadata record (preserve all unknown fields verbatim)
        % -------------------------------------------------------------- %
        fseek(fid, meta.meta_ptr, 'bof');
        fwrite(fid, uint32(meta.prev_ptr),    'uint32', 0, 'l');
        fwrite(fid, uint32(meta.next_ptr),    'uint32', 0, 'l');
        fwrite(fid, uint32(meta.data_ptr),    'uint32', 0, 'l');
        fwrite(fid, uint32(n_samp),           'uint32', 0, 'l');
        fwrite(fid, uint16(meta.sr_raw),      'uint16', 0, 'l');
        fwrite(fid, uint16(meta.unk1),        'uint16', 0, 'l');
        fwrite(fid, uint16(meta.datatype),    'uint16', 0, 'l');
        fwrite(fid, uint16(meta.sample_rate), 'uint16', 0, 'l');
        fwrite(fid, int16(meta.ch_offset),    'int16',  0, 'l');
        fwrite(fid, int16(meta.ch_mul),       'int16',  0, 'l');
        fwrite(fid, int16(meta.ch_scale),     'int16',  0, 'l');
        fwrite(fid, int16(meta.dec_places),   'int16',  0, 'l');
        write_padded(fid, meta.name_raw,  32);
        write_padded(fid, meta.short_raw, 8);
        write_padded(fid, meta.units_raw, 12);
        % Verify position: should be meta_ptr + 84
        actual_pos = ftell(fid);
        expected   = meta.meta_ptr + META_BYTES;
        if actual_pos ~= expected
            err = sprintf('meta record end=0x%X expected=0x%X (off by %d bytes)', ...
                actual_pos, expected, actual_pos - expected);
            prog = log_fail(prog, ci, meta, 'META_LEN', err, meta.meta_ptr);
        end

        % Force write to disk before read-back
        fseek(fid, 0, 'cof');

        % -------------------------------------------------------------- %
        %  D. Read back and verify
        % -------------------------------------------------------------- %
        [rb_phys, rb_ok, rb_err] = readback_channel(output_ld_file, meta);

        if ~rb_ok
            prog = log_fail(prog, ci, meta, 'READBACK', rb_err, meta.data_ptr);
        elseif isempty(meta.phys)
            fprintf('     [SKIP verify] no phys data from reader for this channel\n');
            prog.n_skip = prog.n_skip + 1;
        else
            % Compare — trim to shorter length in case of rounding on n_samp
            n_cmp = min(numel(rb_phys), numel(meta.phys));
            max_err = max(abs(double(rb_phys(1:n_cmp)) - double(meta.phys(1:n_cmp))));
            if max_err > FLOAT_TOL
                err = sprintf('max_err=%.6f > tol=%.6f', max_err, FLOAT_TOL);
                prog = log_fail(prog, ci, meta, 'MISMATCH', err, meta.data_ptr);
            else
                prog.n_pass = prog.n_pass + 1;
                fprintf('     [PASS] max_err=%.2e\n', max_err);
            end
        end

        prog.ch_idx = ci + 1;
        prog = maybe_checkpoint(prog, progress_file, ci, PAUSE_EVERY);

    end  % while

    % ------------------------------------------------------------------ %
    %  Final report
    % ------------------------------------------------------------------ %
    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('  WRITER COMPLETE\n');
    fprintf('  Output    : %s\n', output_ld_file);
    fprintf('  Channels  : %d\n', prog.n_ch);
    fprintf('  PASS      : %d\n', prog.n_pass);
    fprintf('  SKIP      : %d  (no phys data — channel not in reader output)\n', prog.n_skip);
    fprintf('  FAIL      : %d\n', numel(prog.invalid_log));
    fprintf('============================================================\n');

    print_invalid_log(prog.invalid_log);

    if ~isempty(prog.invalid_log)
        rpt = strrep(progress_file, '.mat', '_FINAL_invalid.mat');
        invalid_log = prog.invalid_log; %#ok
        save(rpt, 'invalid_log', '-v7');
        fprintf('\nInvalid log saved: %s\n', rpt);
    end

    if isempty(prog.invalid_log) && exist(progress_file, 'file')
        delete(progress_file);
        fprintf('Progress file cleaned up.\n');
    end
end


% ======================================================================= %
%  BUILD PROGRESS — read master, copy to output, walk binary channel list
% ======================================================================= %
function prog = build_progress(source_ld_file, output_ld_file, META_BYTES, FLOAT_TOL)

    % Copy master → output (byte-exact baseline so pointers are untouched)
    fprintf('Copying master → output (byte-exact baseline)...\n');
    [ok, msg] = copyfile(source_ld_file, output_ld_file, 'f');
    if ~ok, error('copyfile failed: %s', msg); end

    % File size
    d = dir(source_ld_file);
    file_sz = d.bytes;

    % Read all channels via the existing reader
    fprintf('Running motec_ld_reader on master...\n');
    src_data = motec_ld_reader(source_ld_file);

    % Walk binary to collect raw metadata (pointers, scaling, strings)
    fprintf('Walking binary linked list...\n');
    channels = walk_binary(source_ld_file, file_sz, src_data, META_BYTES);
    fprintf('  %d channel records found.\n', numel(channels));

    prog.source_file  = source_ld_file;
    prog.output_file  = output_ld_file;
    prog.file_sz      = file_sz;
    prog.channels     = channels;
    prog.n_ch         = numel(channels);
    prog.ch_idx       = 1;
    prog.n_pass       = 0;
    prog.n_skip       = 0;
    prog.float_tol    = FLOAT_TOL;
    prog.invalid_log  = {};
end


% ======================================================================= %
%  WALK BINARY — parse every channel metadata record from raw file
% ======================================================================= %
function channels = walk_binary(filepath, file_sz, src_data, META_BYTES) %#ok

    fid = fopen(filepath, 'rb');
    if fid < 0, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0x0008, 'bof');
    first_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

    channels    = struct([]);
    current_ptr = first_ptr;
    idx         = 0;

    while current_ptr ~= 0 && current_ptr < file_sz

        fseek(fid, current_ptr, 'bof');

        prev_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        next_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_len    = fread(fid, 1, 'uint32=>double', 0, 'l');
        sr_raw      = fread(fid, 1, 'uint16=>double', 0, 'l');
        unk1        = fread(fid, 1, 'uint16=>double', 0, 'l');
        datatype    = fread(fid, 1, 'uint16=>double', 0, 'l');
        sample_rate = fread(fid, 1, 'uint16=>double', 0, 'l');
        ch_offset   = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_mul      = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_scale    = fread(fid, 1, 'int16=>double',  0, 'l');
        dec_places  = fread(fid, 1, 'int16=>double',  0, 'l');
        name_raw    = fread(fid, 32, 'uint8=>double')';
        short_raw   = fread(fid, 8,  'uint8=>double')';
        units_raw   = fread(fid, 12, 'uint8=>double')';

        % Confirm we read exactly META_BYTES from meta_ptr
        % current_ptr + META_BYTES = expected end
        pos_after = ftell(fid);
        if (pos_after - current_ptr) ~= META_BYTES
            warning('walk_binary: ch%d record size mismatch at 0x%X (read %d, expected %d)', ...
                idx+1, current_ptr, pos_after - current_ptr, META_BYTES);
        end

        name_str  = doubles_to_str(name_raw);
        units_str = doubles_to_str(units_raw);
        short_str = doubles_to_str(short_raw);

        % Match to reader output — by sanitised fieldname first, then raw_name
        phys  = [];
        field = sanitise_fieldname(name_str);
        if ~isempty(field) && isfield(src_data, field)
            phys = src_data.(field).data;
        else
            % Fallback: scan all fields for matching raw_name
            fnames = fieldnames(src_data);
            for f = 1:numel(fnames)
                fn = fnames{f};
                if isstruct(src_data.(fn)) && isfield(src_data.(fn), 'raw_name') ...
                        && strcmp(src_data.(fn).raw_name, name_str)
                    phys = src_data.(fn).data;
                    break;
                end
            end
        end

        idx = idx + 1;
        channels(idx).meta_ptr   = current_ptr;
        channels(idx).prev_ptr   = prev_ptr;
        channels(idx).next_ptr   = next_ptr;
        channels(idx).data_ptr   = data_ptr;
        channels(idx).data_len   = data_len;
        channels(idx).sr_raw     = sr_raw;
        channels(idx).unk1       = unk1;
        channels(idx).datatype   = datatype;
        channels(idx).sample_rate = sample_rate;
        channels(idx).ch_offset  = ch_offset;
        channels(idx).ch_mul     = ch_mul;
        channels(idx).ch_scale   = ch_scale;
        channels(idx).dec_places = dec_places;
        channels(idx).name_raw   = name_raw;
        channels(idx).short_raw  = short_raw;
        channels(idx).units_raw  = units_raw;
        channels(idx).raw_name   = name_str;
        channels(idx).units_str  = units_str;
        channels(idx).short_str  = short_str;
        channels(idx).phys       = phys;

        current_ptr = next_ptr;
        if idx > 5000
            warning('walk_binary: 5000 channel limit hit.');
            break;
        end
    end
end


% ======================================================================= %
%  ENCODE — phys data → raw uint8 bytes (reverse of reader scaling)
% ======================================================================= %
function [raw_bytes, n_samp, ok, err] = encode_channel(meta)

    raw_bytes = uint8([]);
    n_samp    = 0;
    ok        = true;
    err       = '';

    phys = meta.phys;
    if isempty(phys)
        err = 'no phys data (channel not matched in reader output)';
        ok  = false;
        return;
    end

    phys_d = double(phys(:));
    n_samp = numel(phys_d);

    try
        switch meta.datatype

            case 1
                % float16: phys is already physical values, encode to uint16
                u16       = double_to_float16(phys_d);
                raw_bytes = typecast(uint16(u16(:)), 'uint8');

            case 2
                % int16: raw = (phys - offset) * 10^dec * (scale/mul)
                raw_d     = reverse_scale(phys_d, meta.ch_offset, meta.ch_mul, ...
                                          meta.ch_scale, meta.dec_places);
                i16       = int16(round(raw_d));
                raw_bytes = typecast(i16, 'uint8');

            case 3
                % int32: same scaling as int16, wider type
                raw_d     = reverse_scale(phys_d, meta.ch_offset, meta.ch_mul, ...
                                          meta.ch_scale, meta.dec_places);
                i32       = int32(round(raw_d));
                raw_bytes = typecast(i32, 'uint8');

            case 4
                % int16 + 2 zero-pad bytes per sample = 4 bytes/sample
                % forward: phys = int16_raw / 10^dec + offset
                % inverse: int16_raw = round((phys - offset) * 10^dec)
                raw_d = round((phys_d - meta.ch_offset) .* (10^meta.dec_places));
                i16   = int16(raw_d);
                % Build interleaved [lo hi 0 0] per sample
                i16_b = reshape(typecast(i16, 'uint8'), 2, n_samp);   % 2 x n
                pad_b = zeros(2, n_samp, 'uint8');
                raw_bytes = [i16_b; pad_b];   % 4 x n
                raw_bytes = raw_bytes(:);      % column, interleaved

            otherwise
                err = sprintf('unknown datatype %d', meta.datatype);
                ok  = false;
        end

        raw_bytes = raw_bytes(:);  % ensure column uint8

    catch ME
        err = ME.message;
        ok  = false;
    end
end


% ======================================================================= %
%  READ BACK ONE CHANNEL for verification (mirrors reader decode exactly)
% ======================================================================= %
function [rb_phys, ok, err] = readback_channel(output_file, meta)

    rb_phys = [];
    ok      = false;
    err     = '';

    try
        fid = fopen(output_file, 'rb');
        if fid < 0, err = 'cannot open output file'; return; end
        c = onCleanup(@() fclose(fid));

        fseek(fid, meta.data_ptr, 'bof');
        n = meta.data_len;

        switch meta.datatype
            case 1
                u16     = fread(fid, n, 'uint16=>double', 0, 'l');
                rb_phys = float16_to_double(u16);
            case 2
                raw     = fread(fid, n, 'int16=>double', 0, 'l');
                rb_phys = apply_scale(raw, meta.ch_offset, meta.ch_mul, ...
                                      meta.ch_scale, meta.dec_places);
            case 3
                raw     = fread(fid, n, 'int32=>double', 0, 'l');
                rb_phys = apply_scale(raw, meta.ch_offset, meta.ch_mul, ...
                                      meta.ch_scale, meta.dec_places);
            case 4
                raw     = fread(fid, n, 'int16=>double', 2, 'l');
                rb_phys = raw ./ (10^meta.dec_places) + meta.ch_offset;
            otherwise
                err = sprintf('unknown datatype %d', meta.datatype);
                return;
        end
        ok = true;

    catch ME
        err = ME.message;
    end
end


% ======================================================================= %
%  CHECKPOINT — save progress + pause + report every PAUSE_EVERY channels
% ======================================================================= %
function prog = maybe_checkpoint(prog, progress_file, ci, PAUSE_EVERY)
    save(progress_file, 'prog', '-v7');
    if mod(ci, PAUSE_EVERY) ~= 0
        return;
    end

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('  CHECKPOINT  —  channel %d / %d\n', ci, prog.n_ch);
    fprintf('  PASS    : %d\n', prog.n_pass);
    fprintf('  SKIP    : %d  (no phys data)\n', prog.n_skip);
    fprintf('  FAIL    : %d\n', numel(prog.invalid_log));
    fprintf('  Progress: %s\n', progress_file);
    fprintf('============================================================\n');

    if ~isempty(prog.invalid_log)
        fprintf('\n  Invalid byte pointer / data entries so far:\n\n');
        print_invalid_log(prog.invalid_log);
    else
        fprintf('\n  No invalid entries so far.\n');
    end

    % Save a timestamped snapshot of invalid entries at this checkpoint
    if ~isempty(prog.invalid_log)
        snap = strrep(progress_file, '.mat', sprintf('_invalid_ch%04d.mat', ci));
        invalid_log = prog.invalid_log; %#ok
        save(snap, 'invalid_log', '-v7');
        fprintf('\n  Snapshot saved: %s\n', snap);
    end

    fprintf('\n  [PAUSED]  Re-run motec_ld_writer(...) to continue from ch %d.\n', ci+1);
    fprintf('            Ctrl+C now if you want to inspect before continuing.\n\n');
    input('  Press Enter to continue > ', 's');
end


% ======================================================================= %
%  HELPERS
% ======================================================================= %

function prog = log_fail(prog, ci, meta, category, err_msg, ptr)
    entry.ch_idx   = ci;
    entry.ch_name  = meta.raw_name;
    entry.meta_ptr = meta.meta_ptr;
    entry.data_ptr = ptr;
    entry.category = category;
    entry.datatype = meta.datatype;
    entry.msg      = err_msg;
    prog.invalid_log{end+1} = entry;
    fprintf('  [FAIL:%s] %s\n', category, err_msg);
end

function print_invalid_log(log)
    if isempty(log)
        fprintf('  (none)\n');
        return;
    end
    fprintf('  %-4s  %-32s  %-10s  %-12s  %s\n', ...
        'Ch', 'Name', 'Category', 'data_ptr', 'Message');
    fprintf('  %s\n', repmat('-', 1, 78));
    for i = 1:numel(log)
        e = log{i};
        nm = e.ch_name;
        if numel(nm) > 32, nm = [nm(1:29) '...']; end
        fprintf('  %-4d  %-32s  %-10s  0x%-10X  %s\n', ...
            e.ch_idx, nm, e.category, e.data_ptr, e.msg);
    end
end

function raw_d = reverse_scale(phys_d, ch_offset, ch_mul, ch_scale, dec_places)
% Inverse of: phys = raw * (mul/scale) / 10^dec + offset
    if ch_scale ~= 0 && ch_mul ~= 0
        raw_d = (phys_d - ch_offset) .* (10^dec_places) .* (ch_scale / ch_mul);
    else
        raw_d = (phys_d - ch_offset) .* (10^dec_places);
    end
end

function phys = apply_scale(raw, ch_offset, ch_mul, ch_scale, dec_places)
% Forward scale — mirrors reader logic for int16/int32
    if ch_scale ~= 0 && ch_mul ~= 0
        phys = raw .* (ch_mul / ch_scale) ./ (10^dec_places) + ch_offset;
    else
        phys = raw ./ (10^dec_places) + ch_offset;
    end
end

function u16 = double_to_float16(x)
% Encode double → IEEE 754 half-precision uint16.
% Inverse of motec_ld_reader float16_to_double.
    x   = double(x(:));
    u16 = zeros(size(x), 'uint16');
    sgn = uint16(x < 0);
    ax  = abs(x);

    % NaN
    nm = isnan(ax);
    u16(nm) = uint16(32767);

    % Inf
    im = isinf(ax);
    u16(im) = bitor(bitshift(sgn(im), 15), uint16(31744));

    % Zero
    zm = (ax == 0) & ~nm & ~im;
    u16(zm) = bitshift(sgn(zm), 15);

    % Finite nonzero
    fin = ~nm & ~im & ~zm;
    if any(fin)
        xf  = ax(fin);
        sf  = sgn(fin);
        e   = floor(log2(xf));
        eb  = e + 15;

        u16_f = zeros(sum(fin), 1, 'uint16');

        ov = eb >= 31;
        u16_f(ov) = bitor(bitshift(sf(ov), 15), uint16(31744));  % clamp to Inf

        uv = (eb <= 0) & ~ov;
        if any(uv)
            fs = uint16(min(max(round(xf(uv) ./ 2^(-14) .* 1024), 0), 1023));
            u16_f(uv) = bitor(bitshift(sf(uv), 15), fs);
        end

        nrm = ~ov & ~uv;
        if any(nrm)
            en   = eb(nrm);
            fn   = uint16(min(max(round((xf(nrm) ./ 2.^e(nrm) - 1) .* 1024), 0), 1023));
            u16_f(nrm) = bitor(bitor(bitshift(sf(nrm), 15), ...
                                     bitshift(uint16(en), 10)), fn);
        end

        u16(fin) = u16_f;
    end
end

function out = float16_to_double(u16)
% Mirror of reader helper — kept local for read-back independence
    sign = bitshift(bitand(u16, 32768), -15);
    ex   = bitshift(bitand(u16, 31744), -10);
    frac = bitand(u16, 1023);
    out  = zeros(size(u16));
    nm   = (ex > 0) & (ex < 31);
    out(nm) = (-1).^sign(nm) .* 2.^(ex(nm)-15) .* (1 + frac(nm)/1024);
    sn   = (ex == 0) & (frac ~= 0);
    out(sn) = (-1).^sign(sn) .* 2^-14 .* (frac(sn)/1024);
    out(ex==31 & frac==0) = Inf .* (-1).^sign(ex==31 & frac==0);
    out(ex==31 & frac~=0) = NaN;
end

function write_padded(fid, raw_bytes, n)
% Write uint8 array padded/truncated to exactly n bytes
    b = uint8(raw_bytes(:)');
    b = b(1:min(end,n));
    fwrite(fid, b, 'uint8');
    pad = n - numel(b);
    if pad > 0
        fwrite(fid, zeros(1, pad, 'uint8'), 'uint8');
    end
end

function str = doubles_to_str(d)
    nul = find(d == 0, 1);
    if isempty(nul),     str = strtrim(char(d));
    elseif nul == 1,     str = '';
    else,                str = strtrim(char(d(1:nul-1)));
    end
end

function name = sanitise_fieldname(raw)
    if isempty(raw), name = ''; return; end
    name = regexprep(raw, '[^a-zA-Z0-9_]', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '_$', '');
    if isempty(name), return; end
    if ~isletter(name(1)), name = ['ch_' name]; end
    name = name(1:min(end, 63));
end