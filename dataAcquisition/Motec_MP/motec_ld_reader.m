function data = motec_ld_reader(filepath, channels_to_extract)
% MOTEC_LD_READER  Parse a MoTeC .ld binary file without the i2 API licence.
%
% Usage:
%   data = motec_ld_reader('C:\path\to\yourfile.ld')
%       Read all channels (original behaviour, full backwards compatibility).
%
%   data = motec_ld_reader('C:\path\to\yourfile.ld', channels_to_extract)
%       Enhanced mode — only read channels in channels_to_extract (cell array).
%       Channel metadata is still read for every channel (required to walk
%       the linked list), but the fseek+fread of sample data is skipped for
%       channels not in the list. Pass {} to read all channels.
%
% Datatype encoding (confirmed against MoTeC i2):
%   1 = float16  — raw uint16 decoded as IEEE half-precision, already physical
%   2 = int16    — scaled: (raw * mul/scale) / 10^dec + offset
%   3 = int32    — scaled: (raw * mul/scale) / 10^dec + offset
%   4 = int16 + 2 byte padding per sample (4 bytes/sample) — dec/offset only
%
% Post-load normalisation:
%   Distance channels (Trip Distance, Odometer, Distance) are normalised
%   to start at 0. Sentinel/no-fix values below 0 are replaced with NaN.

    % Channel names that should be normalised to start at 0
    DISTANCE_CHANNELS = {'Trip Distance', 'Odometer', 'Distance', 'Trip_Distance'};

    % --- Enhanced mode: build lowercase filter set for fast lookup ---
    if nargin < 2 || isempty(channels_to_extract)
        filter_channels = {};   % empty = read all
    else
        % Include both raw names and sanitised fieldname versions
        sanitised = cellfun(@(c) lower(regexprep(c, '[^a-zA-Z0-9_]', '_')), ...
                            channels_to_extract, 'UniformOutput', false);
        filter_channels = unique([lower(channels_to_extract(:)); sanitised(:)]);
    end
    enhanced_mode = ~isempty(filter_channels);

    fid = fopen(filepath, 'rb');
    if fid == -1
        error('Could not open file: %s', filepath);
    end
    c = onCleanup(@() fclose(fid));

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);

    % Session info
    fseek(fid, 0x0004, 'bof');
    event_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    if event_ptr > 0 && event_ptr < file_sz
        fseek(fid, event_ptr + 0x10, 'bof');
        raw = fread(fid, 64, 'uint8=>double')';
        nul = find(raw == 0, 1);
        if ~isempty(nul) && nul > 1
            fprintf('Session: %s\n', char(raw(1:nul-1)));
        end
    end

    % First channel pointer
    fseek(fid, 0x0008, 'bof');
    first_meta_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
    if first_meta_ptr == 0 || first_meta_ptr >= file_sz
        error('Invalid first channel metadata pointer: 0x%X', first_meta_ptr);
    end
    fprintf('First channel ptr: 0x%X\n\n', first_meta_ptr);

    data          = struct();
    channel_count = 0;
    current_ptr   = first_meta_ptr;

    while current_ptr ~= 0 && current_ptr < file_sz

        % --- Read metadata fields sequentially ---
        fseek(fid, current_ptr, 'bof');
        prev_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l'); %#ok
        next_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
        data_len    = fread(fid, 1, 'uint32=>double', 0, 'l');
        fread(fid,  1, 'uint16=>double', 0, 'l');              % sr_raw (not true Hz)
        fread(fid,  1, 'uint16=>double', 0, 'l');              % unk1
        datatype    = fread(fid, 1, 'uint16=>double', 0, 'l');
        sample_rate = fread(fid, 1, 'uint16=>double', 0, 'l'); % unk2 = true Hz
        ch_offset   = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_mul      = fread(fid, 1, 'int16=>double',  0, 'l');
        ch_scale    = fread(fid, 1, 'int16=>double',  0, 'l');
        dec_places  = fread(fid, 1, 'int16=>double',  0, 'l');
        % Now at +0x20 — channel name
        name_raw  = fread(fid, 32, 'uint8=>double')';
        % skip short name (+0x40, 8 bytes)
        fread(fid, 8, 'uint8=>double');
        % units at +0x50
        units_raw = fread(fid, 12, 'uint8=>double')';

        % Parse null-terminated strings
        name_str  = doubles_to_str(name_raw);
        units_str = doubles_to_str(units_raw);

        % --- Enhanced mode: skip data read if channel not requested ---
        if enhanced_mode
            field_candidate = lower(sanitise_fieldname(name_str));
            if ~ismember(lower(name_str), filter_channels) && ...
               ~ismember(field_candidate, filter_channels)
                current_ptr = next_ptr;
                continue;
            end
        end

        % --- Read and scale data ---
        if data_ptr > 0 && data_ptr < file_sz && data_len > 0

            fseek(fid, data_ptr, 'bof');

            switch datatype
                case 1
                    % float16 — decode from uint16 bit pattern, already physical
                    raw_u16  = fread(fid, data_len, 'uint16=>double', 0, 'l');
                    raw_data = float16_to_double(raw_u16);
                    phys     = raw_data;

                case 2
                    % int16 — full mul/scale/dec/offset scaling
                    raw_data = fread(fid, data_len, 'int16=>double', 0, 'l');
                    if ch_scale ~= 0 && ch_mul ~= 0
                        phys = raw_data .* (ch_mul / ch_scale) ./ (10^dec_places) + ch_offset;
                    else
                        phys = raw_data ./ (10^dec_places) + ch_offset;
                    end

                case 3
                    % int32 — full mul/scale/dec/offset scaling
                    raw_data = fread(fid, data_len, 'int32=>double', 0, 'l');
                    if ch_scale ~= 0 && ch_mul ~= 0
                        phys = raw_data .* (ch_mul / ch_scale) ./ (10^dec_places) + ch_offset;
                    else
                        phys = raw_data ./ (10^dec_places) + ch_offset;
                    end

                case 4
                    % int16 with 2 bytes padding per sample (4 bytes total per sample)
                    % data_len = number of samples, each 4 bytes wide
                    % fread skip=2 reads int16 then skips 2 bytes before next read
                    raw_data = fread(fid, data_len, 'int16=>double', 2, 'l');
                    phys     = raw_data ./ (10^dec_places) + ch_offset;

                otherwise
                    fprintf('  [??] %-32s  unknown datatype %d\n', name_str, datatype);
                    current_ptr = next_ptr;
                    continue
            end

            % --- Post-load normalisation for distance channels ---
            % Normalise to start at 0 and NaN out sentinel/no-fix values
            if any(strcmpi(name_str, DISTANCE_CHANNELS))
                valid = isfinite(phys);
                if any(valid)
                    phys = phys - min(phys(valid));
                end
                phys(phys < 0) = NaN;
            end

            if sample_rate > 0
                time_vec = (0 : numel(phys)-1)' / sample_rate;
            else
                time_vec = (0 : numel(phys)-1)';
            end

            field = sanitise_fieldname(name_str);
            if ~isempty(field)
                if isfield(data, field)
                    field = sprintf('%s_%d', field, channel_count);
                end
                data.(field).data        = phys;
                data.(field).time        = time_vec;
                data.(field).units       = units_str;
                data.(field).sample_rate = sample_rate;
                data.(field).raw_name    = name_str;
                channel_count = channel_count + 1;
                fprintf('  [%3d] %-35s %5g Hz  %7d samples  [%s]\n', ...
                    channel_count, name_str, sample_rate, data_len, units_str);
            end

        else
            if ~isempty(name_str)
                fprintf('  [---] %-35s  no data\n', name_str);
            end
        end

        current_ptr = next_ptr;

        if channel_count > 5000
            warning('Exceeded 5000 channels — stopping.');
            break;
        end
    end

    fprintf('\nLoaded %d channels.\n', channel_count);
