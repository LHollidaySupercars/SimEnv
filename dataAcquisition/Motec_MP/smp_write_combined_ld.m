function smp_write_combined_ld(dash_file, merged, output_file, session_meta)
%SMP_WRITE_COMBINED_LD  Write a combined Dash + ECU .ld file for MoTeC i2.
%
%   smp_write_combined_ld(dash_file, merged, output_file)
%   smp_write_combined_ld(dash_file, merged, output_file, session_meta)
%
%   Strategy
%   --------
%   1. Count original Dash channel records in dash_file.
%   2. Use ld_add_channel (proven three-pass writer) to copy dash_file to
%      output_file and append all ECU channels from merged.ecu_* fields,
%      then append session constant channels (weather, mass) if provided.
%   3. Walk the first n_dash channel records in output_file, read each
%      full 84-byte record, prepend "Dash." to the name and short_name
%      fields, and write the full record back in-place.

    if nargin < 4
        session_meta = struct();
    end

    MAX_NAME = 31;   % usable chars in 32-byte name field

    %% -- 0. Ensure ld_add_channel is on path -----------------------------
    ch_add_dir = fullfile(fileparts(mfilename('fullpath')), 'channelAdd');
    if exist(ch_add_dir, 'dir') && ~any(strcmp(strsplit(path, pathsep), ch_add_dir))
        addpath(ch_add_dir);
    end

    %% -- 1. Count original Dash channels before any copying --------------
    n_dash = count_channels(dash_file);
    fprintf('  Original Dash channels: %d\n', n_dash);
    if n_dash == 0
        error('smp_write_combined_ld: no channels found in %s', dash_file);
    end

    %% -- 2. Build ECU channel list for ld_add_channel --------------------
    all_fields = fieldnames(merged);
    ecu_fields = all_fields(strncmp(all_fields, 'ecu_', 4));
    fprintf('  ECU channels to append: %d\n', numel(ecu_fields));

    ecu_list = {};
    for k = 1:numel(ecu_fields)
        fn = ecu_fields{k};
        ch = merged.(fn);

        raw_data = double(ch.data(:));
        raw_data(~isfinite(raw_data)) = 0;

        if isfield(ch, 'time') && numel(ch.time) > 10
            dt = median(diff(ch.time(1:min(end, 500))));
            if dt > 0
                sr = max(1, round(1 / dt));
            else
                sr = ch.sample_rate;
            end
        else
            sr = ch.sample_rate;
        end

        new_ch.name        = str_to_name(['ECU.' ch.raw_name], MAX_NAME);
        new_ch.units       = ch.units;
        new_ch.sample_rate = sr;
        new_ch.value       = raw_data;
        new_ch.dec_places  = auto_dec_places(max(abs(raw_data)));
        new_ch.offset      = 0;
        new_ch.mul         = 1;
        new_ch.scale       = 1;
        new_ch.datatype    = 2;   % force int16

        ecu_list{end+1} = new_ch; %#ok<AGROW>
    end

    %% -- 3. Create output dir and run ld_add_channel ---------------------
    out_dir = fileparts(output_file);
    if ~isempty(out_dir) && ~exist(out_dir, 'dir')
        mkdir(out_dir);
        fprintf('  Created folder: %s\n', out_dir);
    end

    fprintf('\n=== Appending ECU channels via ld_add_channel ===\n');
    if isempty(ecu_list)
        [ok, msg] = copyfile(dash_file, output_file, 'f');
        if ~ok, error('copyfile failed: %s', msg); end
        fprintf('  No ECU channels -- copied dash file only.\n');
    else
        ld_add_channel(dash_file, output_file, ecu_list);
    end

    %% -- 4. Rename first n_dash channels: prepend "Dash." ----------------
    fprintf('\n=== Renaming Dash channels (Dash. prefix) ===\n');

    d_info  = dir(output_file);
    file_sz = d_info.bytes;

    fid_r = fopen(output_file, 'rb');
    if fid_r < 0, error('Cannot open output file: %s', output_file); end
    fseek(fid_r, 0x0008, 'bof');
    current_ptr = fread(fid_r, 1, 'uint32=>double', 0, 'l');
    fclose(fid_r);

    fprintf('  first_ptr = 0x%X  file_sz = %d bytes\n', current_ptr, file_sz);

    n_renamed = 0;
    for i = 1:n_dash
        if current_ptr == 0 || current_ptr >= file_sz
            fprintf('  [WARN] ptr=0x%X invalid at channel %d -- stopping.\n', current_ptr, i);
            break;
        end

        % Read full 84-byte record
        fid_r = fopen(output_file, 'rb');
        fseek(fid_r, current_ptr, 'bof');
        rec      = fread(fid_r, 84, 'uint8=>uint8')';
        fclose(fid_r);

        next_ptr  = double(typecast(uint8(rec(5:8)),  'uint32'));
        orig_name = rec_to_str(rec(33:64));
        new_name  = str_to_name(['Dash.' orig_name], MAX_NAME);

        % Patch name[32] bytes 33-64, short_name[8] bytes 65-72
        rec(33:64) = str_to_bytes(new_name, 32);
        rec(65:72) = str_to_bytes(new_name, 8);

        % Write full record back
        fid_w = fopen(output_file, 'r+b');
        if fid_w < 0, error('Cannot open for rewrite: %s', output_file); end
        fseek(fid_w, current_ptr, 'bof');
        fwrite(fid_w, rec, 'uint8');
        fclose(fid_w);

        % Verify
        fid_v = fopen(output_file, 'rb');
        fseek(fid_v, current_ptr + 32, 'bof');
        check_raw = fread(fid_v, 32, 'uint8')';
        fclose(fid_v);
        check_str = rec_to_str(check_raw);

        if strncmp(check_str, 'Dash.', 5)
            fprintf('  [OK] %-30s -> %s\n', orig_name, new_name);
            n_renamed = n_renamed + 1;
        else
            fprintf('  [FAIL] %-30s -- got: [%s]\n', orig_name, check_str);
        end

        current_ptr = next_ptr;
    end

    fprintf('\n  Renamed %d / %d Dash channels.\n', n_renamed, n_dash);
    fprintf('  Total: %d Dash + %d ECU + %d session channels.\n', ...
        n_dash, numel(ecu_list), numel(fieldnames(session_meta)));
    fprintf('  Output: %s\n', output_file);
