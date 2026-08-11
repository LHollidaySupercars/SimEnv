
function [needed_channels, channel_ops_map] = smp_build_required_stats(plot_config_files)
% SMP_BUILD_REQUIRED_STATS  Read plottingRequest.xlsx file(s) and determine
%   exactly which channels are needed and which stat operation(s) each one
%   actually requires.
%
%   Channel-bearing columns in plottingRequest.xlsx (per smp_plot_config_load):
%     y_channels     - yAxis1-4 (skipping yAxis2 for timeseries_align, which
%                      holds the align channel instead) — ALWAYS get math_fn
%                      applied via lap_stats.
%     x_axis         - plotted x-axis channel. For scatter-style plots (one
%                      point per lap), this is a PER-LAP STAT, same as y —
%                      must be in channel_ops_map or lap_stats never computes
%                      it and the plot silently falls back to Lap Number.
%                      For timeseries-style plots, x_axis is a raw distance/
%                      time trace — load-only, no stat needed.
%     z_axis         - same treatment as x_axis.
%     align_channel  - explicit alignChannel column, or yAxis2 fallback for
%                      timeseries_align — always load-only, never a stat target.
%
%   mathFunction column: 'none' means no stat needed for that row (raw trace
%   plot) — NOT passed to lap_stats as a literal operation.
%
%   Channel names are normalised (spaces -> underscores, matching lap_stats'
%   own sanitise_fieldname convention) at insertion time, so 'Lap Number'
%   and 'Lap_Number' collapse to one entry instead of being tracked as two
%   separate channels.
%
% OUTPUT
%   needed_channels   - cell array of ALL unique (normalised) channels
%                        referenced by any plot (y + x + z + align) — use
%                        this for channels_to_extract.
%   channel_ops_map   - containers.Map: normalised channel name -> cell
%                        array of required ops. Use this for lap_stats.

    if ischar(plot_config_files), plot_config_files = {plot_config_files}; end

    % Plot types where x_axis/z_axis represent a per-lap AGGREGATE value
    % (one point per lap) and therefore need a computed stat, as opposed to
    % timeseries types where x_axis is a raw distance/time trace.
    %
    % Confirmed from actual plottingRequest.xlsx files (AR/PR/SR, E08_PER):
    %   scatter, scatter_trace, trace_scatter_all -> need x/z-axis stat
    %   timeseries, timeseries_align               -> raw trace, no stat needed
    % Still unconfirmed: sessionlapwise, ranked_box, lapwise_box, phase_profile
    % — currently treated as NOT needing axis stats. If any of these plots
    % come out wrong (silently falling back like the tyre-temp plot did),
    % add that type name to this list.
    SCATTER_LIKE_TYPES = {'scatter', 'scatter_trace', 'trace_scatter_all'};

    channel_ops_map = containers.Map('KeyType', 'char', 'ValueType', 'any');
    all_channels    = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    for f = 1:numel(plot_config_files)
        plots = smp_plot_config_load(plot_config_files{f});

        for r = 1:numel(plots)
            % ---- mathFunction: 'none' / empty means no stat needed ----
            math_fn = plots(r).math_fn;
            if isempty(math_fn) || strcmpi(math_fn, 'none')
                math_fn = '';
            end

            % ---- y_channels: ALWAYS get math_fn applied (if not 'none') ----
            ych = plots(r).y_channels;
            if ischar(ych), ych = {ych}; end
            ych = ych(~cellfun(@isempty, ych));

            for c = 1:numel(ych)
                ch = strtrim(ych{c});
                if ~looks_like_channel_name(ch), continue; end
                ch = normalise_channel_name(ch);
                all_channels(ch) = true;
                if ~isempty(math_fn)
                    channel_ops_map = add_op(channel_ops_map, ch, math_fn);
                end
            end

            % ---- x_axis / z_axis: stat needed ONLY for scatter-like types ----
            needs_axis_stat = any(strcmpi(plots(r).type, SCATTER_LIKE_TYPES));
            axis_channels = {plots(r).x_axis, plots(r).z_axis};
            for c = 1:numel(axis_channels)
                ch = strtrim(axis_channels{c});
                if ~looks_like_channel_name(ch), continue; end
                ch = normalise_channel_name(ch);
                all_channels(ch) = true;
                if needs_axis_stat && ~isempty(math_fn)
                    channel_ops_map = add_op(channel_ops_map, ch, math_fn);
                end
            end

            % ---- align_channel: always load-only, never a stat target ----
            ach = strtrim(plots(r).align_channel);
            if looks_like_channel_name(ach)
                ach = normalise_channel_name(ach);
                all_channels(ach) = true;
            end
        end
    end

    needed_channels = keys(all_channels);

    fprintf('smp_build_required_stats: %d unique channel(s) needed (load) across %d plot file(s).\n', ...
        numel(needed_channels), numel(plot_config_files));
    fprintf('  Of those, %d channel(s) have lap_stats ops (from y-axis and/or scatter-type x/z-axis).\n', ...
        channel_ops_map.Count);
    total_ops = 0;
    ks = keys(channel_ops_map);
    for i = 1:numel(ks)
        total_ops = total_ops + numel(channel_ops_map(ks{i}));
    end
    fprintf('  Total (channel, op) pairs required: %d  (vs. %d if computing all default ops for all %d channels)\n', ...
        total_ops, numel(needed_channels) * 10, numel(needed_channels));
end


% ======================================================================= %
function ok = looks_like_channel_name(s)
% Reject cell-array/vector artefacts accidentally picked up from the wrong
% Excel column (e.g. xLim ranges like '[2090, 2150]', or differentiator
% category-label arrays like "{'Braking','Entry','Mid-Corner','Exit'}").
    ok = ~isempty(s) && ischar(s) && ...
         ~contains(s, {'{', '[', newline, '\n'}) && ...
         ~contains(s, ',') && ...
         ~strcmpi(s, 'none') && ~strcmpi(s, 'nan');
end


% ======================================================================= %
function name = normalise_channel_name(raw)
% Match lap_stats' own sanitise_fieldname convention, so channel_ops_map
% keys and all_channels entries are consistent — collapses 'Lap Number' /
% 'Lap_Number' style duplicates into a single entry.
    name = regexprep(strtrim(raw), '[^a-zA-Z0-9_]', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '_$', '');
end


% ======================================================================= %
function map = add_op(map, ch, math_fn)
    if isKey(map, ch)
        existing = map(ch);
        if ~any(strcmpi(existing, math_fn))
            existing{end+1} = math_fn; %#ok<AGROW>
        end
        map(ch) = existing;
    else
        map(ch) = {math_fn};
    end
end


