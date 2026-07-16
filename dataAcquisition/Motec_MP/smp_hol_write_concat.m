function smp_hol_write_concat(source_file, merged_sess, output_file)
% SMP_HOL_WRITE_CONCAT  Write a merged HOL .ld file from a concat_sessions result.
%
% Copies source_file byte-exact to output_file, then for every channel in
% the 124-byte linked list that has a matching field in merged_sess: encodes
% the full multi-stint data using the channel's OWN mul/scale/dec/offset,
% appends the encoded bytes at the end of the file, and patches only
% data_ptr + data_len in the existing metadata record.  All other metadata
% (channel names, sr_raw, timing tail, scaling) is preserved verbatim.
% No duplicate channels are created.
%
% This is the correct write strategy for any MoTeC concat HOL use-case
% (TeamData, L180, etc.) — replace ld_add_channel for multi-stint outputs.
%
% Supported datatypes
%   2  int16           re-encoded with channel's mul/scale/dec/offset
%   3  int32           re-encoded with channel's mul/scale/dec/offset
%   4  int32           re-encoded with channel's mul/scale/dec/offset
%                       (confirmed via raw byte dump against motec_ld_reader;
%                       previously assumed int16+2-byte-pad, which silently
%                       clamped absolute-value channels — e.g. GPS Latitude/
%                       Longitude — down to int16 range on every round-trip)
%   1  float16         left unchanged (GPS_Time etc. — not critical for HOL)
%
% Usage
%   smp_hol_write_concat(source_file, merged_sess, output_file)
%
%   source_file  — path to a valid .ld file used as binary template
%                  (typically the largest/reference stint file)
%   merged_sess  — struct returned by concat_sessions (first output),
%                  fields named via motec_ld_reader sanitisation rules
%   output_file  — destination .ld path (created / overwritten)

    META_BYTES = 124;

    % ------------------------------------------------------------------ %
    %  1. Copy source -> output (preserves file header + all metadata)
    % ------------------------------------------------------------------ %
    [ok, msg] = copyfile(source_file, output_file, 'f');
    if ~ok, error('smp_hol_write_concat: copyfile failed: %s', msg); end
    fprintf('  HOL template: %s\n', output_file);

    % ------------------------------------------------------------------ %
    %  2. Walk 124-byte channel linked list; replace data blocks
    % ------------------------------------------------------------------ %
    d        = dir(output_file);
    file_end = d.bytes;

    fid = fopen(output_file, 'r+b');
    if fid < 0, error('smp_hol_write_concat: cannot open for r+b: %s', output_file); end
    cl = onCleanup(@() hwc_fclose(fid)); %#ok<NASGU>

    fseek(fid, 0x0008, 'bof');
    current_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    if current_ptr == 0 || current_ptr >= file_end
        error('smp_hol_write_concat: invalid first_meta_ptr 0x%X', current_ptr);
    end

    n_upd = 0;  n_skip = 0;  count = 0;

    while current_ptr ~= 0 && current_ptr < file_end
        fseek(fid, current_ptr, 'bof');
        rec = fread(fid, META_BYTES, 'uint8=>uint8');
        if numel(rec) < META_BYTES
            fprintf('  [WARN] short record at 0x%X -- stopping.\n', current_ptr);
            break;
        end

        next_ptr    = double(typecast(uint8(rec(5:8)),   'uint32'));
        datatype    = double(typecast(uint8(rec(21:22)), 'uint16'));
        sample_rate = double(typecast(uint8(rec(23:24)), 'uint16'));
        ch_offset   = double(typecast(uint8(rec(25:26)), 'int16'));
        ch_mul      = double(typecast(uint8(rec(27:28)), 'int16'));
        ch_scale    = double(typecast(uint8(rec(29:30)), 'int16'));
        ch_dec      = double(typecast(uint8(rec(31:32)), 'int16'));
        name_bytes  = rec(33:64);
        nul         = find(name_bytes == 0, 1);
        if ~isempty(nul), name_bytes = name_bytes(1:nul-1); end
        name_str    = strtrim(char(name_bytes'));
        field       = hwc_sanitise(name_str);

        if ~isempty(field) && isfield(merged_sess, field) && datatype ~= 1
            hch   = merged_sess.(field);
            phys  = double(hch.data(:));
            n_new = numel(phys);

            raw_bytes = hwc_encode(phys, datatype, ch_offset, ch_mul, ch_scale, ch_dec);

            % Append encoded data at end of file
            fseek(fid, 0, 'eof');
            new_data_ptr = ftell(fid);
            fwrite(fid, raw_bytes, 'uint8');
            file_end = new_data_ptr + numel(raw_bytes);

            % Patch data_ptr (rec bytes 9-12, file offset current_ptr+8)
            % and  data_len (rec bytes 13-16, file offset current_ptr+12)
            fseek(fid, current_ptr + 8, 'bof');
            fwrite(fid, uint32(new_data_ptr), 'uint32', 0, 'l');
            fwrite(fid, uint32(n_new),        'uint32', 0, 'l');

            fprintf('    [UPD] %-32s  %d Hz  %d samples  %.1f s\n', ...
                name_str, sample_rate, n_new, n_new / max(sample_rate, 1));
            n_upd = n_upd + 1;
        else
            if datatype == 1
                fprintf('    [SKIP-f16] %-32s\n', name_str);
            elseif isempty(field)
                fprintf('    [SKIP-nm ] %-32s\n', name_str);
            else
                fprintf('    [SKIP-ns ] %-32s\n', name_str);
            end
            n_skip = n_skip + 1;
        end

        current_ptr = next_ptr;
        count = count + 1;
        if count > 5000
            warning('smp_hol_write_concat: 5000-channel limit reached');
            break;
        end
    end

    fclose(fid);
    fprintf('  HOL: %d channels updated, %d skipped\n', n_upd, n_skip);

    % ------------------------------------------------------------------ %
    %  3. Delete stale .ldx cache so i2 Pro rebuilds it
    % ------------------------------------------------------------------ %
    [ldx_dir, ldx_base] = fileparts(output_file);
    ldx_path = fullfile(ldx_dir, [ldx_base '.ldx']);
    if exist(ldx_path, 'file'), delete(ldx_path); end
end


% ======================================================================= %
%  LOCAL HELPERS
% ======================================================================= %

function hwc_fclose(fid)
    try; if fid >= 0 && ~isempty(fopen(fid)), fclose(fid); end; catch; end
end

% -----------------------------------------------------------------------
function field = hwc_sanitise(name_str)
% Mirror motec_ld_reader sanitise_fieldname:
%   replace non-alphanumeric (excl _) with _, strip leading _/digits.
    if isempty(name_str), field = ''; return; end
    s     = regexprep(name_str, '[^a-zA-Z0-9_]', '_');
    s     = regexprep(s, '^[_0-9]+', '');
    field = s;
end

% -----------------------------------------------------------------------
function raw_bytes = hwc_encode(phys, datatype, offset, mul, scale, dec)
% Exact inverse of motec_ld_reader channel decoding.
%   Decode: phys = raw * (mul/scale) / 10^dec + offset
%   Encode: raw  = (phys - offset) * (scale/mul) * 10^dec
    phys = double(phys(:));
    phys(~isfinite(phys)) = 0;
    switch datatype
        case 2  % int16
            if scale ~= 0 && mul ~= 0
                raw_d = (phys - offset) .* (scale / mul) .* (10^dec);
            else
                raw_d = (phys - offset) .* (10^dec);
            end
            raw_d     = max(-32768, min(32767, round(raw_d)));
            raw_bytes = typecast(int16(raw_d), 'uint8');
        case 3  % int32
            if scale ~= 0 && mul ~= 0
                raw_d = (phys - offset) .* (scale / mul) .* (10^dec);
            else
                raw_d = (phys - offset) .* (10^dec);
            end
            raw_bytes = typecast(int32(round(raw_d)), 'uint8');
        case 4  % int32 (matches motec_ld_reader's corrected non-ECU decode —
                % previously assumed int16+pad, which silently clamped
                % absolute-value channels like GPS Latitude/Longitude down
                % to int16 range, corrupting them on every round-trip)
            if scale ~= 0 && mul ~= 0
                raw_d = (phys - offset) .* (scale / mul) .* (10^dec);
            else
                raw_d = (phys - offset) .* (10^dec);
            end
            raw_bytes = typecast(int32(round(raw_d)), 'uint8');
        otherwise
            raw_bytes = uint8([]);
    end
    raw_bytes = raw_bytes(:);
end