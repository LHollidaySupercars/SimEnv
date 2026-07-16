function laps_dist = distance_interp(laps, opts)
% DISTANCE_INTERP  Resample all lap channels onto a common distance axis.
%
% Each channel in the input laps struct has its own time axis (due to
% different logging rates). This function:
%   1. Builds or finds a distance vector for each lap
%   2. Defines a common distance grid (0 → lap_distance, step = resolution)
%   3. Interpolates every channel onto that grid using interp1
%
% Distance source (in priority order):
%   a) A native distance channel if present (e.g. 'Distance', 'Odometer')
%   b) Speed integration: dist = cumtrapz(time, speed_in_m_per_s)
%
% Usage:
%   laps_dist = distance_interp(laps)
%   laps_dist = distance_interp(laps, opts)
%
% Options:
%   opts.distance_channel   Channel name to use as distance source.
%                           (default: auto-detect, see DIST_CANDIDATES below)
%   opts.distance_scale     Scale factor applied to native distance channel
%                           to convert to metres. e.g. if units are km: 1000
%                           (default: 1.0)
%   opts.speed_channel      Channel name for speed (used if integrating).
%                           (default: auto-detect from SPEED_CANDIDATES)
%   opts.speed_to_ms        Scale factor to convert speed channel to m/s.
%                           e.g. if speed is in km/h: 1/3.6
%                           (default: 1/3.6  i.e. assumes km/h)
%   opts.resolution         Distance grid spacing in metres. (default: 1)
%   opts.lap_length         Force a fixed lap length in metres.
%                           If empty, uses max distance reached each lap.
%                           (default: [])
%   opts.common_grid        If true, all laps share the same distance vector
%                           (trimmed to shortest lap). If false, each lap has
%                           its own grid length. (default: true)
%   opts.interp_method      interp1 method. (default: 'linear')
%   opts.verbose            (default: true)
%
% Returns:
%   laps_dist   Copy of the input laps struct array with additional fields
%               added to each lap:
%
%               laps_dist(k).dist_vec               Common distance grid (m)
%               laps_dist(k).lap_distance           Total distance of this lap (m)
%               laps_dist(k).channels.X.dist_data   Channel interpolated onto dist_vec
%
% Note: The original .data and .time fields are preserved alongside .dist_data.

    % ------------------------------------------------------------------
    %  Defaults
    % ------------------------------------------------------------------
    if nargin < 2, opts = struct(); end

    % Native distance channel candidates (tried in order, case-insensitive)
    DIST_CANDIDATES  = {'Distance','Odometer','Dist','Odo','Track_Position'};
    SPEED_CANDIDATES = {'Speed','Vehicle_Speed','GPS_Speed','Wheel_Speed_FL', ...
                        'Wheel_Speed_FR','Wheel_Speed_RL','Wheel_Speed_RR'};

    dist_ch_req   = get_opt(opts, 'distance_channel', '');
    dist_scale    = get_opt(opts, 'distance_scale',   1.0);
    speed_ch_req  = get_opt(opts, 'speed_channel',    '');
    speed_to_ms   = get_opt(opts, 'speed_to_ms',      1/3.6);   % km/h → m/s
    resolution    = get_opt(opts, 'resolution',       1);        % metres
    lap_length    = get_opt(opts, 'lap_length',       []);
    common_grid   = get_opt(opts, 'common_grid',      true);
    interp_method = get_opt(opts, 'interp_method',    'linear');
    verbose       = get_opt(opts, 'verbose',          true);

    n_laps = numel(laps);
    laps_dist = laps;   % deep copy (struct array copies in MATLAB)

    % ------------------------------------------------------------------
    %  Identify distance and speed channels from first lap
    % ------------------------------------------------------------------
    ch_names = fieldnames(laps(1).channels);

    dist_field  = '';
    using_native = false;

    if ~isempty(dist_ch_req)
        dist_field = find_channel_field(laps(1).channels, dist_ch_req, ch_names);
    end
    if isempty(dist_field)
        for i = 1:numel(DIST_CANDIDATES)
            dist_field = find_channel_field(laps(1).channels, DIST_CANDIDATES{i}, ch_names);
            if ~isempty(dist_field), break; end
        end
    end
    if ~isempty(dist_field)
        using_native = true;
        if verbose
            fprintf('distance_interp: using native distance channel "%s" (scale=%.4f)\n', ...
                dist_field, dist_scale);
        end
    end

    speed_field = '';
    if ~using_native || isempty(dist_field)
        if ~isempty(speed_ch_req)
            speed_field = find_channel_field(laps(1).channels, speed_ch_req, ch_names);
        end
        if isempty(speed_field)
            for i = 1:numel(SPEED_CANDIDATES)
                speed_field = find_channel_field(laps(1).channels, SPEED_CANDIDATES{i}, ch_names);
                if ~isempty(speed_field), break; end
            end
        end
        if isempty(speed_field)
            error(['distance_interp: no distance or speed channel found.\n' ...
                   'Set opts.distance_channel or opts.speed_channel explicitly.']);
        end
        if verbose
            fprintf('distance_interp: integrating speed channel "%s" (speed_to_ms=%.5f)\n', ...
                speed_field, speed_to_ms);
        end
    end

    % ------------------------------------------------------------------
    %  Per-lap: build distance vector and interpolate
    % ------------------------------------------------------------------
    lap_distances = zeros(1, n_laps);

    for k = 1:n_laps
        ch_struct = laps(k).channels;

        % Build distance vector for this lap
        if using_native && ~isempty(dist_field)
            d_ch   = ch_struct.(dist_field);
            d_time = d_ch.time;
            d_raw  = d_ch.data * dist_scale;
            % Normalise so it starts at 0
            d_raw  = d_raw - d_raw(1);
        else
            % Integrate speed
            s_ch      = ch_struct.(speed_field);
            s_time    = s_ch.time;
            s_ms      = s_ch.data * speed_to_ms;
            s_ms      = max(s_ms, 0);   % no negative speed
            d_raw     = cumtrapz(s_time, s_ms);
            d_time    = s_time;
        end

        % Remove non-monotonic distance points (GPS glitches, etc.)
        mono_mask = [true; diff(d_raw) > 0];
        d_time    = d_time(mono_mask);
        d_raw     = d_raw(mono_mask);

        lap_dist = d_raw(end);
        if ~isempty(lap_length)
            lap_dist = lap_length;
        end

        lap_distances(k) = lap_dist;
        laps_dist(k).lap_distance = lap_dist;

        % Per-lap distance grid
        dist_vec = (0 : resolution : lap_dist)';
        laps_dist(k).dist_vec = dist_vec;

        % Interpolate every channel onto this distance grid
        for c = 1:numel(ch_names)
            fn    = ch_names{c};
            ch    = ch_struct.(fn);
            t_ch  = ch.time;
            d_ch_val = ch.data;

            % Map channel time → distance using the d_time/d_raw lookup
            if numel(t_ch) < 2
                % Can't interpolate single-sample channels
                laps_dist(k).channels.(fn).dist_data = NaN(size(dist_vec));
                continue;
            end

            % First: interpolate d_raw(t) at t_ch to get distance at each sample
            t_range = [d_time(1), d_time(end)];
            t_ch_clipped = min(max(t_ch, t_range(1)), t_range(2));
            dist_at_sample = interp1(d_time, d_raw, t_ch_clipped, 'linear', 'extrap');

            % Remove non-monotonic distance in channel's own time axis
            mono2 = [true; diff(dist_at_sample) > 0];
            dist_at_sample = dist_at_sample(mono2);
            d_ch_val_m     = d_ch_val(mono2);

            if numel(dist_at_sample) < 2
                laps_dist(k).channels.(fn).dist_data = NaN(size(dist_vec));
                continue;
            end

            % Clip dist_vec to range of dist_at_sample
            d_min = dist_at_sample(1);
            d_max = dist_at_sample(end);
            dist_q = min(max(dist_vec, d_min), d_max);