end


% ======================================================================= %
function str = doubles_to_str(d)
% Convert a double array of ASCII codes to a string, stopping at null (0).
    nul = find(d == 0, 1);
    if isempty(nul)
        str = strtrim(char(d));
    elseif nul == 1
        str = '';
    else
        str = strtrim(char(d(1:nul-1)));
    end
end


% ======================================================================= %
function out = float16_to_double(u16)
    sign = bitshift(bitand(u16, 32768), -15);
    exp  = bitshift(bitand(u16, 31744), -10);
    frac = bitand(u16, 1023);
    out  = zeros(size(u16));

    nm = (exp > 0) & (exp < 31);
    out(nm) = (-1).^sign(nm) .* 2.^(exp(nm)-15) .* (1 + frac(nm)/1024);

    sn = (exp == 0) & (frac ~= 0);
    out(sn) = (-1).^sign(sn) .* 2^-14 .* (frac(sn)/1024);

    out(exp==31 & frac==0) = Inf .* (-1).^sign(exp==31 & frac==0);
    out(exp==31 & frac~=0) = NaN;
end


% ======================================================================= %
function name = sanitise_fieldname(raw)
    if isempty(raw)
        name = '';
        return;
    end
    name = regexprep(raw, '[^a-zA-Z0-9_]', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '_$', '');
    if isempty(name), return; end
    if ~isletter(name(1)), name = ['ch_' name]; end
    name = name(1:min(end, 63));
