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
%   opts.operations   Cell array of operations to compute.
%                     Default: {'min','max','mean','median','std','var',
%                               'range','change','final','initial'}
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
% Returns:
%   stats   Struct with one sub-struct per channel name.
%
%   stats.Speed.lap_numbers    (1 x N_laps)
%   stats.Speed.lap_times      (1 x N_laps)  [s]
%   stats.Speed.min            (1 x N_laps)
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
%   If percentiles are requested, additional fields are added:
%   stats.Speed.p10, stats.Speed.p90, etc.

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
    operations  = get_opt(opts, 'operations',  default_ops);
    percentiles = get_opt(opts, 'percentiles', []);

    n_laps = numel(laps);
    stats  = struct();

    % ------------------------------------------------------------------
    %  For each channel
    % ------------------------------------------------------------------
    for ci = 1:numel(channels)
        ch_req = channels{ci};

        % Find the field in laps(1).channels (case-insensitive)
        ch_field = find_channel_field(laps(1).channels, ch_req);
        if isempty(ch_field)
            warning('lap_stats: channel "%s" not found — skipping.', ch_req);
            continue;
        end

        % Sanitise to valid struct fieldname for output
        out_field = sanitise_fieldname(ch_req);
        if isempty(out_field), out_field = sanitise_fieldname(ch_field); end

        % Pre-allocate result vectors
        res = struct();
        res.lap_numbers = zeros(1, n_laps);
        res.lap_times   = zeros(1, n_laps);
        for op = operations(:)'
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

            % Compute requested operations
            for op = operations(:)'
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
    %  Summary
    % ------------------------------------------------------------------
    out_fields = fieldnames(stats);
    fprintf('lap_stats: computed stats for %d channel(s) across %d laps.\n', ...
        numel(out_fields), n_laps);
    for i = 1:numel(out_fields)
        f = out_fields{i};
        fprintf('  %s  [%s]\n', stats.(f).raw_name, stats.(f).units);
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