%             interp_data = interp1(dist_at_sample, d_ch_val_m, dist_q, interp_method);
%             laps_dist(k).channels.(fn).dist_data = interp_data;
% Per-channel interp method override (e.g. 'nearest' for boolean gates)
            if isfield(ch, 'interp_method') && ~isempty(ch.interp_method)
                ch_interp = ch.interp_method;
            else
                ch_interp = interp_method;   % fall back to global setting
            end
            interp_data = interp1(dist_at_sample, d_ch_val_m, dist_q, ch_interp);
            laps_dist(k).channels.(fn).dist_data = interp_data;
        end
    end

    % ------------------------------------------------------------------
    %  Optionally enforce a common distance grid across all laps
    % ------------------------------------------------------------------
    if common_grid
        if isempty(lap_length)
            common_len = min(lap_distances);
        else
            common_len = lap_length;
        end
        common_dist_vec = (0 : resolution : common_len)';
        n_grid = numel(common_dist_vec);

        for k = 1:n_laps
            laps_dist(k).dist_vec = common_dist_vec;
            for c = 1:numel(ch_names)
                fn  = ch_names{c};
                old_dv  = (0 : resolution : lap_distances(k))';
                old_dd  = laps_dist(k).channels.(fn).dist_data;

                if numel(old_dv) ~= numel(old_dd)
                    % Mismatch — just truncate/NaN-pad
                    if numel(old_dd) >= n_grid
                        laps_dist(k).channels.(fn).dist_data = old_dd(1:n_grid);
                    else
                        padded = NaN(n_grid, 1);
                        padded(1:numel(old_dd)) = old_dd;
                        laps_dist(k).channels.(fn).dist_data = padded;
                    end
                else
                    % Re-interpolate onto common grid
                    clipped_old_dv = min(max(common_dist_vec, old_dv(1)), old_dv(end));
%                     new_dd = interp1(old_dv, old_dd, clipped_old_dv, interp_method);
                    ch_interp_2 = interp_method;
                    if isfield(laps_dist(k).channels.(fn), 'interp_method')
                        ch_interp_2 = laps_dist(k).channels.(fn).interp_method;
                    end
                    new_dd = interp1(old_dv, old_dd, clipped_old_dv, ch_interp_2);
                    laps_dist(k).channels.(fn).dist_data = new_dd;
                end
            end
        end

        if verbose
            fprintf('distance_interp: common grid applied. Length=%.0fm, Step=%gm, Points=%d\n', ...
                common_len, resolution, n_grid);
        end
    end

    if verbose
        fprintf('distance_interp: done. Lap distances (m): ');
        fprintf('%.0f  ', lap_distances);
        fprintf('\n\n');
    end
end


% ======================================================================= %
function field = find_channel_field(channels_struct, name, ch_names)
    if nargin < 3, ch_names = fieldnames(channels_struct); end
    if isfield(channels_struct, name), field = name; return; end
    san = regexprep(name, '[^a-zA-Z0-9_]', '_');
    san = regexprep(san, '_+', '_');
    if isfield(channels_struct, san), field = san; return; end
    for i = 1:numel(ch_names)
        if strcmpi(ch_names{i}, name) || strcmpi(ch_names{i}, san)
            field = ch_names{i};
            return;
        end
    end
    field = '';
end


% ======================================================================= %
function val = get_opt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        val = opts.(name);
    else
        val = default;
    end
end
