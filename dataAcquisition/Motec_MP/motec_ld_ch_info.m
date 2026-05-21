function info = motec_ld_ch_info(filepath, filter_name)
% MOTEC_LD_CH_INFO  Walk all channel metadata blocks in a MoTeC .ld file
% and print the raw scaling parameters for each channel (or one channel).
%
% This is a diagnostic tool — it reads ONLY metadata (no sample data),
% so it is fast even on large files.
%
% Usage:
%   motec_ld_ch_info('E:\path\to\file.ld')
%       Print metadata for ALL channels.
%
%   motec_ld_ch_info('E:\path\to\file.ld', 'Engine Speed')
%       Print metadata only for the named channel (case-insensitive,
%       also matches sanitised fieldname e.g. 'Engine_Speed').
%
%   info = motec_ld_ch_info(...)
%       Returns a struct array with one entry per matched channel.
%       Fields: raw_name, units, datatype, sample_rate, data_len,
%               ch_mul, ch_scale, dec_places, ch_offset,
%               first_sample (decoded physical value of sample [1]),
%               min_phys, max_phys (range over all samples).
%
% Datatype encoding:
%   1 = float16   (raw uint16 -> IEEE half-precision, already physical)
%   2 = int16     scaled: raw * (mul/scale) / 10^dec + offset
%   3 = int32     scaled: raw * (mul/scale) / 10^dec + offset
%   4 = int16 + 2-byte padding/sample: raw / 10^dec + offset

    if nargin < 2
        filter_name = '';
    end

    fid = fopen(filepath, 'rb');
    if fid == -1, error('Cannot open: %s', filepath); end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);

    fseek(fid, 0x0008, 'bof');
    current_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

    if current_ptr == 0 || current_ptr >= file_sz
        error('Invalid first channel pointer 0x%X in file %s', current_ptr, filepath);
    end

    fprintf('\n%-35s  %4s  %4s  %6s  %6s  %5s  %4s  %6s  %5s  | %s\n', ...
        'Channel', 'Type', 'Hz', 'Len', 'mul', 'scale', 'dec', 'offset', 'unit', 'Phys range (first 100 samples)');
    fprintf('%s\n', repmat('-', 1, 120));

    info    = struct([]);
    n_found = 0;

    while current_ptr ~= 0 && current_ptr < file_sz

        fseek(fid, current_ptr, 'bof');
        fread(fid, 1, 'uint32=>double', 0, 'l');              % prev_ptr
        next_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_len    = fread(fid, 1, 'uint32=>double', 0, 'l');
        fread(fid,  1, 'uint16=>double', 0, 'l');              % sr_raw
        fread(fid,  1, 'uint16=>double', 0, 'l');              % unk1
        datatype    = fread(fid, 1, 'uint16=>double', 0, 'l');
        sample_rate = fread(fid, 1, 'uint16=>double', 0, 'l'); % true Hz
        ch_offset   = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_mul      = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_scale    = fread(fid, 1, 'int16=>double',  0, 'l');
        dec_places  = fread(fid, 1, 'int16=>double',  0, 'l');

        % Channel name at +0x20 (32 bytes, null-terminated)
        fseek(fid, current_ptr + 0x20, 'bof');
        name_raw = fread(fid, 32, 'uint8=>double')';
        name_str = raw_to_str(name_raw);

        % Units at +0x50 (12 bytes, null-terminated)
        fseek(fid, current_ptr + 0x50, 'bof');
        units_raw = fread(fid, 12, 'uint8=>double')';
        units_str = raw_to_str(units_raw);

        % Apply name filter if given
        if ~isempty(filter_name)
            san_filter = lower(regexprep(filter_name, '[^a-zA-Z0-9_]', '_'));
            san_name   = lower(regexprep(name_str,   '[^a-zA-Z0-9_]', '_'));
            if ~strcmpi(name_str, filter_name) && ~strcmpi(san_name, san_filter)
                current_ptr = next_ptr;
                continue;
            end
        end

        % Read a small sample window to show the physical range
        phys_range_str = 'no data';
        first_sample   = NaN;
        min_phys       = NaN;
        max_phys       = NaN;

        n_peek = min(data_len, 500);   % peek at up to 500 samples

        if data_ptr > 0 && data_ptr < file_sz && data_len > 0 && n_peek > 0
            fseek(fid, data_ptr, 'bof');
            try
                switch datatype
                    case 1
                        raw_u16 = fread(fid, n_peek, 'uint16=>double', 0, 'l');
                        phys    = float16_to_double(raw_u16);
                    case 2
                        raw = fread(fid, n_peek, 'int16=>double', 0, 'l');
                        if ch_scale ~= 0 && ch_mul ~= 0
                            phys = raw .* (ch_mul / ch_scale) ./ (10^dec_places) + ch_offset;
                        else
                            phys = raw ./ (10^dec_places) + ch_offset;
                        end
                    case 3
                        raw = fread(fid, n_peek, 'int32=>double', 0, 'l');
                        if ch_scale ~= 0 && ch_mul ~= 0
                            phys = raw .* (ch_mul / ch_scale) ./ (10^dec_places) + ch_offset;
                        else
                            phys = raw ./ (10^dec_places) + ch_offset;
                        end
                    case 4
                        raw  = fread(fid, n_peek, 'int16=>double', 2, 'l');
                        phys = raw ./ (10^dec_places) + ch_offset;
                    otherwise
                        phys = [];
                end

                if ~isempty(phys) && any(isfinite(phys))
                    min_phys     = min(phys(isfinite(phys)));
                    max_phys     = max(phys(isfinite(phys)));
                    first_sample = phys(1);
                    phys_range_str = sprintf('[%.3g, %.3g]  first=%.3g', min_phys, max_phys, first_sample);
                end
            catch
                phys_range_str = 'read error';
            end
        end

        fprintf('%-35s  %4d  %4g  %6d  %6d  %5d  %4d  %6d  %5s  | %s\n', ...
            name_str, datatype, sample_rate, data_len, ...
            ch_mul, ch_scale, dec_places, ch_offset, units_str, phys_range_str);

        n_found = n_found + 1;
        info(n_found).raw_name    = name_str;
        info(n_found).units       = units_str;
        info(n_found).datatype    = datatype;
        info(n_found).sample_rate = sample_rate;
        info(n_found).data_len    = data_len;
        info(n_found).ch_mul      = ch_mul;
        info(n_found).ch_scale    = ch_scale;
        info(n_found).dec_places  = dec_places;
        info(n_found).ch_offset   = ch_offset;
        info(n_found).first_sample = first_sample;
        info(n_found).min_phys    = min_phys;
        info(n_found).max_phys    = max_phys;

        current_ptr = next_ptr;

        if n_found > 5000
            warning('Exceeded 5000 channels — stopping.');
            break;
        end
    end

    if isempty(info)
        if ~isempty(filter_name)
            fprintf('  (no channel matching "%s" found)\n', filter_name);
        end
    else
        fprintf('\nTotal channels found: %d\n', n_found);
    end

    if nargout == 0
        clear info;
    end
end

% -----------------------------------------------------------------------
function str = raw_to_str(d)
    nul = find(d == 0, 1);
    if isempty(nul)
        str = strtrim(char(d));
    elseif nul == 1
        str = '';
    else
        str = strtrim(char(d(1:nul-1)));
    end
end

% -----------------------------------------------------------------------
function out = float16_to_double(u16)
% Decode IEEE 754 half-precision uint16 array to double.
    sign_bit  = bitshift(u16, -15);
    exp_bits  = bitand(bitshift(u16, -10), 0x1F);
    mant_bits = bitand(u16, 0x3FF);

    out = zeros(size(u16));

    % Normal numbers
    norm = exp_bits > 0 & exp_bits < 31;
    out(norm) = (-1).^sign_bit(norm) .* 2.^(double(exp_bits(norm)) - 15) .* ...
                (1 + double(mant_bits(norm)) / 1024);

    % Subnormals
    sub = exp_bits == 0 & mant_bits ~= 0;
    out(sub) = (-1).^sign_bit(sub) .* 2^(-14) .* (double(mant_bits(sub)) / 1024);

    % Inf / NaN
    out(exp_bits == 31 & mant_bits == 0) = Inf;
    out(exp_bits == 31 & mant_bits ~= 0) = NaN;
end