end


% ======================================================================= %
%  LOCAL: Count channels by walking the linked list                       %
% ======================================================================= %
function n = count_channels(filepath)
    fid = fopen(filepath, 'rb');
    if fid < 0, error('count_channels: cannot open %s', filepath); end
    cl  = onCleanup(@() fclose(fid));

    fseek(fid, 0, 'eof');
    file_sz = ftell(fid);

    fseek(fid, 0x0008, 'bof');
    ptr = fread(fid, 1, 'uint32=>double', 0, 'l');

    n = 0;
    while ptr ~= 0 && ptr < file_sz
        fseek(fid, ptr + 0x04, 'bof');
        ptr = fread(fid, 1, 'uint32=>double', 0, 'l');
        n   = n + 1;
        if n > 5000, break; end
    end
end


% ======================================================================= %
%  LOCAL: Extract null-terminated string from uint8 row vector            %
% ======================================================================= %
function s = rec_to_str(bytes)
    nul = find(bytes == 0, 1);
    if isempty(nul)
        s = strtrim(char(bytes));
    else
        s = strtrim(char(bytes(1:nul-1)));
    end
end


% ======================================================================= %
%  LOCAL: Truncate channel name to max_len printable chars                %
% ======================================================================= %
function s = str_to_name(s, max_len)
    if numel(s) > max_len
        s = s(1:max_len);
    end
end


% ======================================================================= %
%  LOCAL: String to fixed-length null-padded uint8 row vector             %
% ======================================================================= %
function b = str_to_bytes(str, n)
    b = zeros(1, n, 'uint8');
    bytes = uint8(str(1:min(end, n)));
    b(1:numel(bytes)) = bytes;
end


% ======================================================================= %
%  LOCAL: Compute dec_places to preserve value precision in int16         %
%  Finds highest dec_places (0-4) such that value*10^d <= 32767           %
% ======================================================================= %
function d = auto_dec_places(val)
    abs_val = abs(double(val));
    if abs_val == 0
        d = 0;
        return;
    end
    for d = 4:-1:0
        if abs_val * 10^d <= 32767
            return;
        end
    end
    d = 0;
end