end

% function data = motec_ld_reader(filepath)
% % MOTEC_LD_READER  Parse a MoTeC .ld binary file without the i2 API licence.
% %
% % Usage:
% %   data = motec_ld_reader('C:\path\to\yourfile.ld')
% %
% % Datatype encoding (confirmed against MoTeC i2):
% %   1 = float16  — raw uint16 decoded as IEEE half-precision, already physical
% %   2 = int16    — scaled: (raw * mul/scale) / 10^dec + offset
% %   3 = int32    — scaled: (raw * mul/scale) / 10^dec + offset
% %   4 = int16 + 2 byte padding per sample (4 bytes/sample) — dec/offset only
% %
% % Post-load normalisation:
% %   Distance channels (Trip Distance, Odometer, Distance) are normalised
% %   to start at 0. Sentinel/no-fix values below 0 are replaced with NaN.
% 
%     % Channel names that should be normalised to start at 0
%     DISTANCE_CHANNELS = {'Trip Distance', 'Odometer', 'Distance', 'Trip_Distance'};
% 
%     fid = fopen(filepath, 'rb');
%     if fid == -1
%         error('Could not open file: %s', filepath);
%     end
%     c = onCleanup(@() fclose(fid));
% 
%     fseek(fid, 0, 'eof');
%     file_sz = ftell(fid);
% 
%     % Session info
%     fseek(fid, 0x0004, 'bof');
%     event_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
%     if event_ptr > 0 && event_ptr < file_sz
%         fseek(fid, event_ptr + 0x10, 'bof');
%         raw = fread(fid, 64, 'uint8=>double')';
%         nul = find(raw == 0, 1);
%         if ~isempty(nul) && nul > 1
%             fprintf('Session: %s\n', char(raw(1:nul-1)));
%         end
%     end
% 
%     % First channel pointer
%     fseek(fid, 0x0008, 'bof');
%     first_meta_ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
%     if first_meta_ptr == 0 || first_meta_ptr >= file_sz
%         error('Invalid first channel metadata pointer: 0x%X', first_meta_ptr);
%     end
%     fprintf('First channel ptr: 0x%X\n\n', first_meta_ptr);
% 
%     data          = struct();
%     channel_count = 0;
%     current_ptr   = first_meta_ptr;
% 
%     while current_ptr ~= 0 && current_ptr < file_sz
% 
%         % --- Read metadata fields sequentially ---
%         fseek(fid, current_ptr, 'bof');
%         prev_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l'); %#ok
%         next_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
%         data_ptr    = fread(fid, 1, 'uint32=>double', 0, 'l');
%         data_len    = fread(fid, 1, 'uint32=>double', 0, 'l');
%         fread(fid,  1, 'uint16=>double', 0, 'l');              % sr_raw (not true Hz)
%         fread(fid,  1, 'uint16=>double', 0, 'l');              % unk1
%         datatype    = fread(fid, 1, 'uint16=>double', 0, 'l');
%         sample_rate = fread(fid, 1, 'uint16=>double', 0, 'l'); % unk2 = true Hz
%         ch_offset   = fread(fid, 1, 'int16=>double',  0, 'l');
%         ch_mul      = fread(fid, 1, 'int16=>double',  0, 'l');
%         ch_scale    = fread(fid, 1, 'int16=>double',  0, 'l');
%         dec_places  = fread(fid, 1, 'int16=>double',  0, 'l');
%         % Now at +0x20 — channel name
%         name_raw  = fread(fid, 32, 'uint8=>double')';
%         % skip short name (+0x40, 8 bytes)
%         fread(fid, 8, 'uint8=>double');
%         % units at +0x50
%         units_raw = fread(fid, 12, 'uint8=>double')';
% 
%         % Parse null-terminated strings
%         name_str  = doubles_to_str(name_raw);
%         units_str = doubles_to_str(units_raw);
% 
%         % --- Read and scale data ---
%         if data_ptr > 0 && data_ptr < file_sz && data_len > 0
% 
%             fseek(fid, data_ptr, 'bof');
% 
%             switch datatype
%                 case 1
%                     % float16 — decode from uint16 bit pattern, already physical
%                     raw_u16  = fread(fid, data_len, 'uint16=>double', 0, 'l');
%                     raw_data = float16_to_double(raw_u16);
%                     phys     = raw_data;
% 
%                 case 2
%                     % int16 — full mul/scale/dec/offset scaling
%                     raw_data = fread(fid, data_len, 'int16=>double', 0, 'l');
%                     if ch_scale ~= 0 && ch_mul ~= 0
%                         phys = raw_data .* (ch_mul / ch_scale) ./ (10^dec_places) + ch_offset;
%                     else
%                         phys = raw_data ./ (10^dec_places) + ch_offset;
%                     end
% 
%                 case 3
%                     % int32 — full mul/scale/dec/offset scaling
%                     raw_data = fread(fid, data_len, 'int32=>double', 0, 'l');
%                     if ch_scale ~= 0 && ch_mul ~= 0
%                         phys = raw_data .* (ch_mul / ch_scale) ./ (10^dec_places) + ch_offset;
%                     else
%                         phys = raw_data ./ (10^dec_places) + ch_offset;
%                     end
% 
%                 case 4
%                     % int16 with 2 bytes padding per sample (4 bytes total per sample)
%                     % data_len = number of samples, each 4 bytes wide
%                     % fread skip=2 reads int16 then skips 2 bytes before next read
%                     raw_data = fread(fid, data_len, 'int16=>double', 2, 'l');
%                     phys     = raw_data ./ (10^dec_places) + ch_offset;
% 
%                 otherwise
%                     fprintf('  [??] %-32s  unknown datatype %d\n', name_str, datatype);
%                     current_ptr = next_ptr;
%                     continue
%             end
% 
%             % --- Post-load normalisation for distance channels ---
%             % Normalise to start at 0 and NaN out sentinel/no-fix values
%             if any(strcmpi(name_str, DISTANCE_CHANNELS))
%                 valid = isfinite(phys);
%                 if any(valid)
%                     phys = phys - min(phys(valid));
%                 end
%                 phys(phys < 0) = NaN;
%             end
% 
%             if sample_rate > 0
%                 time_vec = (0 : numel(phys)-1)' / sample_rate;
%             else
%                 time_vec = (0 : numel(phys)-1)';
%             end
% 
%             field = sanitise_fieldname(name_str);
%             if ~isempty(field)
%                 if isfield(data, field)
%                     field = sprintf('%s_%d', field, channel_count);
%                 end
%                 data.(field).data        = phys;
%                 data.(field).time        = time_vec;
%                 data.(field).units       = units_str;
%                 data.(field).sample_rate = sample_rate;
%                 data.(field).raw_name    = name_str;
%                 channel_count = channel_count + 1;
%                 fprintf('  [%3d] %-35s %5g Hz  %7d samples  [%s]\n', ...
%                     channel_count, name_str, sample_rate, data_len, units_str);
%             end
% 
%         else
%             if ~isempty(name_str)
%                 fprintf('  [---] %-35s  no data\n', name_str);
%             end
%         end
% 
%         current_ptr = next_ptr;
% 
%         if channel_count > 5000
%             warning('Exceeded 5000 channels — stopping.');
%             break;
%         end
%     end
% 
%     fprintf('\nLoaded %d channels.\n', channel_count);
% end
% 
% 
% % ======================================================================= %
% function str = doubles_to_str(d)
% % Convert a double array of ASCII codes to a string, stopping at null (0).
%     nul = find(d == 0, 1);
%     if isempty(nul)
%         str = strtrim(char(d));
%     elseif nul == 1
%         str = '';
%     else
%         str = strtrim(char(d(1:nul-1)));
%     end
% end
% 
% 
% % ======================================================================= %
% function out = float16_to_double(u16)
%     sign = bitshift(bitand(u16, 32768), -15);
%     exp  = bitshift(bitand(u16, 31744), -10);
%     frac = bitand(u16, 1023);
%     out  = zeros(size(u16));
% 
%     nm = (exp > 0) & (exp < 31);
%     out(nm) = (-1).^sign(nm) .* 2.^(exp(nm)-15) .* (1 + frac(nm)/1024);
% 
%     sn = (exp == 0) & (frac ~= 0);
%     out(sn) = (-1).^sign(sn) .* 2^-14 .* (frac(sn)/1024);
% 
%     out(exp==31 & frac==0) = Inf .* (-1).^sign(exp==31 & frac==0);
%     out(exp==31 & frac~=0) = NaN;
% end
% 
% 
% % ======================================================================= %
% function name = sanitise_fieldname(raw)
%     if isempty(raw)
%         name = '';
%         return;
%     end
%     name = regexprep(raw, '[^a-zA-Z0-9_]', '_');
%     name = regexprep(name, '_+', '_');
%     name = regexprep(name, '_$', '');
%     if isempty(name), return; end
%     if ~isletter(name(1)), name = ['ch_' name]; end
%     name = name(1:min(end, 63));
% end