function smp_append_session_meta(com_file, session_meta, dash_t)
%SMP_APPEND_SESSION_META  Append session constant channels to a combined .ld file.
%
%   smp_append_session_meta(com_file, session_meta, dash_t)
%
%   Appends weather/mass channels (Temperature, Humidity, etc.) from
%   session_meta as constant-value time-series channels to com_file.
%
%   Uses the vector path in ld_add_channel (ch.value = vector) so that
%   sample count is derived from dash_t, not from a donor channel.
%   This ensures correct time alignment in MoTeC i2.
%
%   Parameters:
%     com_file      - path to the combined .ld file to append to (modified in-place)
%     session_meta  - struct from smp_session_metadata_load (fields: .name, .value, .units)
%     dash_t        - Dash logger time vector (seconds), used to compute session duration

    % Ensure ld_add_channel is on path
    ch_add_dir = fullfile(fileparts(mfilename('fullpath')), 'channelAdd');
    if exist(ch_add_dir, 'dir') && ~any(strcmp(strsplit(path, pathsep), ch_add_dir))
        addpath(ch_add_dir);
    end

    meta_fields = fieldnames(session_meta);
    if isempty(meta_fields)
        fprintf('  [INFO] smp_append_session_meta: no fields — nothing to append.\n');
        return;
    end

    % Number of 1Hz samples = session duration in whole seconds
    t_start  = dash_t(1);
    t_end    = dash_t(end);
    n_1hz    = max(1, ceil(t_end - t_start));

    fprintf('  Session duration: %.1fs  →  %d samples at 1Hz\n', t_end - t_start, n_1hz);

    % Build channel list
    ch_list = {};
    for k = 1:numel(meta_fields)
        fn  = meta_fields{k};
        sch = session_meta.(fn);

        val = double(sch.value);

        % Compute dec_places: highest d in 0-4 such that val*10^d <= 32767
        dec = 0;
        for d = 4:-1:0
            if abs(val) * 10^d <= 32767
                dec = d;
                break;
            end
        end

        new_ch.name        = sch.name;
        new_ch.short_name  = sch.name(1:min(end, 7));
        new_ch.units       = sch.units;
        new_ch.sample_rate = 1;
        new_ch.value       = repmat(val, n_1hz, 1);   % vector — exact length
        new_ch.dec_places  = dec;
        new_ch.offset      = 0;
        new_ch.mul         = 1;
        new_ch.scale       = 1;
        new_ch.datatype    = 2;   % int16

        ch_list{end+1} = new_ch; %#ok<AGROW>
        fprintf('  + %-20s = %.4f %s  (dec=%d, n=%d)\n', sch.name, val, sch.units, dec, n_1hz);
    end

    % ld_add_channel copies source → output, so use a temp file then replace
    [out_dir, out_base, out_ext] = fileparts(com_file);
    tmp_file = fullfile(out_dir, [out_base '_smeta_tmp' out_ext]);

    ld_add_channel(com_file, tmp_file, ch_list);
    movefile(tmp_file, com_file, 'f');

    fprintf('  Session metadata channels appended to: %s\n', com_file);
end
