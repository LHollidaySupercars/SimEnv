function smp_shift_ld_time(input_file, output_file, offset_s)
% SMP_SHIFT_LD_TIME  Shift the session start time in a MoTeC .ld file by a
% constant offset so that two logger files align when opened together in
% MoTeC i2.
%
% MoTeC i2 uses the embedded date/time header fields to align multiple logs
% on a common timeline. Adjusting the ECU logger's start time by the phase
% offset discovered via xcorr (smp_merge_ecu_dash) makes both files line up
% without touching any sample data.
%
% Usage:
%   smp_shift_ld_time(input_file, output_file, offset_s)
%
%   input_file  — path to the ECU .ld file to shift
%   output_file — path to write the time-corrected copy
%   offset_s    — seconds to ADD to the file's start time
%                 (positive = file starts later, i.e. shift ECU forward)
%                 Use the 'offset_s' variable from smp_merge_ecu_dash.
%
% Header fields patched (ASCII strings, confirmed from motec_ld_info.m):
%   0x005E  date  char[16]  "DD/MM/YYYY"
%   0x007E  time  char[16]  "HH:MM:SS"
%
% The rest of the file (all sample data + metadata) is copied byte-exact.

    if nargin < 3
        error('Usage: smp_shift_ld_time(input_file, output_file, offset_s)');
    end

    DATE_OFFSET = 0x5E;
    TIME_OFFSET = 0x7E;
    DATE_LEN    = 16;
    TIME_LEN    = 16;

    % --- Read existing date/time strings from header ---
    fid = fopen(input_file, 'rb');
    if fid == -1, error('Cannot open input file: %s', input_file); end

    fseek(fid, DATE_OFFSET, 'bof');
    date_bytes = fread(fid, DATE_LEN, 'uint8=>double')';
    fseek(fid, TIME_OFFSET, 'bof');
    time_bytes = fread(fid, TIME_LEN, 'uint8=>double')';
    fclose(fid);

    date_str = strtrim(char(date_bytes(date_bytes > 0)));
    time_str = strtrim(char(time_bytes(time_bytes > 0)));

    fprintf('Original date: "%s"  time: "%s"\n', date_str, time_str);

    % --- Parse date and time ---
    % Expected formats: "DD/MM/YYYY" and "HH:MM:SS"
    dt = parse_datetime(date_str, time_str);
    if isempty(dt)
        error(['Could not parse date/time from header.\n' ...
               'Got: date="%s"  time="%s"\n' ...
               'Expected "DD/MM/YYYY" and "HH:MM:SS".'], date_str, time_str);
    end

    % --- Apply offset ---
    dt_shifted = dt + offset_s / 86400;   % datenum uses days

    new_date_str = datestr(dt_shifted, 'dd/mm/yyyy');
    new_time_str = datestr(dt_shifted, 'HH:MM:SS');

    fprintf('Shifted  date: "%s"  time: "%s"  (offset = %+.4fs)\n', ...
        new_date_str, new_time_str, offset_s);

    % --- Copy file byte-exact, then patch header strings ---
    copy_file_binary(input_file, output_file);

    fid = fopen(output_file, 'r+b');
    if fid == -1, error('Cannot open output file for writing: %s', output_file); end
    c = onCleanup(@() fclose(fid));

    write_fixed_str(fid, DATE_OFFSET, new_date_str, DATE_LEN);
    write_fixed_str(fid, TIME_OFFSET, new_time_str, TIME_LEN);

    fprintf('Written: %s\n', output_file);
end

% -----------------------------------------------------------------------
function dt = parse_datetime(date_str, time_str)
% Parse DD/MM/YYYY and HH:MM:SS into a MATLAB datenum. Returns [] on failure.
    dt = [];
    try
        combined = [strtrim(date_str) ' ' strtrim(time_str)];
        % Try DD/MM/YYYY HH:MM:SS
        dt = datenum(combined, 'dd/mm/yyyy HH:MM:SS');
    catch
        try
            % Fallback: let MATLAB auto-detect
            dt = datenum(combined);
        catch
            % leave empty
        end
    end
end

% -----------------------------------------------------------------------
function write_fixed_str(fid, offset, str, field_len)
% Write a null-padded fixed-length ASCII string at the given byte offset.
    fseek(fid, offset, 'bof');
    bytes = zeros(1, field_len, 'uint8');
    n = min(numel(str), field_len);
    bytes(1:n) = uint8(str(1:n));
    fwrite(fid, bytes, 'uint8');
end

% -----------------------------------------------------------------------
function copy_file_binary(src, dst)
% Byte-exact file copy (no system command, works on all platforms).
    fid_r = fopen(src, 'rb');
    if fid_r == -1, error('Cannot open source: %s', src); end
    fid_w = fopen(dst, 'wb');
    if fid_w == -1, fclose(fid_r); error('Cannot open dest: %s', dst); end
    cr = onCleanup(@() fclose(fid_r));
    cw = onCleanup(@() fclose(fid_w));

    CHUNK = 4 * 1024 * 1024;   % 4 MB chunks
    while true
        data = fread(fid_r, CHUNK, 'uint8');
        if isempty(data), break; end
        fwrite(fid_w, data, 'uint8');
    end
end
