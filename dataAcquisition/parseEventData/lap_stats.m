function stats = lap_stats(laps, channels, opts)
% LAP_STATS  Compute per-lap statistics for one or more channels.
%
% Takes the output of lap_slicer() and computes a suite of statistics
% for each requested channel across all laps.
%
% Usage:
%   stats = lap_stats(laps, 'Speed')
%   stats = lap_stats(laps, {'Speed','RPM','Throttle_Pos'})
%   stats = lap_stats(laps, channels, opts)
%
% Options:
%   opts.operations       Cell array of operations applied to EVERY channel
%                         in `channels` (unless overridden per-channel via
%                         opts.per_channel_ops — see below).
%                         Default: {'min','max','mean','median','std','var',
%                                   'range','change','final','initial'}
%
%   opts.per_channel_ops  containers.Map: channel name -> cell array of
%                         operations for THAT channel specifically. If a
%                         channel is a key in this map, its own op list is
%                         used instead of opts.operations. A channel can
%                         have multiple ops (e.g. {'mean non zero','max'})
%                         if it's referenced by multiple plots with
%                         different mathFunction values — all of them are
%                         computed, nothing is dropped.
%                         Channels NOT in this map fall back to
%                         opts.operations (or the default list).
%
%                     Non-zero variants (strip zeros before computing):
%                       'mean non zero'    → field: mean_non_zero
%                       'min non zero'     → field: min_non_zero
%                       'max non zero'     → field: max_non_zero
%                       'median non zero'  → field: median_non_zero
%                       'std non zero'     → field: std_non_zero
%
%                     These match the Excel mathFunction column directly,
%                     e.g. write "mean non zero" in the Excel cell.
%
%   opts.percentiles  Extra percentile values to compute, e.g. [10 90].
%                     Default: [] (none)
%
%   opts.corner_cfg        Struct array from smp_corner_config_load.m
%                         (corner_num / start_dist / end_dist). If empty,
%                         corner-phase stats are skipped entirely.
%   opts.dist_channel_field  Distance channel field name used for corner
%                         boundary matching. Default: 'Odometer'.
%   opts.phase_channels   Struct mapping phase name -> gate channel name.
%                         Default: Braking/Entry/MidCrn/Exit ->
%                         brakingGateVCH/entryGateVCH/midCrnGateVCH/exitGateVCH
%
% Returns:
%   stats   Struct with one sub-struct per channel name.
%
%   stats.Speed.lap_numbers    (1 x N_laps)
%   stats.Speed.lap_times      (1 x N_laps)  [s]
%   stats.Speed.min            (1 x N_laps)   [only if 'min' was in this
%                                              channel's op list]
%   stats.Speed.max            (1 x N_laps)
%   stats.Speed.mean           (1 x N_laps)
%   stats.Speed.median         (1 x N_laps)
%   stats.Speed.std            (1 x N_laps)
%   stats.Speed.var            (1 x N_laps)
%   stats.Speed.range          (1 x N_laps)  max - min
%   stats.Speed.change         (1 x N_laps)  last - first sample
%   stats.Speed.final          (1 x N_laps)  last sample value
%   stats.Speed.initial        (1 x N_laps)  first sample value
%   stats.Speed.mean_non_zero  (1 x N_laps)  mean of non-zero samples
%   stats.Speed.min_non_zero   (1 x N_laps)  min  of non-zero samples
%   stats.Speed.max_non_zero   (1 x N_laps)  max  of non-zero samples
%   stats.Speed.median_non_zero(1 x N_laps)  median of non-zero samples
%   stats.Speed.std_non_zero   (1 x N_laps)  std  of non-zero samples
%   stats.Speed.units          (char)
%   stats.Speed.raw_name       (char)
%   stats.Speed.channel_field  (char)  MATLAB field name used
%
%   NOTE: only fields for operations actually requested for that channel
%   are present — a channel restricted to {'mean non zero'} via
%   per_channel_ops will NOT have .min/.max/.median/etc. fields at all.
%
%   If percentiles are requested, additional fields are added:
%   stats.Speed.p10, stats.Speed.p90, etc.
%
%   If opts.corner_cfg is supplied, additional fields are added, one set
%   per corner_num x phase in phase_channels:
%
%   stats.Corner1_Braking_TimeVCH.time           (1 x N_laps)  [s]
%   stats.Corner1_Braking_TimeVCH.lap_numbers     (1 x N_laps)
%   stats.Corner1_Braking_TimeVCH.lap_times       (1 x N_laps)
%   stats.Corner1_Braking_LapTimeCorrVCH.scalar   corr(corner time, lap time)
%   stats.Corner1_Braking_TimeVarianceVCH.scalar  std(corner time)
%
%   These are computed ONCE per lap_stats call (not per requested channel).

    % ------------------------------------------------------------------
    %  Defaults
    % ------------------------------------------------------------------
    if nargin < 3, opts = struct(); end
    if nargin < 2 || isempty(channels)
        % Default: all channels
        channels = fieldnames(laps(1).channels);
    end
    if ischar(channels), channels = {channels}; end

    default_ops = {'min','max','mean','median','std','var','range','change','final','initial'};
    operations  = get_opt(opts, 'operations',      default_ops);
    percentiles = get_opt(opts, 'percentiles',     []);
    per_ch_ops  = get_opt(opts, 'per_channel_ops', []);   % containers.Map or []

    % ---- Corner-phase config (optional) ----
    corner_cfg     = get_opt(opts, 'corner_cfg',        []);
    dist_ch_field  = get_opt(opts, 'dist_channel_field', 'Odometer');
    phase_channels = get_opt(opts, 'phase_channels', struct( ...
    'Braking', 'braking_Gate_VCH', 'Entry', 'entry_Gate_VCH', ...
    'MidCrn',  'mid_Crn_Gate_VCH',  'Exit',  'exit_Gate_VCH', ...
    'LiftCoast', 'lift_Coast_Gate_VCH', 'OffPedal', 'off_Pedal_Gate_VCH'));

    n_laps = numel(laps);
    stats  = struct();

    % ------------------------------------------------------------------
    %  For each channel
    % ------------------------------------------------------------------
    for ci = 1:numel(channels)
        ch_req = channels{ci};

        % ---- Per-channel op override, if provided ----
        % A channel can require MULTIPLE ops (e.g. referenced by two
        % different plots with different mathFunction values) — per_ch_ops
        % already accumulates all of them into one cell array per channel
        % (see smp_build_required_stats' add_op), so nothing is dropped.
        if ~isempty(per_ch_ops) && isKey(per_ch_ops, ch_req)
            ops_for_this_channel = per_ch_ops(ch_req);
        else
            ops_for_this_channel = operations;
        end

        % Find the field in laps(1).channels (case-insensitive)
        ch_field = find_channel_field(laps(1).channels, ch_req);
        if isempty(ch_field)
            warning('lap_stats: channel "%s" not found — skipping.', ch_req);
            continue;
        end

        % Sanitise to valid struct fieldname for output
        out_field = sanitise_fieldname(ch_req);
        if isempty(out_field), out_field = sanitise_fieldname(ch_field); end

        % Pre-allocate result vectors — ONLY for this channel's own ops
        res = struct();
        res.lap_numbers = zeros(1, n_laps);
        res.lap_times   = zeros(1, n_laps);
        res.lap_types   = cell(1, n_laps);
        for op = ops_for_this_channel(:)'
            res.(sanitise_fieldname(op{1})) = NaN(1, n_laps);
        end
        for p = percentiles(:)'
            res.(sprintf('p%d', p)) = NaN(1, n_laps);
        end

        meta_set = false;

        % ------------------------------------------------------------------
        %  Loop over laps
        % ------------------------------------------------------------------
        for k = 1:n_laps
            res.lap_numbers(k) = laps(k).lap_number;
            res.lap_times(k)   = laps(k).lap_time;
            if isfield(laps(k), 'lap_type')
                res.lap_types{k} = laps(k).lap_type;
            else
                res.lap_types{k} = '';
            end

            ch   = laps(k).channels.(ch_field);
            d    = ch.data;
            d    = d(isfinite(d));   % strip NaN/Inf

            if ~meta_set
                res.units       = ch.units;
                res.raw_name    = ch.raw_name;
                res.channel_field = ch_field;
                meta_set = true;
            end

            if isempty(d)
                continue;  % leave NaN in all stats for this lap
            end

            % Compute this channel's own requested operations
            for op = ops_for_this_channel(:)'
                op_str   = op{1};
                op_field = sanitise_fieldname(op_str);   % e.g. 'mean non zero' → 'mean_non_zero'
                switch lower(strtrim(op_str))
                    case 'min',              res.min(k)              = min(d);
                    case 'max',              res.max(k)              = max(d);
                    case 'mean',             res.mean(k)             = mean(d);
                    case 'median',           res.median(k)           = median(d);
                    case 'std',              res.std(k)              = std(d);
                    case 'var',              res.var(k)              = var(d);
                    case 'range',            res.range(k)            = max(d) - min(d);
                    case 'change',           res.change(k)           = d(end) - d(1);
                    case 'final',            res.final(k)            = d(end);
                    case 'sample_rate',      res.sample_rate(k)      = ch.sample_rate;
                    case 'initial',          res.initial(k)          = d(1);
                    % --- Non-zero variants: strip exact zeros before computing ---
                    case 'mean non zero'
                        dz = d(d ~= 0);
                        if ~isempty(dz), res.mean_non_zero(k) = mean(dz); end
                    case 'min non zero'
                        dz = d(d ~= 0);
                        if ~isempty(dz), res.min_non_zero(k)  = min(dz);  end
                    case 'max non zero'
                        dz = d(d ~= 0);
                        if ~isempty(dz), res.max_non_zero(k)  = max(dz);  end
                    case 'median non zero'
                        dz = d(d ~= 0);
                        if ~isempty(dz), res.median_non_zero(k) = median(dz); end
                    case 'std non zero'
                        dz = d(d ~= 0);
                        if ~isempty(dz), res.std_non_zero(k)  = std(dz);  end
                    otherwise
                        warning('lap_stats: unknown operation "%s" — skipping.', op_str);
                end
            end

            % Percentiles
            for p = percentiles(:)'
                res.(sprintf('p%d', p))(k) = prctile(d, p);
            end
        end

        stats.(out_field) = res;
    end

    % ------------------------------------------------------------------
    %  Corner-phase time + sensitivity (optional, needs corner_cfg)
    %  Runs ONCE per lap_stats call — NOT nested in the per-channel loop.
    % ------------------------------------------------------------------
    if ~isempty(corner_cfg)
        lap_times_all = zeros(1, n_laps);
        for k = 1:n_laps, lap_times_all(k) = laps(k).lap_time; end
        phases = fieldnames(phase_channels);

        for c = 1:numel(corner_cfg)
                    cn = corner_cfg(c).corner_num;
                    if ~iscell(cn), cn = {char(string(cn))}; end   % corner_num may be numeric
        for ph = 1:numel(phases)
                        ph_name    = phases{ph};
                        gate_field = phase_channels.(ph_name);
                        out_field  = sanitise_fieldname(sanitise_fieldname(sprintf('Corner%s_%s_TimeVCH', cn{1}, ph_name)));
                        res = struct('lap_numbers', zeros(1,n_laps), 'lap_times', lap_times_all, ...
        'time', NaN(1,n_laps), 'units','s', ...
        'raw_name', sprintf('Corner%s_%s_TimeVCH', cn{1}, ph_name));
        for k = 1:n_laps
                            res.lap_numbers(k) = laps(k).lap_number;
        if ~isfield(laps(k).channels, gate_field) || ...
                               ~isfield(laps(k).channels, dist_ch_field)
        continue;
        end
                            dist = laps(k).channels.(gate_field).dist;   % same channel's own distance array
                            gate = laps(k).channels.(gate_field).data;
                            dt   = 1 / laps(k).channels.(gate_field).sample_rate;
                            mask = (dist >= corner_cfg(c).start_dist) & (dist < corner_cfg(c).end_dist) & logical(gate);
                            nnz(mask)
                            find(mask)
        if nnz(mask) < 3, continue; end
                            res.time(k) = sum(mask) * dt;
        end
                        stats.(out_field) = res;
        % ---- Sensitivity scalars ----
                        ok = isfinite(res.time) & isfinite(lap_times_all);
                        sres = struct('raw_name', sprintf('Corner%s_%s_TimeVCH_corr', cn{1}, ph_name), ...
        'units','corr', 'scalar', NaN);
                        vres = struct('raw_name', sprintf('Corner%s_%s_TimeVCH_var', cn{1}, ph_name), ...
        'units','s', 'scalar', NaN);
        if nnz(ok) >= 3
                            cc = corrcoef(res.time(ok), lap_times_all(ok));
                            sres.scalar = cc(1,2);
                            vres.scalar = std(res.time(ok));
        end
                        stats.(sanitise_fieldname(sres.raw_name)) = sres;
                        stats.(sanitise_fieldname(vres.raw_name)) = vres;
        end                                          % <-- closes "for ph"
        
            % ---- NEW: Throttle-drop-to-full-throttle window total (denominator) ----
            out_field2 = sanitise_fieldname(sprintf('Corner%s_ThrottleWindowTimeVCH', cn{1}));
            res2 = struct('lap_numbers', zeros(1,n_laps), 'lap_times', lap_times_all, ...
                'time', NaN(1,n_laps), 'units','s', ...
                'raw_name', sprintf('Corner%s_ThrottleWindowTimeVCH', cn{1}));
            for k = 1:n_laps
                res2.lap_numbers(k) = laps(k).lap_number;
                if ~isfield(laps(k).channels, 'full_Throttle_Gate_VCH') || ...
                   ~isfield(laps(k).channels, dist_ch_field)
                    continue;
                end
                dist2 = laps(k).channels.full_Throttle_Gate_VCH.dist;
                gate2 = laps(k).channels.full_Throttle_Gate_VCH.data;
                dt2   = 1 / laps(k).channels.full_Throttle_Gate_VCH.sample_rate;
                mask2 = (dist2 >= corner_cfg(c).start_dist) & (dist2 < corner_cfg(c).end_dist) & ~logical(gate2);
                if nnz(mask2) < 3, continue; end
                res2.time(k) = sum(mask2) * dt2;
            end
            stats.(out_field2) = res2;
        
        end                                          % <-- closes "for c"
    end

    % ------------------------------------------------------------------
    %  Summary
    % ------------------------------------------------------------------
    out_fields = fieldnames(stats);
    fprintf('lap_stats: computed stats for %d channel(s) across %d laps.\n', ...
        numel(out_fields), n_laps);
    for i = 1:numel(out_fields)
        f = out_fields{i};
        if isfield(stats.(f), 'units')
            fprintf('  %s  [%s]\n', stats.(f).raw_name, stats.(f).units);
        end
    end
end


% ======================================================================= %
function field = find_channel_field(channels_struct, name)
    if isfield(channels_struct, name)
        field = name;
        return;
    end
    san = regexprep(name, '[^a-zA-Z0-9_]', '_');
    san = regexprep(san, '_+', '_');
    if isfield(channels_struct, san)
        field = san;
        return;
    end
    all_f = fieldnames(channels_struct);
    for i = 1:numel(all_f)
        if strcmpi(all_f{i}, name) || strcmpi(all_f{i}, san)
            field = all_f{i};
            return;
        end
    end
    field = '';
end


% ======================================================================= %
function name = sanitise_fieldname(raw)
    if isempty(raw), name = ''; return; end
    name = regexprep(raw, '[^a-zA-Z0-9_]', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '_$', '');
    if isempty(name), return; end
    if ~isletter(name(1)), name = ['ch_' name]; end
    name = name(1:min(end,63));
end


% ======================================================================= %
function val = get_opt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        val = opts.(name);
    else
        val = default;
    end
end