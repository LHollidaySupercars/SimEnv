% function figs = smp_plot_from_config(SMP, plots, cfg, driver_map, opts)
% % SMP_PLOT_FROM_CONFIG  Generate all plots defined in a plot config struct.
% %
% % Supports two data modes automatically:
% %
% %   Stream mode  — SMP struct came from smp_filter_cache().
% %                  node.stats{r} and node.traces{r} are pre-compiled.
% %
% %   Bulk mode    — SMP struct came from smp_filter() / smp_load_teams.
% %                  node.channels{r} contains raw channel data.
% %
% % New plot types added:
% %   sessionlapwise  — per-car line, x = continuous session lap
% %
% % New post-render features (driven by smp_plot_config_load fields):
% %   x_lim / y_lim           — axis limits from Excel '[lo, hi]'
% %   highlight_outliers       — annotate outlier laps (manufacturer mode only)
% %   outlier_method           — 'mad' or 'iqr'
% %   outlier_threshold        — scalar multiplier
% 
%     % ------------------------------------------------------------------
%     %  Defaults
%     % ------------------------------------------------------------------
%     if nargin < 4, driver_map = []; end
%     if nargin < 5 || isempty(opts), opts = struct(); end
% 
%     min_lt     = get_opt(opts, 'min_lap_time',  85);
%     max_lt     = get_opt(opts, 'max_lap_time',  115);
%     n_laps_avg = get_opt(opts, 'n_laps_avg',    3);
%     verbose    = get_opt(opts, 'verbose',        true);
%     save_path  = get_opt(opts, 'save_path',      '');
%     dist_ch    = get_opt(opts, 'dist_channel',   'Odometer');
%     dist_npts  = get_opt(opts, 'dist_n_points',  1000);
% 
%     SHAPES = {'o','s','^','d'};
% 
%     if isfield(cfg, 'colours'), colour_cfg = cfg.colours;
%     else,                       colour_cfg = cfg; end
% 
%     if verbose, fprintf('\n=== smp_plot_from_config ===\n'); end
% 
%     % ------------------------------------------------------------------
%     %  Collect channel names needed across all plots
%     % ------------------------------------------------------------------
%     all_y = {};
%     all_x = {};
%     for p = 1:numel(plots)
%         all_y = [all_y, plots(p).y_channels]; %#ok
%         xa = plots(p).x_axis;
%         if ~is_keyword(xa), all_x{end+1} = xa; end %#ok
%     end
%     stat_channels = unique([all_y, all_x]);
% 
%     % ------------------------------------------------------------------
%     %  Build run_list
%     % ------------------------------------------------------------------
%     run_list = [];
%     team_keys = fieldnames(SMP);
% 
%     for t = 1:numel(team_keys)
%         tk   = team_keys{t};
%         node = SMP.(tk);
%         n_runs = height(node.meta);
% 
%         for r = 1:n_runs
% 
%             has_stats    = isfield(node, 'stats')    && numel(node.stats)    >= r && ~isempty(node.stats{r});
%             has_channels = isfield(node, 'channels') && numel(node.channels) >= r && ~isempty(node.channels{r});
% 
%             if has_stats
%                 entry = build_entry_stream(node, r, tk, driver_map);
%                 if isempty(entry), continue; end
%                 if verbose
%                     fprintf('  [stream] %-6s | %-22s | %-12s | %-10s | %d laps\n', ...
%                         entry.car, entry.driver, entry.manufacturer, entry.session, entry.n_laps);
%                 end
% 
%             elseif has_channels
%                 entry = build_entry_bulk(node, r, tk, driver_map, ...
%                             stat_channels, min_lt, max_lt, verbose);
%                 if isempty(entry), continue; end
%                 if verbose
%                     fprintf('  [bulk]   %-6s | %-22s | %-12s | %-10s | %d laps\n', ...
%                         entry.car, entry.driver, entry.manufacturer, entry.session, entry.n_laps);
%                 end
% 
%             else
%                 if verbose
%                     fprintf('  [SKIP] %s run %d — no stats or channels available.\n', tk, r);
%                 end
%                 continue;
%             end
% 
%             if isempty(run_list), run_list = entry;
%             else,                 run_list(end+1) = entry; end %#ok
%         end
%     end
% 
%     if isempty(run_list)
%         warning('smp_plot_from_config: no valid runs found.');
%         figs = {};
%         return;
%     end
%     fprintf('\n%d runs ready for plotting.\n\n', numel(run_list));
% 
%     % ------------------------------------------------------------------
%     %  Pre-build figures with subplot layouts
%     % ------------------------------------------------------------------
%     fig_handles = containers.Map('KeyType','int32','ValueType','any');
%     fig_axes    = containers.Map('KeyType','int32','ValueType','any');
%     fig_layouts = containers.Map('KeyType','int32','ValueType','any');
% 
%     fw = get_opt(opts, 'fig_width',  1200);
%     fh = get_opt(opts, 'fig_height', 650);
% 
%     for p = 1:numel(plots)
%         pd = plots(p);
%         if ~isfield(pd,'fig_num') || isnan(pd.fig_num), continue; end
%         fn = int32(pd.fig_num);
%         if ~isKey(fig_handles, fn)
%             lay = pd.fig_layout;
%             if isempty(lay),    lay = [1 1]; end
%             if numel(lay) == 1, lay = [lay(1) 1]; end
%             lay = lay(1:2);
%             fig_layouts(fn) = lay;
%             f = figure('Visible','off','Color','white','Position',[100 100 fw fh]);
%             fig_handles(fn) = f;
%             ax_all = gobjects(lay(1), lay(2));
%             for ri = 1:lay(1)
%                 for ci = 1:lay(2)
%                     ax_all(ri,ci) = subplot(lay(1), lay(2), (ri-1)*lay(2)+ci, 'Parent', f);
%                 end
%             end
%             fig_axes(fn) = ax_all;
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  Generate each plot
%     % ------------------------------------------------------------------
%     figs = cell(numel(plots), 1);
% 
%     for p = 1:numel(plots)
%         pd = plots(p);
%         if verbose
%             fprintf('--- Plot %d: "%s"  [%s / %s / colour=%s]\n', ...
%                 p, pd.name, pd.type, pd.math_fn, pd.colour_mode);
%         end
% 
%         try
%             if isfield(pd, 'plot_filter') && ~isempty(pd.plot_filter)
%                 filter_groups = smp_parse_plot_filter(pd.plot_filter);
%                 plot_run_list = smp_apply_plot_filter(run_list, filter_groups);
%             else
%                 plot_run_list = run_list;
%             end
% 
%             if isempty(plot_run_list)
%                 warning('smp_plot_from_config: plot "%s" — no runs after filter.', pd.name);
%                 continue;
%             end
% 
%             % Resolve axes handle
%             ax_in = [];
%             use_subplot = isfield(pd,'fig_num') && ~isnan(pd.fig_num) && ...
%                           isfield(pd,'fig_pos')  && ~isempty(pd.fig_pos);
%             fprintf('  [subplot] fig_num=%s  fig_pos=%s  use_subplot=%d\n', ...
%                 num2str(pd.fig_num), mat2str(pd.fig_pos), use_subplot);
%             if use_subplot
%                 fn  = int32(pd.fig_num);
%                 pos = pd.fig_pos;
%                 if isKey(fig_axes, fn)
%                     ax_grid = fig_axes(fn);
%                     lay     = fig_layouts(fn);
%                     ri = min(round(pos(1)), lay(1));
%                     ci = min(round(pos(2)), lay(2));
%                     ax_in = ax_grid(ri, ci);
%                 end
%             end
% 
%             switch pd.type
%                 case 'scatter'
%                     figs{p} = make_scatter(plot_run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in);
%                 case 'line'
%                     figs{p} = make_line(plot_run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in);
%                 case 'boxplot'
%                     figs{p} = make_boxplot(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
%                 case 'violin'
%                     figs{p} = make_violin(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
%                 case 'histogram'
%                     figs{p} = make_histogram(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
%                 case 'timeseries'
%                     figs{p} = make_timeseries(plot_run_list, pd, colour_cfg, driver_map, opts, ...
%                                               dist_ch, dist_npts, n_laps_avg, ax_in);
%                 case 'ranked_box'
%                     figs{p} = make_ranked_box(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
%                 case 'lapwise_box'
%                     figs{p} = make_lapwise_box(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
%                 case 'sessionlapwise'
%                     figs{p} = make_session_lap_wise(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
%                 case 'timeseries_align'
%                     figs{p} = make_timeseries_align(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
%                 case 'psd'
% %                     figs{p} = make_psd(plot_run_list, pd, colour_cfg, driver_map, opts);
%                     [fig{p}, psd_stats] = make_psd(run_list, pd, colour_cfg, driver_map, opts, ax_in)
%                 case 'psd_scatter'
%                     figs{p} = make_psd_scatter(plot_run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in);
%                 case 'big_scatter'
%                     figs{p} = make_big_scatter(plot_run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in);
%                 otherwise
%                     warning('smp_plot_from_config: plot type "%s" not supported.', pd.type);
%             end
% 
%             % For subplot figures, figs{p} = parent figure
%             if use_subplot && isKey(fig_handles, int32(pd.fig_num))
%                 figs{p} = fig_handles(int32(pd.fig_num));
%             end
% 
%         catch ME
%             fprintf('  [ERROR] plot "%s": %s\n%s\n', ...
%                 pd.name, ME.message, ME.getReport('basic'));
%         end
% 
%         % ---- Post-processing: axis limits + outlier highlighting ----
%         if ~isempty(figs{p})
%             if ~strcmpi(pd.type, 'timeseries_align')
%                 apply_axis_limits(figs{p}, pd);
%             end
%             if isfield(pd,'highlight_outliers') && pd.highlight_outliers && ...
%                     strcmpi(pd.colour_mode, 'manufacturer') && ...
%                     ismember(pd.type, {'scatter','line','sessionlapwise'})
%                 draw_outlier_highlights(figs{p}, pd, plot_run_list, colour_cfg, driver_map, ax_in);
%             end
%         end
% 
%         if ~isempty(save_path) && ~isempty(figs{p})
%             if ~use_subplot
%                 safe = regexprep(pd.name, '[^a-zA-Z0-9_\- ]', '');
%                 safe = strrep(strtrim(safe), ' ', '_');
%                 exportgraphics(figs{p}, fullfile(save_path, [safe '.png']), 'Resolution', 150);
%             end
%         end
%     end
%     if ~isempty(figs{p})
%         apply_axis_limits(figs{p}, pd);
%     end
%     % Save subplot figures
%     if ~isempty(save_path)
%         fn_keys = keys(fig_handles);
%         for k = 1:numel(fn_keys)
%             f = fig_handles(fn_keys{k});
%             exportgraphics(f, fullfile(save_path, sprintf('figure_%d.png', fn_keys{k})), ...
%                 'Resolution', 150);
%         end
%     end
% end
% 
% 
% % ======================================================================= %
% %  ENTRY BUILDERS
% % ======================================================================= %
% function entry = build_entry_stream(node, r, tk, driver_map)
%     entry = [];
%     stats_s  = node.stats{r};
%     traces_s = [];
%     if isfield(node, 'traces') && numel(node.traces) >= r
%         traces_s = node.traces{r};
%     end
%     if isempty(stats_s), return; end
% 
%     entry.driver       = strtrim(char(string(node.meta.Driver(r))));
%     entry.team         = tk;
%     entry.manufacturer = strtrim(char(string(node.meta.Manufacturer(r))));
%     entry.session      = strtrim(char(string(node.meta.Session(r))));
%     entry.car          = resolve_car_number(entry.driver, driver_map, ...
%                              strtrim(char(string(node.meta.CarNumber(r)))));
%     entry.stats        = stats_s;
%     entry.traces       = traces_s;
%     entry.mode         = 'stream';
% 
%     fields = fieldnames(stats_s);
%     if ~isempty(fields) && isfield(stats_s.(fields{1}), 'lap_numbers')
%         entry.n_laps = numel(stats_s.(fields{1}).lap_numbers);
%     else
%         entry.n_laps = 0;
%     end
% 
%     entry.best_lap_time = Inf;
%     if ~isempty(traces_s) && isfield(traces_s, 'lap_times') && ~isempty(traces_s.lap_times)
%         entry.best_lap_time = min(traces_s.lap_times);
%     elseif ~isempty(fields) && isfield(stats_s.(fields{1}), 'lap_times')
%         lt = stats_s.(fields{1}).lap_times;
%         lt = lt(isfinite(lt));
%         if ~isempty(lt), entry.best_lap_time = min(lt); end
%     end
%     entry.laps = [];
% end
% 
% 
% function entry = build_entry_bulk(node, r, tk, driver_map, ...
%                                    stat_channels, min_lt, max_lt, verbose)
%     entry = [];
%     ch_struct = node.channels{r};
%     if isempty(ch_struct), return; end
% 
%     lap_opts.min_lap_time = min_lt;
%     lap_opts.max_lap_time = max_lt;
%     lap_opts.verbose      = false;
% 
%     try
%         laps = lap_slicer(ch_struct, lap_opts);
%     catch ME
%         if verbose, fprintf('  [WARN] %s r%d lap_slicer: %s\n', tk, r, ME.message); end
%         return;
%     end
%     if isempty(laps), return; end
% 
%     nz_ops = {'mean non zero','min non zero','max non zero', ...
%               'median non zero','std non zero'};
%     try
%         stats = lap_stats(laps, stat_channels, ...
%             struct('operations', {[{'max','min','mean','median','var'}, nz_ops]}));
%     catch ME
%         if verbose, fprintf('  [WARN] %s r%d lap_stats: %s\n', tk, r, ME.message); end
%         return;
%     end
% 
%     entry.driver       = strtrim(char(string(node.meta.Driver{r})));
%     entry.team         = tk;
%     entry.manufacturer = strtrim(char(string(node.meta.Manufacturer{r})));
%     entry.session      = strtrim(char(string(node.meta.Session{r})));
%     entry.car          = resolve_car_number(entry.driver, driver_map, ...
%                              strtrim(char(string(node.meta.CarNumber{r}))));
%     entry.stats        = stats;
%     entry.traces       = [];
%     entry.laps         = laps;
%     entry.n_laps       = numel(laps);
%     entry.best_lap_time = min([laps.lap_time]);
%     entry.mode         = 'bulk';
% end
% 
% 
% % ======================================================================= %
% %  COLOUR HELPER
% % ======================================================================= %
% function col = resolve_colour(entry, colour_mode, colour_cfg, driver_map)
%     switch lower(colour_mode)
%         case {'driver', 'number'}
%             if ~isempty(driver_map) && isstruct(driver_map)
%                 col = local_driver_colour(driver_map, entry.driver);
%             else
%                 col = get_colour(colour_cfg, entry.driver, 'driver');
%             end
%         case 'team'
%             col = get_colour(colour_cfg, entry.team, 'manufacturer');
%         otherwise
%             col = get_colour(colour_cfg, entry.manufacturer, 'manufacturer');
%     end
% end
% 
% 
% % ======================================================================= %
% %  FIGURE FACTORY
% % ======================================================================= %
% function [fig, ax_left, ax_right] = new_fig(pd, opts, ax_in)
%     fw = get_opt(opts, 'fig_width',  1200);
%     fh = get_opt(opts, 'fig_height', 650);
%     fs = get_opt(opts, 'font_size',  11);
% 
%     if nargin >= 3 && ~isempty(ax_in) && isgraphics(ax_in)
%         ax_left = ax_in;
%         fig     = ax_left.Parent;
%         while ~isa(fig, 'matlab.ui.Figure'), fig = fig.Parent; end
%     else
%         fig = figure('Visible','off','Color','white','Position',[100 100 fw fh]);
%         ax_left = axes(fig);
%     end
% 
%     ax_right = [];
%     hold(ax_left,'on'); box(ax_left,'on'); grid(ax_left,'on');
%     set(ax_left,'FontSize',fs,'FontName','Arial', ...
%            'GridAlpha',0.25,'GridLineStyle','--','GridColor',[0.7 0.7 0.7]);
%     ax_left.Color  = [0.97 0.97 0.97];
%     fig.Color = 'white';
%     ax_left.XColor = [0.2 0.2 0.2];
%     ax_left.YColor = [0.2 0.2 0.2];
% 
%     if isfield(pd,'use_secondary') && pd.use_secondary && numel(pd.y_channels) >= 2
%         yyaxis(ax_left, 'right');
%         ax_right = ax_left;
%         ax_left.YAxis(2).Color = [0.2 0.2 0.2];
%         yyaxis(ax_left, 'left');
%     end
% 
%     title(ax_left, pd.name, 'FontSize', fs+1, 'FontWeight', 'bold', 'Interpreter', 'none');
% end
% 
% function apply_legend(ax, handles, labels, opts)
%     valid = isgraphics(handles);
%     if ~any(valid), return; end
%     fs = get_opt(opts, 'font_size', 11);
%     legend(ax, handles(valid), labels(valid), ...
%         'Location','best','FontSize',fs-1,'Box','off','Interpreter','none');
% end
% 
% 
% % ======================================================================= %
% %  SCATTER
% % ======================================================================= %
% function fig = make_scatter(run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in)
%     if nargin < 7, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs = get_opt(opts, 'font_size', 11);
%     use_secondary = isfield(pd,'use_secondary') && pd.use_secondary && numel(pd.y_channels) >= 2;
%     use_shapes    = strcmpi(pd.differentiator, 'shapes');
%     is_falling    = contains(lower(pd.name),'falling') || contains(lower(pd.x_axis),'falling');
% 
%     leg_h = []; leg_l = {}; leg_seen = {};
%     x_lbl = 'Lap Number';
% 
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
% 
%         for yi = 1:numel(pd.y_channels)
%             y_ch    = pd.y_channels{yi};
%             y_field = sanitise_fn(y_ch);
%             if ~isfield(entry.stats, y_field), continue; end
% 
%             if use_secondary && yi == 2
%                 yyaxis(ax, 'right');
%                 ylabel(ax, pd.y_channels{yi}, 'FontSize', fs, 'Interpreter','none');
%             elseif use_secondary && yi == 1
%                 yyaxis(ax, 'left');
%                 ylabel(ax, pd.y_channels{1}, 'FontSize', fs, 'Interpreter','none');
%             end
% 
%             y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
%             lap_nums = entry.stats.(y_field).lap_numbers;
%             valid    = isfinite(y_vals);
%             y_vals   = y_vals(valid);  lap_nums = lap_nums(valid);
%             if isempty(y_vals), continue; end
% 
%             if is_falling
%                 [y_vals, ~] = sort(y_vals, 'descend');
%                 x_vals = 1:numel(y_vals);  x_lbl = 'Rank';
%             elseif is_keyword_lap(pd.x_axis)
%                 x_vals = lap_nums;  x_lbl = 'Lap Number';
%             else
%                 x_field = sanitise_fn(pd.x_axis);
%                 if isfield(entry.stats, x_field)
%                     xv = local_apply_math(entry.stats.(x_field), pd.math_fn);
%                     x_vals = xv(valid);  x_lbl = pd.x_axis;
%                 else
%                     x_vals = lap_nums;  x_lbl = 'Lap Number';
%                 end
%             end
% 
%             marker = 'o';
%             if use_shapes && yi <= numel(SHAPES), marker = SHAPES{yi}; end
% 
%             h = scatter(ax, x_vals, y_vals, 40, col, marker, 'filled', ...
%                 'MarkerEdgeColor', col*0.7, 'MarkerFaceAlpha', 0.8);
% 
%             lbl = build_label(entry, pd, yi, driver_map);
%             if ~any(strcmp(leg_seen, lbl))
%                 leg_h(end+1) = h; leg_l{end+1} = lbl; leg_seen{end+1} = lbl; %#ok
%             end
%         end
%     end
% 
%     if use_secondary, yyaxis(ax, 'left'); end
%     xlabel(ax, x_lbl, 'FontSize', fs, 'Interpreter','none');
%     if ~use_secondary
%         ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
%     end
%     apply_legend(ax, leg_h, leg_l, opts);
%     if use_shapes && numel(pd.y_channels) > 1
%         add_shape_key(fig, pd.y_channels, SHAPES, fs);
%     end
%     apply_axis_limits(ax, pd);   % <-- ADD THIS
% end
% 
% 
% % ======================================================================= %
% %  RANKED BOX
% % ======================================================================= %
% function fig = make_ranked_box(run_list, pd, colour_cfg, driver_map, opts, ax_in) %#ok<INUSL>
%     if nargin < 6, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs  = get_opt(opts, 'font_size', 11);
%     bw  = 0.06;  off = 0.10;
% 
%     MFR_LIST   = {'Ford',      'Toyota',    'Chevrolet'};
%     MFR_OFFSET = [-off,         0,           +off      ];
%     MFR_COLOUR = {[0.0 0.3 0.7],[0.8 0.1 0.1],[0.9 0.7 0.0]};
% 
%     y_ch    = pd.y_channels{1};
%     y_field = sanitise_fn(y_ch);
% 
%     spd_min = -Inf;  spd_max = Inf;
%     season_file = get_opt(opts, 'season_file', 'C:\SimEnv\trackDB\seasonOverview.xlsx');
%     venue = get_opt(opts, 'venue', '');
%     if ~isempty(venue)
%         try
%             T = readtable(season_file, 'Sheet', '2026');
%             track_col = T.Track;
%             if iscell(track_col)
%                 row = find(strcmpi(strtrim(track_col), strtrim(venue)), 1);
%             else
%                 row = find(strcmpi(strtrim(string(track_col)), strtrim(venue)), 1);
%             end
%             if ~isempty(row)
%                 if ismember('TopSpeedMin', T.Properties.VariableNames), spd_min = T.TopSpeedMin(row); end
%                 if ismember('TopSpeedMax', T.Properties.VariableNames), spd_max = T.TopSpeedMax(row); end
%                 fprintf('  [ranked_box] Speed bounds: %.1f - %.1f km/h\n', spd_min, spd_max);
%             else
%                 warning('make_ranked_box: venue "%s" not found in seasonOverview.', venue);
%             end
%         catch ME
%             warning('make_ranked_box: could not load seasonOverview: %s', ME.message);
%         end
%     end
% 
% driver_mfr = {}; driver_vals = {}; driver_car = {};
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         if ~isfield(entry.stats, y_field), continue; end
%         vals = local_apply_math(entry.stats.(y_field), pd.math_fn);
% %         vals = vals(isfinite(vals) & vals >= spd_min & vals <= spd_max);
% vals = vals(isfinite(vals));
%         is_speed_ch = any(contains(lower(y_ch), {'speed','gps','velocity'}));
%         if is_speed_ch
%             vals = vals(vals >= spd_min & vals <= spd_max);
%         end
%         if isempty(vals), continue; end
%         driver_vals{end+1} = sort(vals, 'descend'); %#ok
%         driver_mfr{end+1}  = entry.manufacturer;    %#ok
%         driver_car{end+1}  = entry.car;             %#ok
%     end
%     if isempty(driver_vals), warning('make_ranked_box: no valid data.'); return; end
% 
%     max_rank = max(cellfun(@numel, driver_vals));
%     leg_h = []; leg_l = {}; leg_seen = {};
% 
%     for rank = 1:max_rank
%         for mi = 1:numel(MFR_LIST)
%             mfr = MFR_LIST{mi};  col = MFR_COLOUR{mi};  x0 = rank + MFR_OFFSET(mi);
%             mfr_vals = [];
%             for d = 1:numel(driver_vals)
%                 if strcmpi(driver_mfr{d}, mfr) && rank <= numel(driver_vals{d})
%                     mfr_vals(end+1) = driver_vals{d}(rank); %#ok
%                 end
%             end
%             if numel(mfr_vals) <= 1, continue; end
%             iq = prctile(mfr_vals,[25 75]);  med_ = median(mfr_vals);
%             mfr_vals = mfr_vals(mfr_vals >= med_ - 3*(iq(2)-iq(1)) & ...
%                                 mfr_vals <= med_ + 3*(iq(2)-iq(1)));
%             if numel(mfr_vals) <= 1, continue; end
% %             q   = prctile(mfr_vals,[25 50 75]);
% %             iqr = q(3)-q(1);
% %             w_lo = max(mfr_vals(mfr_vals >= q(1)-1.5*iqr));
% %             w_hi = min(mfr_vals(mfr_vals <= q(3)+1.5*iqr));
% %             otl  = mfr_vals(mfr_vals < q(1)-1.5*iqr | mfr_vals > q(3)+1.5*iqr);
%             q    = prctile(mfr_vals,[25 50 75]);
%             iqr  = q(3)-q(1);
%             w_lo = max(mfr_vals(mfr_vals >= q(1)-1.5*iqr));
%             w_hi = min(mfr_vals(mfr_vals <= q(3)+1.5*iqr));
%             % Outlier detection — respects pd.outlier_method and threshold
%             if isfield(pd,'highlight_outliers') && pd.highlight_outliers
%                 thr = pd.outlier_threshold;
%                 switch pd.outlier_method
%                     case 'iqr'
%                         otl = mfr_vals(mfr_vals < q(1)-thr*iqr | mfr_vals > q(3)+thr*iqr);
%                     otherwise % mad
%                         med_v = q(2);
%                         mad_v = median(abs(mfr_vals - med_v));
%                         otl   = mfr_vals(mfr_vals < med_v-thr*mad_v | mfr_vals > med_v+thr*mad_v);
%                 end
%             else
%                 otl = mfr_vals(mfr_vals < q(1)-1.5*iqr | mfr_vals > q(3)+1.5*iqr);
%             end
%             xb = [x0-bw,x0+bw,x0+bw,x0-bw,x0-bw];
%             yb = [q(1),q(1),q(3),q(3),q(1)];
%             fill(ax,xb,yb,col,'FaceAlpha',0.4,'EdgeColor',col,'LineWidth',1.2);
%             plot(ax,[x0-bw,x0+bw],[q(2),q(2)],'-','Color',col,'LineWidth',2);
%             plot(ax,[x0,x0],[q(1),w_lo],'-','Color',col,'LineWidth',1);
%             plot(ax,[x0,x0],[q(3),w_hi],'-','Color',col,'LineWidth',1);
%             plot(ax,[x0-bw*0.5,x0+bw*0.5],[w_lo,w_lo],'-','Color',col,'LineWidth',1);
%             plot(ax,[x0-bw*0.5,x0+bw*0.5],[w_hi,w_hi],'-','Color',col,'LineWidth',1);
%             if ~isempty(otl)
%                 scatter(ax, repmat(x0,size(otl)), otl, 20, col, 'o', ...
%                     'MarkerEdgeColor', col, 'MarkerFaceAlpha', 0);
%                 % Label which car is the outlier
%                 for oi = 1:numel(otl)
%                     % Find which car produced this value at this rank
%                     for d = 1:numel(driver_vals)
%                         if strcmpi(driver_mfr{d}, mfr) && rank <= numel(driver_vals{d}) ...
%                                 && driver_vals{d}(rank) == otl(oi)
%                             text(ax, x0 + bw*1.2, otl(oi), ...
%                                 sprintf('#%s', driver_car{d}), ...
%                                 'FontSize', 8, 'Color', col*0.75, ...
%                                 'VerticalAlignment', 'middle', ...
%                                 'HorizontalAlignment', 'left', ...
%                                 'Interpreter', 'none');
%                             break;
%                         end
%                     end
%                 end
%             end
%             if ~any(strcmp(leg_seen, mfr))
%                 h = fill(ax,NaN,NaN,col,'FaceAlpha',0.4,'EdgeColor',col);
%                 leg_h(end+1)=h; leg_l{end+1}=mfr; leg_seen{end+1}=mfr; %#ok
%             end
%         end
%     end
%     xlabel(ax,'Rank','FontSize',fs,'Interpreter','none');
%     ylabel(ax,y_ch,'FontSize',fs,'Interpreter','none');
%     ax.XTick = 1:max_rank;
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% 
% 
% % ======================================================================= %
% %  LAPWISE BOX
% % ======================================================================= %
% function fig = make_lapwise_box(run_list, pd, colour_cfg, driver_map, opts, ax_in) %#ok<INUSL>
%     if nargin < 6, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs  = get_opt(opts, 'font_size', 11);
%     bw  = 0.06;  off = 0.10;
% 
%     MFR_LIST   = {'Ford',      'Toyota',    'Chevrolet'};
%     MFR_OFFSET = [-off,         0,           +off      ];
%     MFR_COLOUR = {[0.0 0.3 0.7],[0.8 0.1 0.1],[0.9 0.7 0.0]};
% 
%     y_ch    = pd.y_channels{1};
%     y_field = sanitise_fn(y_ch);
% 
%     spd_min = -Inf;  spd_max = Inf;
%     season_file = get_opt(opts, 'season_file', 'C:\SimEnv\trackDB\seasonOverview.xlsx');
%     venue = get_opt(opts, 'venue', '');
%     if ~isempty(venue)
%         try
%             T = readtable(season_file, 'Sheet', '2026');
%             track_col = T.Track;
%             if iscell(track_col)
%                 row = find(strcmpi(strtrim(track_col), strtrim(venue)), 1);
%             else
%                 row = find(strcmpi(strtrim(string(track_col)), strtrim(venue)), 1);
%             end
%             if ~isempty(row)
%                 if ismember('TopSpeedMin', T.Properties.VariableNames), spd_min = T.TopSpeedMin(row); end
%                 if ismember('TopSpeedMax', T.Properties.VariableNames), spd_max = T.TopSpeedMax(row); end
%             end
%         catch, end
%     end
% 
%     driver_mfr = {}; driver_vals = {}; driver_car = {};
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         if ~isfield(entry.stats, y_field), continue; end
%         vals = local_apply_math(entry.stats.(y_field), pd.math_fn);
%         if strcmpi(y_field,'Speed')
%             vals = vals(isfinite(vals) & vals >= spd_min & vals <= spd_max);
%         else
%             vals = vals(isfinite(vals));
%         end
%         if isempty(vals), continue; end
%         driver_vals{end+1} = vals;            %#ok
%         driver_mfr{end+1}  = entry.manufacturer; %#ok
%     end
%     if isempty(driver_vals), warning('make_lapwise_box: no valid data.'); return; end
% 
%     max_lap = max(cellfun(@numel, driver_vals));
%     leg_h = []; leg_l = {}; leg_seen = {};
% 
%     for lap = 1:max_lap
%         for mi = 1:numel(MFR_LIST)
%             mfr = MFR_LIST{mi};  col = MFR_COLOUR{mi};  x0 = lap + MFR_OFFSET(mi);
%             mfr_vals = [];
%             for d = 1:numel(driver_vals)
%                 if strcmpi(driver_mfr{d}, mfr) && lap <= numel(driver_vals{d})
%                     mfr_vals(end+1) = driver_vals{d}(lap); %#ok
%                 end
%             end
%             if numel(mfr_vals) <= 1, continue; end
%                        iq = prctile(mfr_vals,[25 75]);  med_ = median(mfr_vals);
%             mfr_vals = mfr_vals(mfr_vals >= med_ - 3*(iq(2)-iq(1)) & ...
%                                 mfr_vals <= med_ + 3*(iq(2)-iq(1)));
%             if numel(mfr_vals) <= 1, continue; end
%             q    = prctile(mfr_vals,[25 50 75]);
%             iqr_ = q(3)-q(1);
%             w_lo = max(mfr_vals(mfr_vals >= q(1)-1.5*iqr_));
%             w_hi = min(mfr_vals(mfr_vals <= q(3)+1.5*iqr_));
%             if isfield(pd,'highlight_outliers') && pd.highlight_outliers
%                 thr = pd.outlier_threshold;
%                 switch pd.outlier_method
%                     case 'iqr'
%                         otl = mfr_vals(mfr_vals < q(1)-thr*iqr_ | mfr_vals > q(3)+thr*iqr_);
%                     otherwise % mad
%                         mad_v = median(abs(mfr_vals - q(2)));
%                         otl   = mfr_vals(mfr_vals < q(2)-thr*mad_v | mfr_vals > q(2)+thr*mad_v);
%                 end
%             else
%                 otl = mfr_vals(mfr_vals < q(1)-1.5*iqr_ | mfr_vals > q(3)+1.5*iqr_);
%             end
%             xb = [x0-bw,x0+bw,x0+bw,x0-bw,x0-bw];
%             yb = [q(1),q(1),q(3),q(3),q(1)];
%             fill(ax,xb,yb,col,'FaceAlpha',0.4,'EdgeColor',col,'LineWidth',1.2);
%             plot(ax,[x0-bw,x0+bw],[q(2),q(2)],'-','Color',col,'LineWidth',2);
%             plot(ax,[x0,x0],[q(1),w_lo],'-','Color',col,'LineWidth',1);
%             plot(ax,[x0,x0],[q(3),w_hi],'-','Color',col,'LineWidth',1);
%             plot(ax,[x0-bw*0.5,x0+bw*0.5],[w_lo,w_lo],'-','Color',col,'LineWidth',1);
%             plot(ax,[x0-bw*0.5,x0+bw*0.5],[w_hi,w_hi],'-','Color',col,'LineWidth',1);
%             if ~isempty(otl)
%                 scatter(ax,repmat(x0,size(otl)),otl,20,col,'o','MarkerEdgeColor',col,'MarkerFaceAlpha',0);
%             end
%             if ~any(strcmp(leg_seen, mfr))
%                 h = fill(ax,NaN,NaN,col,'FaceAlpha',0.4,'EdgeColor',col);
%                 leg_h(end+1)=h; leg_l{end+1}=mfr; leg_seen{end+1}=mfr; %#ok
%             end
%         end
%     end
%     xlabel(ax,'Lap Number','FontSize',fs,'Interpreter','none');
%     ylabel(ax,y_ch,'FontSize',fs,'Interpreter','none');
%     ax.XTick = 1:max_lap;
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% 
% 
% % ======================================================================= %
% %  SESSION LAP WISE  (NEW)
% %  Groups by session, then car. Outings stacked in run_list order.
% % ======================================================================= %
% function fig = make_session_lap_wise(run_list, pd, colour_cfg, driver_map, opts, ax_in)
%     if nargin < 6, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs = get_opt(opts, 'font_size', 11);
% 
%     sessions = unique({run_list.session}, 'stable');
%     cars     = unique({run_list.car},     'stable');
% 
%     leg_h = []; leg_l = {}; leg_seen = {};
% 
%     for s = 1:numel(sessions)
%         sess      = sessions{s};
%         sess_runs = run_list(strcmp({run_list.session}, sess));
% 
%         for c = 1:numel(cars)
%             car_runs = sess_runs(strcmp({sess_runs.car}, cars{c}));
%             if isempty(car_runs), continue; end
% 
%             col = resolve_colour(car_runs(1), pd.colour_mode, colour_cfg, driver_map);
% 
%             for yi = 1:numel(pd.y_channels)
%                 y_ch    = pd.y_channels{yi};
%                 y_field = sanitise_fn(y_ch);
% 
%                 x_all = []; y_all = [];
%                 lap_offset = 0;
% 
%                 for r = 1:numel(car_runs)
%                     entry = car_runs(r);
%                     if ~isfield(entry.stats, y_field), continue; end
%                     y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
%                     lap_nums = entry.stats.(y_field).lap_numbers;
%                     valid    = isfinite(y_vals);
%                     y_vals   = y_vals(valid);  lap_nums = lap_nums(valid);
%                     if isempty(y_vals), continue; end
%                     x_all = [x_all; lap_nums(:) + lap_offset]; %#ok
%                     y_all = [y_all; y_vals(:)];                %#ok
%                     lap_offset = lap_offset + max(lap_nums);
%                 end
%                 if isempty(x_all), continue; end
% 
%                 h = plot(ax, x_all, y_all, '-o', ...
%                     'Color', col, 'LineWidth', 1.8, 'MarkerSize', 4, ...
%                     'MarkerFaceColor', col, 'MarkerEdgeColor', col*0.7);
% 
%                 % Build legend label — group by colour_mode key, not car number
%                 switch lower(pd.colour_mode)
%                     case 'manufacturer'
%                         leg_key = car_runs(1).manufacturer;
%                         if isempty(leg_key), leg_key = sprintf('#%s', cars{c}); end
%                     case 'team'
%                         leg_key = car_runs(1).team;
%                         if isempty(leg_key), leg_key = sprintf('#%s', cars{c}); end
%                     otherwise  % driver — keep individual car identity
%                         if numel(sessions) > 1
%                             leg_key = sprintf('#%s  %s', cars{c}, sess);
%                         else
%                             leg_key = sprintf('#%s', cars{c});
%                         end
%                 end
%                 if numel(pd.y_channels) > 1, leg_key = sprintf('%s  [%s]', leg_key, y_ch); end
%                 if ~any(strcmp(leg_seen, leg_key))
%                     leg_h(end+1) = h; leg_l{end+1} = leg_key; leg_seen{end+1} = leg_key; %#ok
%                 end
%             end
%         end
%     end
% 
%     xlabel(ax, 'Session Lap', 'FontSize', fs, 'Interpreter','none');
%     ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% 
% 
% % ======================================================================= %
% %  AXIS LIMITS  (NEW)
% % ======================================================================= %
% function apply_axis_limits(fig, pd)
%     % Find all axes, exclude legend/colorbar pseudo-axes by checking Tag
%     all_ax = findobj(fig, 'Type', 'axes');
%     plot_ax = [];
%     for i = 1:numel(all_ax)
%         t = get(all_ax(i), 'Tag');
%         if isempty(t) || strcmpi(t, '')
%             plot_ax(end+1) = all_ax(i); %#ok
%         end
%     end
%     if isempty(plot_ax), return; end
%     % Primary axes = first created = last in findobj stack
%     ax = plot_ax(end);
%     if isfield(pd,'x_lim') && numel(pd.x_lim) == 2, xlim(ax, pd.x_lim); end
%     if isfield(pd,'y_lim') && numel(pd.y_lim) == 2, ylim(ax, pd.y_lim); end
% end
% 
% 
% % ======================================================================= %
% %  OUTLIER HIGHLIGHTING  (NEW)
% % ======================================================================= %
% % function draw_outlier_highlights(fig, pd, run_list, colour_cfg, driver_map)
% %     ax = findobj(fig, 'Type', 'axes');
% %     if isempty(ax), return; end
% %     ax = ax(end);
% % 
% %     method    = pd.outlier_method;
% %     threshold = pd.outlier_threshold;
% %     fs_ann    = 8;
% % 
% %     mfrs = unique({run_list.manufacturer}, 'stable');
% % 
% %     for m = 1:numel(mfrs)
% %         mfr      = mfrs{m};
% %         mfr_runs = run_list(strcmp({run_list.manufacturer}, mfr));
% %         col      = resolve_colour(mfr_runs(1), 'manufacturer', colour_cfg, driver_map);
% % 
% %         for yi = 1:numel(pd.y_channels)
% %             y_field = sanitise_fn(pd.y_channels{yi});
% % 
% %             pool = [];
% %             for r = 1:numel(mfr_runs)
% %                 if ~isfield(mfr_runs(r).stats, y_field), continue; end
% %                 v = local_apply_math(mfr_runs(r).stats.(y_field), pd.math_fn);
% %                 pool = [pool, v(isfinite(v))]; %#ok
% %             end
% %             if numel(pool) < 4, continue; end
% % 
% %             switch method
% %                 case 'iqr'
% %                     q1 = prctile(pool,25);  q3 = prctile(pool,75);
% %                     iq = q3 - q1;
% %                     lo = q1 - threshold*iq;  hi = q3 + threshold*iq;
% %                 otherwise % mad
% %                     med_  = median(pool);
% %                     mad_  = median(abs(pool - med_));
% %                     lo = med_ - threshold*mad_;  hi = med_ + threshold*mad_;
% %             end
% % 
% %             for r = 1:numel(mfr_runs)
% %                 entry = mfr_runs(r);
% %                 if ~isfield(entry.stats, y_field), continue; end
% %                 y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
% %                 lap_nums = entry.stats.(y_field).lap_numbers;
% %                 valid    = isfinite(y_vals);
% %                 y_vals   = y_vals(valid);  lap_nums = lap_nums(valid);
% % 
% %                 out_mask = y_vals < lo | y_vals > hi;
% %                 if ~any(out_mask), continue; end
% % 
% %                 scatter(ax, lap_nums(out_mask), y_vals(out_mask), 80, ...
% %                     'MarkerEdgeColor', col, 'MarkerFaceColor', 'none', ...
% %                     'LineWidth', 2.0, 'HandleVisibility', 'off');
% % 
% %                 out_idx = find(out_mask);
% %                 for k = 1:numel(out_idx)
% %                     i = out_idx(k);
% %                     text(ax, lap_nums(i), y_vals(i), ...
% %                         sprintf('  #%s L%d', entry.car, lap_nums(i)), ...
% %                         'FontSize', fs_ann, 'Color', col*0.75, ...
% %                         'VerticalAlignment', 'middle', ...
% %                         'HorizontalAlignment', 'left', 'Interpreter', 'none');
% %                 end
% %             end
% %         end
% %     end
% % end
% 
% function draw_outlier_highlights(fig, pd, run_list, colour_cfg, driver_map, ax_in)
%     if nargin >= 6 && ~isempty(ax_in) && isgraphics(ax_in)
%         ax = ax_in;
%     else
%         ax = findobj(fig, 'Type', 'axes');
%         if isempty(ax), return; end
%         ax = ax(end);
%     end
% 
%     method       = pd.outlier_method;
%     threshold    = pd.outlier_threshold;
%     fs_ann       = 8;
%     MAX_OUTLIERS = 5;
% 
%     % Accumulate ALL candidates across every manufacturer + channel first
%     all_laps = [];
%     all_vals = [];
%     all_cars = {};
%     all_cols = {};
%     all_devs = [];
%     all_mfrs = {};
%     mfrs = unique({run_list.manufacturer}, 'stable');
% 
%     for m = 1:numel(mfrs)
%         mfr      = mfrs{m};
%         mfr_runs = run_list(strcmp({run_list.manufacturer}, mfr));
%         col      = resolve_colour(mfr_runs(1), 'manufacturer', colour_cfg, driver_map);
% 
%         for yi = 1:numel(pd.y_channels)
%             y_field = sanitise_fn(pd.y_channels{yi});
% 
%             pool = [];
%             for r = 1:numel(mfr_runs)
%                 if ~isfield(mfr_runs(r).stats, y_field), continue; end
%                 v = local_apply_math(mfr_runs(r).stats.(y_field), pd.math_fn);
%                 pool = [pool, v(isfinite(v))]; %#ok
%             end
%             if numel(pool) < 4, continue; end
% 
%             switch method
%                 case 'iqr'
%                     q1 = prctile(pool,25);  q3 = prctile(pool,75);
%                     iq = q3 - q1;
%                     lo = q1 - threshold*iq;  hi = q3 + threshold*iq;
%                     centre = (q1 + q3) / 2;
%                 otherwise % mad
%                     med_  = median(pool);
%                     mad_  = median(abs(pool - med_));
%                     lo = med_ - threshold*mad_;  hi = med_ + threshold*mad_;
%                     centre = med_;
%             end
% 
%             for r = 1:numel(mfr_runs)
%                 entry = mfr_runs(r);
%                 if ~isfield(entry.stats, y_field), continue; end
%                 y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
%                 lap_nums = entry.stats.(y_field).lap_numbers;
%                 valid    = isfinite(y_vals);
%                 y_vals   = y_vals(valid);  lap_nums = lap_nums(valid);
% 
%                 out_idx = find(y_vals < lo | y_vals > hi);
%                 for k = 1:numel(out_idx)
%                     i = out_idx(k);
%                     all_laps(end+1) = lap_nums(i);              %#ok
%                     all_vals(end+1) = y_vals(i);                %#ok
%                     all_cars{end+1} = entry.car;                %#ok
%                     all_cols{end+1} = col;                      %#ok
%                     all_devs(end+1) = abs(y_vals(i) - centre);  %#ok
%                     all_mfrs{end+1} = mfr;
%                 end
%             end
%         end
%     end
% 
%     if isempty(all_laps), return; end
% 
%     scope = 'manufacturer';
%     if isfield(pd, 'outlier_scope') && strcmpi(pd.outlier_scope, 'global')
%         scope = 'global';
%     end
% 
%     if strcmpi(scope, 'global')
%         global_centre = median(all_vals);
%         global_devs   = abs(all_vals - global_centre);
%         [~, rank_order] = sort(global_devs, 'descend');
%         keep = rank_order(1 : min(MAX_OUTLIERS, numel(rank_order)));
%     else
%         mfr_tags = unique(all_mfrs, 'stable');
%         keep = [];
%         for m = 1:numel(mfr_tags)
%             mfr_idx = find(strcmp(all_mfrs, mfr_tags{m}));
%             [~, rank_order] = sort(all_devs(mfr_idx), 'descend');
%             keep = [keep, mfr_idx(rank_order(1 : min(MAX_OUTLIERS, numel(rank_order))))]; %#ok
%         end
%     end
% 
%     scat_handles = gobjects(numel(keep), 1);
%     for k = 1:numel(keep)
%         i   = keep(k);
%         col = all_cols{i};
%         scat_handles(k) = scatter(ax, all_laps(i), all_vals(i), 80, ...
%             'MarkerEdgeColor', col, 'MarkerFaceColor', 'none', ...
%             'LineWidth', 2.0, 'HandleVisibility', 'off');
%         text(ax, all_laps(i), all_vals(i), ...
%             sprintf('  #%s L%d', all_cars{i}, all_laps(i)), ...
%             'FontSize', fs_ann, 'Color', col*0.75, ...
%             'VerticalAlignment', 'middle', ...
%             'HorizontalAlignment', 'left', 'Interpreter', 'none');
%     end
%     uistack(scat_handles, 'top');
% end
% % ======================================================================= %
% %  LINE
% % ======================================================================= %
% function fig = make_line(run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in)
%     if nargin < 7, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs = get_opt(opts, 'font_size', 11);
%     use_secondary = isfield(pd,'use_secondary') && pd.use_secondary && numel(pd.y_channels) >= 2;
%     use_shapes    = strcmpi(pd.differentiator, 'shapes');
% 
%     leg_h = []; leg_l = {}; leg_seen = {};
%     x_lbl = 'Lap Number';
% 
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
% 
%         for yi = 1:numel(pd.y_channels)
%             y_ch    = pd.y_channels{yi};
%             y_field = sanitise_fn(y_ch);
%             if ~isfield(entry.stats, y_field), continue; end
% 
%             if use_secondary && yi == 2
%                 yyaxis(ax, 'right');
%                 ylabel(ax, pd.y_channels{yi}, 'FontSize', fs, 'Interpreter','none');
%             elseif use_secondary && yi == 1
%                 yyaxis(ax, 'left');
%                 ylabel(ax, pd.y_channels{1}, 'FontSize', fs, 'Interpreter','none');
%             end
% 
%             y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
%             lap_nums = entry.stats.(y_field).lap_numbers;
%             valid    = isfinite(y_vals);
%             y_vals   = y_vals(valid);  lap_nums = lap_nums(valid);
%             if isempty(y_vals), continue; end
% 
%             if is_keyword_lap(pd.x_axis)
%                 x_vals = lap_nums;  x_lbl = 'Lap Number';
%             else
%                 x_field = sanitise_fn(pd.x_axis);
%                 if isfield(entry.stats, x_field)
%                     xv = local_apply_math(entry.stats.(x_field), pd.math_fn);
%                     x_vals = xv(valid);  x_lbl = pd.x_axis;
%                 else
%                     x_vals = lap_nums;  x_lbl = 'Lap Number';
%                 end
%             end
% 
%             marker = 'none';
%             if use_shapes && yi <= numel(SHAPES), marker = SHAPES{yi}; end
% 
%             h = plot(ax, x_vals, y_vals, '-', ...
%                 'Color', col, 'LineWidth', 1.8, 'Marker', marker, 'MarkerSize', 5);
% 
%             lbl = build_label(entry, pd, yi, driver_map);
%             if ~any(strcmp(leg_seen, lbl))
%                 leg_h(end+1)=h; leg_l{end+1}=lbl; leg_seen{end+1}=lbl; %#ok
%             end
%         end
%     end
% 
%     if use_secondary, yyaxis(ax, 'left'); end
%     xlabel(ax, x_lbl, 'FontSize', fs, 'Interpreter','none');
%     if ~use_secondary
%         ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
%     end
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% 
% 
% % ======================================================================= %
% %  BOXPLOT
% % ======================================================================= %
% function fig = make_boxplot(run_list, pd, colour_cfg, driver_map, opts, ax_in)
%     if nargin < 6, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
% 
%     all_vals = []; all_grp = []; grp_labels = {}; colours = [];
%     gi = 0;
% 
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
%         for yi = 1:numel(pd.y_channels)
%             y_field = sanitise_fn(pd.y_channels{yi});
%             if ~isfield(entry.stats, y_field), continue; end
%             vals = get_dist_vals(entry, y_field, pd.math_fn);
%             if isempty(vals), continue; end
%             gi = gi + 1;
%             all_vals(end+1:end+numel(vals)) = vals(:)';  %#ok
%             all_grp(end+1:end+numel(vals))  = gi;        %#ok
%             grp_labels{gi} = build_label(entry, pd, yi, driver_map); %#ok
%             colours(gi,:)  = col;                        %#ok
%         end
%     end
%     if isempty(all_vals), return; end
%     bp = boxplot(ax, all_vals, all_grp, 'Labels', grp_labels, 'Widths', 0.4, 'Symbol', '+');
%     colour_boxplot(bp, colours);
%     ax.XTickLabelRotation = 30;
% end
% 
% 
% % ======================================================================= %
% %  VIOLIN
% % ======================================================================= %
% function fig = make_violin(run_list, pd, colour_cfg, driver_map, opts, ax_in)
%     if nargin < 6, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
% 
%     gi = 0; tick_pos = []; tick_labels = {};
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
%         for yi = 1:numel(pd.y_channels)
%             y_field = sanitise_fn(pd.y_channels{yi});
%             if ~isfield(entry.stats, y_field), continue; end
%             vals = get_dist_vals(entry, y_field, pd.math_fn);
%             if numel(vals) < 3, continue; end
%             gi = gi + 1;
%             [f, xi] = ksdensity(vals);
%             f = f / max(f) * 0.4;
%             fill(ax, [gi+f, fliplr(gi-f)], [xi, fliplr(xi)], col, ...
%                 'FaceAlpha',0.65,'EdgeColor',col*0.75,'LineWidth',0.8);
%             plot(ax, [gi-0.15 gi+0.15], [median(vals) median(vals)], '-','Color',col*0.5,'LineWidth',2);
%             plot(ax, [gi gi], [prctile(vals,25) prctile(vals,75)], '-','Color',col*0.5,'LineWidth',3);
%             tick_pos(end+1)    = gi;                          %#ok
%             tick_labels{end+1} = build_label(entry, pd, yi, driver_map); %#ok
%         end
%     end
%     if gi == 0, return; end
%     set(ax,'XTick',tick_pos,'XTickLabel',tick_labels);
%     ax.XTickLabelRotation = 30;
%     xlim(ax,[0.5, gi+0.5]);
% end
% 
% 
% % ======================================================================= %
% %  HISTOGRAM
% % ======================================================================= %
% function fig = make_histogram(run_list, pd, colour_cfg, driver_map, opts, ax_in)
%     if nargin < 6, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs = get_opt(opts, 'font_size', 11);
% 
%     leg_h = []; leg_l = {}; leg_seen = {};
%     
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
%         for yi = 1:numel(pd.y_channels)
%             y_field = sanitise_fn(pd.y_channels{yi});
%             if ~isfield(entry.stats, y_field), continue; end
%             vals = get_dist_vals(entry, y_field, pd.math_fn);
%             if isempty(vals), continue; end
%             
%             % plotting magic of the PSD
%             
%             h = histogram(ax, vals, 'FaceColor', col, 'EdgeColor', col*0.7, ...
%                 'FaceAlpha', 0.5, 'Normalization', 'probability');
%             lbl = build_label(entry, pd, yi, driver_map);
%             if ~any(strcmp(leg_seen, lbl))
%                 leg_h(end+1)=h; leg_l{end+1}=lbl; leg_seen{end+1}=lbl; %#ok
%             end
%         end
%     end
%     xlabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
%     ylabel(ax, 'Probability', 'FontSize', fs);
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% % ======================================================================= %
% %  Make PSD
% % ======================================================================= %
% 
% % ======================================================================= %
% %  PSD  (Welch, no toolbox)
% %  pd.y_channels{1} = signal channel
% %  pd.z_axis        = gate channel (0/1 mask); empty = no gating
% % ======================================================================= %
% function [fig, psd_stats] = make_psd(run_list, pd, colour_cfg, driver_map, opts, ax_in)
%     if nargin < 6, ax_in = []; end
% 
%     % --- PSD config (overridable via opts) ---
%     win_len  = get_opt(opts, 'psd_win_len',  256);
%     overlap  = get_opt(opts, 'psd_overlap',  128);
%     nfft     = get_opt(opts, 'psd_nfft',     512);
%     freq_max = get_opt(opts, 'psd_freq_max', 12);
%     fs_font  = get_opt(opts, 'font_size',    11);
% 
%     % --- Figure / axes ---
%     if isempty(ax_in)
%         fw  = get_opt(opts, 'fig_width',  1200);
%         fh  = get_opt(opts, 'fig_height', 650);
%         fig = figure('Visible','off','Color','white','Position',[100 100 fw fh]);
%         ax  = axes(fig);
%     else
%         ax  = ax_in;
%         fig = ancestor(ax, 'figure');
%     end
%     hold(ax, 'on');
%     box(ax, 'on');
%     grid(ax, 'on');
%     set(ax, 'FontSize', fs_font, 'FontName', 'Arial', ...
%         'GridAlpha', 0.25, 'GridLineStyle', '--', 'GridColor', [0.7 0.7 0.7]);
%     ax.Color  = [0.97 0.97 0.97];
%     fig.Color = 'white';
% 
%     y_ch     = pd.y_channels{1};
%     y_field  = sanitise_fn(y_ch);
%     has_gate = isfield(pd, 'z_axis') && ~isempty(pd.z_axis);
%     if has_gate
%         gate_field = sanitise_fn(pd.z_axis);
%     end
% 
%     leg_h = []; leg_l = {};
% 
%     psd_stats = struct('driver',{}, 'lap_time',{}, 'value',{}, 'col',{});
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
% 
%         % --- Get fastest lap channels ---
%         laps = entry;
%         if isempty(laps), continue; end
%         [~, best] = min([laps.best_lap_time]);
%         lap_ch = laps(best).traces;
% 
%         % --- Find signal ---
%         fn    = fieldnames(lap_ch);
%         match = fn(strcmpi(fn, y_field));
%         if isempty(match)
%             fprintf('  [WARN] PSD: channel "%s" not found for %s\n', y_ch, entry.driver);
%             continue;
%         end
%         sig = lap_ch.(match{1})(best).data(:);
%         Fs  =  unique(entry.stats.(match{1})(best).sample_rate);
% 
%         % --- Apply gate (zero out where gate == 0) ---
%         if has_gate
%             gmatch = fn(strcmpi(fn, gate_field));
%             if ~isempty(gmatch)
%                 gate = lap_ch.(gmatch{1}).data(:);
%                 % Align lengths
%                 n = min(numel(sig), numel(gate));
%                 sig  = sig(1:n);
%                 gate = gate(1:n);
%                 sig(gate == 0) = 0;
%             else
%                 fprintf('  [WARN] PSD: gate channel "%s" not found for %s — no gating applied\n', ...
%                     pd.z_axis, entry.driver);
%             end
%         end
% 
%         sig(isnan(sig)) = 0;
%         sig = sig - mean(sig);
% 
%         % --- Welch PSD (manual) ---
%         w       = 0.5 * (1 - cos(2*pi*(0:win_len-1)' / (win_len-1)));
%         w_power = sum(w.^2);
%         starts  = 1:(win_len-overlap):numel(sig)-win_len+1;
%         n_segs  = numel(starts);
%         if n_segs < 1, continue; end
%         pxx = zeros(nfft/2+1, 1);
%         for k = 1:n_segs
%             seg = sig(starts(k):starts(k)+win_len-1) .* w;
%             X   = fft(seg, nfft);
%             pxx = pxx + abs(X(1:nfft/2+1)).^2;
%         end
%         pxx = pxx ./ (n_segs * unique(Fs) * w_power);
%         pxx(2:end-1) = 2 * pxx(2:end-1);
%         f = (0:nfft/2)' * Fs / nfft;
% 
%         f_mask = f > 0.2 & f < freq_max;
% 
%         lbl = build_label(entry, pd, 1, driver_map);
%         h   = semilogy(ax, f(f_mask), pxx(f_mask), '-', ...
%             'Color', col, 'LineWidth', 1.5, 'DisplayName', lbl);
%         
%         set(ax, 'YScale', 'log');
% 
%         leg_h(end+1) = h;    %#ok
%         leg_l{end+1} = lbl;  %#ok
%         
%         % --- Extract scalar stat from frequency band ---
%         stat_range = get_opt(opts, 'psd_stat_freq_range', [1 4]);
%         stat_fn    = get_opt(opts, 'psd_stat_fn',         'max');
%         band_mask  = f >= stat_range(1) & f <= stat_range(2);
%         band_pxx   = pxx(band_mask);
%         if strcmp(stat_fn, 'min')
%             scalar = min(band_pxx);
%         else
%             scalar = max(band_pxx);
%         end
%         
%         psd_stats(r).driver   = entry.driver;
%         psd_stats(r).lap_time = laps.best_lap_time;
%         psd_stats(r).value    = scalar;
%         psd_stats(r).col      = col;
%         
%     end
% 
%     title(ax, pd.name, 'FontSize', fs_font+1, 'FontWeight', 'bold', 'Interpreter', 'none');
%     xlabel(ax, 'Frequency (Hz)', 'FontSize', fs_font, 'Interpreter', 'none');
%     ylabel(ax, sprintf('PSD (%s²/Hz)', y_ch), 'FontSize', fs_font, 'Interpreter', 'none');
%     xlim(ax, [0.2 freq_max]);
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% % ======================================================================= %
% %  TIMESERIES
% % ======================================================================= %
% 
% % ======================================================================= %
% %  PSD SCATTER  — lap time vs PSD scalar extracted from make_psd
% % ======================================================================= %
% % function fig = make_psd_scatter(run_list, pd, colour_cfg, driver_map, opts, SHAPES)
% function fig = make_psd_scatter(run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in)
%     if nargin < 7, ax_in = []; end
%     if isempty(ax_in)
%         [fig, ax] = new_fig(pd, opts);
%     else
%         ax  = ax_in;
%         fig = ancestor(ax, 'figure');
%     end
%     hold(ax, 'on');
% 
%     fs         = get_opt(opts, 'font_size',           11);
%     stat_range = get_opt(opts, 'psd_stat_freq_range', [3 5]);
%     stat_fn    = get_opt(opts, 'psd_stat_fn',         'max');
%     win_len    = get_opt(opts, 'psd_win_len',          256);
%     overlap    = get_opt(opts, 'psd_overlap',          128);
%     nfft       = get_opt(opts, 'psd_nfft',             512);
% 
%     has_gate = isfield(pd, 'z_axis') && ~isempty(pd.z_axis);
%     if has_gate, gate_field = sanitise_fn(pd.z_axis); end
% 
%     y_ch    = pd.y_channels{1};
%     y_field = sanitise_fn(y_ch);
% 
%     leg_h = []; leg_l = {};
% 
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
%         col   = col(:)';
% 
%         tr = entry.traces;
%         if isempty(tr) || ~isstruct(tr) || tr.n_traces == 0
%             fprintf('  [WARN] psd_scatter: no traces for %s\n', entry.driver);
%             continue;
%         end
% 
%         % --- Find signal field using strcmpi (same as working psd code) ---
%         tr_fn = fieldnames(tr);
%         match = tr_fn(strcmpi(tr_fn, y_field));
%         if isempty(match)
%             fprintf('  [WARN] psd_scatter: channel "%s" not found for %s\n', y_ch, entry.driver);
%             continue;
%         end
%         lap_traces = tr.(match{1});
% 
%         % --- Gate field ---
%         gate_traces = [];
%         if has_gate
%             gmatch = tr_fn(strcmpi(tr_fn, gate_field));
%             if ~isempty(gmatch)
%                 gate_traces = tr.(gmatch{1});
%             else
%                 fprintf('  [WARN] psd_scatter: gate "%s" not found for %s\n', pd.z_axis, entry.driver);
%             end
%         end
% 
%         x_vals = []; y_vals = [];
% 
%         for li = 1:tr.n_traces
%             sig = lap_traces(li).data(:);
%             Fs  = unique(entry.stats.(match{1}).sample_rate);   % sample_rate on the trace struct directly
% 
%             % --- Gate ---
%             if ~isempty(gate_traces) && li <= numel(gate_traces)
%                 gate = gate_traces(li).data(:);
%                 n    = min(numel(sig), numel(gate));
%                 sig  = sig(1:n);
%                 gate = gate(1:n);
%                 sig(gate == 0) = 0;
%             end
% 
%             sig(isnan(sig)) = 0;
%             sig = sig - mean(sig);
% 
%             if numel(sig) < win_len, continue; end
% 
%             % --- Welch PSD ---
%             w       = 0.5*(1 - cos(2*pi*(0:win_len-1)'/(win_len-1)));
%             w_power = sum(w.^2);
%             starts  = 1:(win_len-overlap):numel(sig)-win_len+1;
%             n_segs  = numel(starts);
%             if n_segs < 1, continue; end
% 
%             pxx = zeros(nfft/2+1, 1);
%             for k = 1:n_segs
%                 seg = sig(starts(k):starts(k)+win_len-1) .* w;
%                 X   = fft(seg, nfft);
%                 pxx = pxx + abs(X(1:nfft/2+1)).^2;
%             end
%             pxx = pxx ./ (n_segs .* Fs .* w_power);
%             pxx(2:end-1) = 2*pxx(2:end-1);
%             f = (0:nfft/2)' .* Fs ./ nfft;
% 
%             band_mask = f >= stat_range(1) & f <= stat_range(2);
%             band_pxx  = pxx(band_mask);
%             if isempty(band_pxx), continue; end
% 
%             if strcmp(stat_fn, 'min')
%                 scalar = min(band_pxx);
%             else
%                 scalar = max(band_pxx);
%             end
% 
%             x_vals(end+1) = tr.lap_times(li);  %#ok
%             y_vals(end+1) = scalar;             %#ok
%         end
% 
%         if isempty(x_vals), continue; end
% 
%         h = scatter(ax, y_vals, x_vals, 40, col, 'o', 'filled', ...
%             'MarkerEdgeColor', col*0.7, 'MarkerFaceAlpha', 0.8);
%         lbl = build_label(entry, pd, 1, driver_map);
%         leg_h(end+1) = h;    %#ok
%         leg_l{end+1} = lbl;  %#ok
%     end
% 
%     ylabel(ax, 'Lap Time (s)', 'FontSize', fs, 'Interpreter', 'none');
%     xlabel(ax, sprintf('%s PSD %s [%.0f-%.0f Hz]', y_ch, stat_fn, ...
%         stat_range(1), stat_range(2)), 'FontSize', fs, 'Interpreter', 'none');
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% 
% 
% function fig = make_timeseries(run_list, pd, colour_cfg, driver_map, opts, ...
%                                 dist_ch, dist_npts, n_laps_avg, ax_in)
%     if nargin < 9, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs  = get_opt(opts, 'font_size', 11);
%     lw  = 2.0;  lwa = 0.8;
% 
%     leg_h = []; leg_l = {}; leg_seen = {};
% 
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
% 
%         if strcmp(entry.mode, 'stream')
%             tr = entry.traces;
%             if isempty(tr) || ~isstruct(tr) || tr.n_traces == 0
%                 fprintf('  [WARN] No traces for %s — skipping timeseries.\n', entry.driver);
%                 continue;
%             end
%             for yi = 1:numel(pd.y_channels)
%                 y_ch    = pd.y_channels{yi};
%                 y_field = sanitise_fn(y_ch);
%                 if ~isfield(tr, y_field)
%                     fprintf('  [WARN] Trace "%s" not found for %s\n', y_ch, entry.driver);
%                     continue;
%                 end
% % ==========================Editted and commented out=================
% % lap_traces = tr.(y_field);
% % 
% % d_best = lap_traces(1).dist(:);
% % y_best = lap_traces(1).data(:);
% % if isempty(d_best) || isempty(y_best), continue; end
% % 
% % h_best = plot(ax, d_best, y_best, '-', 'Color', col, 'LineWidth', lw);
% % lbl = build_label(entry, pd, 1, driver_map);
% % if ~any(strcmp(leg_seen, lbl))
% %     leg_h(end+1)    = h_best; %#ok
% %     leg_l{end+1}    = sprintf('%s  [%.2fs]', lbl, tr.lap_times(1)); %#ok
% %     leg_seen{end+1} = lbl; %#ok
% % end
% % 
% % for k = 2:n_show
%                 lap_traces = tr.(y_field);
% 
%                 % Select best lap — exclude lap 0 (pitlane/install lap in non-race sessions)
%                 valid_k = find(tr.lap_numbers >= -1 & isfinite(tr.lap_times));
%                 if isempty(valid_k)
%                     valid_k = 1:tr.n_traces;   % fallback: use all
%                 end
%                 [~, rel_best] = min(tr.lap_times(valid_k));
%                 best_k = valid_k(rel_best);
% 
%                 n_show = tr.n_traces;
%                 d_best = lap_traces(best_k).dist(:);
%                 y_best = lap_traces(best_k).data(:);
%                 if isempty(d_best) || isempty(y_best), continue; end
% 
%                 h_best = plot(ax, d_best, y_best, '-', 'Color', col, 'LineWidth', lw);
%                 lbl = build_label(entry, pd, 1, driver_map);
%                 if ~any(strcmp(leg_seen, lbl))
%                     leg_h(end+1) = h_best; %#ok
%                     drv_str  = strrep(entry.driver, '_', ' ');
%                     lap_str  = sprintf('Lap %d | %.3fs', tr.lap_numbers(best_k), tr.lap_times(best_k));
%                     if numel(pd.y_channels) > 1
%                         leg_l{end+1} = sprintf('%s  (%s)  [%s]  [%s]', lbl, drv_str, pd.y_channels{1}, lap_str); %#ok
%                     else
%                         leg_l{end+1} = sprintf('%s  (%s)  [%s]', lbl, drv_str, lap_str); %#ok
%                     end
%                     leg_seen{end+1} = lbl; %#ok
%                 end
% % background laps not being plotted 
% %                 for k = 1:n_show
% %                     if k == best_k, continue; end
% %                     d_k=lap_traces(k).dist(:); y_k=lap_traces(k).data(:);
% %                     if isempty(d_k)||isempty(y_k), continue; end
% %                     plot(ax,d_k,y_k,'-','Color',[col,0.25],'LineWidth',lwa);
% %                 end
%             end
% 
%         else
%             laps = entry.laps;
%             if isempty(laps), continue; end
%             lap_times = [laps.lap_time];
%             [~, best] = min(lap_times);
%             ch_names_b = fieldnames(laps(best).channels);
%             if isempty(ch_names_b) || ~isfield(laps(best).channels.(ch_names_b{1}), 'dist')
%                 fprintf('  [WARN] .dist not found for %s — delete cache and recompile.\n', entry.driver);
%                 continue;
%             end
%             ref_ch = laps(best).channels.(ch_names_b{1});
%             d_grid = ref_ch.dist(:);
%             n_pts  = numel(d_grid);
% 
%             for yi = 1:numel(pd.y_channels)
%                 y_ch    = pd.y_channels{yi};
%                 y_field = find_ch_field(laps(best).channels, y_ch);
%                 if isempty(y_field)
%                     fprintf('  [WARN] Channel "%s" not found for %s\n', y_ch, entry.driver);
%                     continue;
%                 end
%                 y_best = laps(best).channels.(y_field).data(:);
%                 if numel(y_best) ~= n_pts
%                     fprintf('  [WARN] Size mismatch: %s %d vs dist %d for %s\n', ...
%                         y_ch, numel(y_best), n_pts, entry.driver);
%                     continue;
%                 end
%                 h_best = plot(ax, d_grid, y_best, '-', 'Color', col, 'LineWidth', lw);
%                 leg_h(end+1)=h_best; leg_l{end+1}=sprintf('%s  [fastest]', entry.driver); %#ok
% 
%                 if n_laps_avg > 1 && numel(laps) >= n_laps_avg
%                     [~, sorted_idx] = sort(lap_times,'ascend');
%                     avg_idx = sorted_idx(1:n_laps_avg);
%                     lap_mat = NaN(n_pts, n_laps_avg);
%                     for k = 1:n_laps_avg
%                         li = avg_idx(k);
%                         yf_li = find_ch_field(laps(li).channels, y_ch);
%                         if isempty(yf_li), continue; end
%                         y_k = laps(li).channels.(yf_li).data(:);
%                         if numel(y_k) == n_pts, lap_mat(:,k) = y_k; end
%                         plot(ax,d_grid,lap_mat(:,k),'-','Color',[col,0.25],'LineWidth',lwa);
%                     end
%                     y_avg = mean(lap_mat,2,'omitnan');
%                     h_avg = plot(ax,d_grid,y_avg,'--','Color',col,'LineWidth',lw);
%                     leg_h(end+1)=h_avg; leg_l{end+1}=sprintf('%s  [%d-lap avg]',entry.driver,n_laps_avg); %#ok
%                     y_p25=prctile(lap_mat,25,2); y_p75=prctile(lap_mat,75,2);
%                     vb=~isnan(y_p25)&~isnan(y_p75);
%                     if any(vb)
%                         fill(ax,[d_grid(vb);flipud(d_grid(vb))],[y_p25(vb);flipud(y_p75(vb))], ...
%                             col,'FaceAlpha',0.15,'EdgeColor','none');
%                     end
%                 end
%             end
%         end
%     end
% 
%     xlabel(ax, 'Distance (m)', 'FontSize', fs, 'Interpreter','none');
%     ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% 
% function fig = make_timeseries_align(run_list, pd, colour_cfg, driver_map, opts, ax_in, ~)
% % Plots fastest lap traces from entry.traces, aligned via peak-shift on raw data.
% % No resampling — each trace plots on its own native distance axis, shifted so
% % the dominant peak of the alignment channel sits at a common reference point.
% 
%     if nargin < 6, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs  = get_opt(opts, 'font_size', 11);
%     lw  = 2.0;
% 
%     align_ch = '';
%     if isfield(pd, 'align_channel'), align_ch = pd.align_channel; end
%     align_win = [];
%     if isfield(pd, 'align_window') && numel(pd.align_window) == 2
%         align_win = pd.align_window(:)';
%     end
%     max_offset = 60;
%     if isfield(pd, 'align_max_offset') && isfinite(pd.align_max_offset)
%         max_offset = pd.align_max_offset;
%     end
% 
%     n         = numel(run_list);
%     offsets_m = zeros(1, n);
%     valid     = false(1, n);
% 
%     % ---- Validate: each run must have traces with the first y-channel ----
%     y0_field = sanitise_fn(pd.y_channels{1});
%     for r = 1:n
%         tr = run_list(r).traces;
%         if isempty(tr) || ~isstruct(tr), continue; end
%         if ~isfield(tr, y0_field),       continue; end
%         if isempty(tr.(y0_field)),        continue; end
%         if ~isfield(tr.(y0_field)(1), 'dist') || isempty(tr.(y0_field)(1).dist)
%             continue;
%         end
%         valid(r) = true;
%     end
% 
%     valid_idx = find(valid);
%     if numel(valid_idx) < 2
%         warning('make_timeseries_align: fewer than 2 runs with valid traces for "%s".', ...
%                 pd.y_channels{1});
%         return;
%     end
% 
%     % ---- Compute peak-based offsets on raw data ----
%     ref           = valid_idx(1);
%     align_field   = sanitise_fn(align_ch);
%     ref_peak_dist = NaN;
% 
%     if ~isempty(align_ch)
%         tr_ref = run_list(ref).traces;
%         if isfield(tr_ref, align_field) && ~isempty(tr_ref.(align_field))
%             d_ref = tr_ref.(align_field)(1).dist(:);
%             v_ref = tr_ref.(align_field)(1).data(:);
%             if ~isempty(align_win)
%                 mask = d_ref >= align_win(1) & d_ref <= align_win(2);
%             else
%                 mask = true(size(d_ref));
%             end
%             if sum(mask) >= 5
%                 [~, pk_idx]   = max(v_ref(mask));
%                 d_masked      = d_ref(mask);
%                 ref_peak_dist = d_masked(pk_idx);
%             end
%         end
% 
%         if isnan(ref_peak_dist)
%             warning('make_timeseries_align: could not find peak in reference run — no alignment applied.');
%         else
%             fprintf('  Align reference peak at %.1fm\n', ref_peak_dist);
%             for r = valid_idx(2:end)
%                 tr = run_list(r).traces;
%                 if ~isfield(tr, align_field) || isempty(tr.(align_field)), continue; end
%                 d_raw = tr.(align_field)(1).dist(:);
%                 v_raw = tr.(align_field)(1).data(:);
%                 if ~isempty(align_win)
%                     mask = d_raw >= align_win(1) & d_raw <= align_win(2);
%                 else
%                     mask = true(size(d_raw));
%                 end
%                 if sum(mask) < 5, continue; end
%                 [~, pk_idx]   = max(v_raw(mask));
%                 d_masked      = d_raw(mask);
%                 car_peak_dist = d_masked(pk_idx);
%                 offset_m      = ref_peak_dist - car_peak_dist;
%                 if abs(offset_m) > max_offset
%                     warning('make_timeseries_align: %s offset %.1fm capped at %.0fm.', ...
%                             run_list(r).driver, offset_m, max_offset);
%                     offset_m = sign(offset_m) * max_offset;
%                 end
%                 offsets_m(r) = offset_m;
%                 fprintf('  Align %s vs %s: %+.1fm\n', ...
%                         run_list(r).driver, run_list(ref).driver, offset_m);
%             end
%         end
%     else
%         fprintf('  [timeseries_align] No align_channel set — plotting without alignment.\n');
%     end
% 
%     % ---- Compute global x range across all valid runs and channels ----
%     % Done before plotting so xlim can be set once cleanly after all traces.
%     x_max = 0;
%     for r = valid_idx
%         tr = run_list(r).traces;
%         for yi = 1:numel(pd.y_channels)
%             yf = sanitise_fn(pd.y_channels{yi});
%             if ~isfield(tr, yf) || isempty(tr.(yf)), continue; end
%             d = tr.(yf)(1).dist(:);
%             if ~isempty(d)
%                 x_max = max(x_max, max(d) + offsets_m(r));
%             end
%         end
%     end
% 
%     % ---- Plot each trace on its native axis + shift ----
%     leg_h = []; leg_l = {}; leg_seen = {};
% 
%     for r = valid_idx
%         entry = run_list(r);
%         col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
%         tr    = entry.traces;
%         for yi = 1:numel(pd.y_channels)
%             yf = sanitise_fn(pd.y_channels{yi});
%             if ~isfield(tr, yf) || isempty(tr.(yf)), continue; end
%             d_raw = tr.(yf)(1).dist(:);
%             v_raw = tr.(yf)(1).data(:);
%             if isempty(d_raw) || isempty(v_raw), continue; end
%             h = plot(ax, d_raw + offsets_m(r), v_raw, '-', 'Color', col, 'LineWidth', lw);
%             lbl = entry.driver;
%             if ~any(strcmp(leg_seen, lbl))
%                 leg_h(end+1) = h; %#ok
%                 lap_num_str = '';
%                 if isfield(tr, 'lap_numbers') && numel(tr.lap_numbers) >= 1
%                     lap_num_str = sprintf('Lap %d  |  ', tr.lap_numbers(1));
%                 end
%                 lap_time_str = '';
%                 if isfield(tr, 'lap_times') && numel(tr.lap_times) >= 1
%                     lap_time_str = sprintf('  [%s%.3fs]', lap_num_str, tr.lap_times(1));
%                 end
%                 if offsets_m(r) ~= 0
%                     leg_l{end+1} = sprintf('%s%s  [%+.1fm]', lbl, lap_time_str, offsets_m(r)); %#ok
%                 else
%                     leg_l{end+1} = sprintf('%s%s', lbl, lap_time_str); %#ok
%                 end
%                 leg_seen{end+1} = lbl; %#ok
%             end
%         end
%     end
% 
%     % ---- Mark alignment window ----
%     if ~isempty(align_win)
%         xline(ax, align_win(1), '--k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
%         xline(ax, align_win(2), '--k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
%     end
% 
%     % ---- Axis labels, legend, xlim ----
%     if x_max > 0
%         xlim(ax, [0, x_max]);
%     end
%     xlabel(ax, 'Distance (m)', 'FontSize', fs, 'Interpreter', 'none');
%     ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter', 'none');
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% 
% function y_out = align_interp(d_raw, v_raw, dist_vec)
% % Resample v_raw (already on its own distance axis d_raw) onto dist_vec.
%     y_out = [];
%     n_min = min(numel(d_raw), numel(v_raw));
%     if n_min < 2, return; end
%     d = d_raw(1:n_min);
%     v = v_raw(1:n_min);
%     mono = [true; diff(d) > 0];
%     d = d(mono); v = v(mono);
%     if numel(d) < 2, return; end
%     dq    = min(max(dist_vec, d(1)), d(end));
%     y_out = interp1(d, v, dq, 'linear');
% end
% 
% function field = local_find_field(ch_struct, name)
%     san    = regexprep(name, '[^a-zA-Z0-9_]', '_');
%     fnames = fieldnames(ch_struct);
%     field  = '';
%     for i  = 1:numel(fnames)
%         if strcmpi(fnames{i}, name) || strcmpi(fnames{i}, san)
%             field = fnames{i}; return;
%         end
%     end
% end
% 
% function [locs, prom] = local_peaks_simple(sig, min_prom)
% % Toolbox-free peak finder — returns indices and prominences of local maxima.
% % min_prom: minimum prominence threshold (default 0 = return all peaks)
%     if nargin < 2, min_prom = 0; end
%     n    = numel(sig);
%     locs = []; prom = [];
%     if n < 3, return; end
%     is_pk = false(n,1);
%     for k = 2:n-1
%         if sig(k) > sig(k-1) && sig(k) > sig(k+1), is_pk(k) = true; end
%     end
%     cands = find(is_pk);
%     if isempty(cands), return; end
%     p = zeros(numel(cands),1);
%     sv = sig(cands);
%     for j = 1:numel(cands)
%         k    = cands(j);
%         pkv  = sig(k);
%         tl   = cands(sv >= pkv & (1:numel(cands))' < j);
%         tr   = cands(sv >= pkv & (1:numel(cands))' > j);
%         lb   = min(sig(1:k));           if ~isempty(tl), lb = min(sig(tl(end):k)); end
%         rb   = min(sig(k:n));           if ~isempty(tr), rb = min(sig(k:tr(1)));   end
%         p(j) = pkv - max(lb, rb);
%     end
%     % Apply minimum prominence filter
%     keep  = p >= min_prom;
%     locs  = cands(keep);
%     prom  = p(keep);
% end
% 
% 
% 
% function fig = make_align(run_list, pd, colour_cfg, driver_map, opts, ax_in)
%     if nargin < 6, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs  = get_opt(opts, 'font_size', 11);
%     lw  = 2.0;
% 
%     % --- Alignment params from pd ---
%     % x_lim doubles as the alignment window here
%     align_window     = [];
%     if isfield(pd, 'align_window') && numel(pd.align_window) == 2 && all(isfinite(pd.align_window))
%         align_window = pd.align_window(:)';
%     end
% 
%     peak_min_prom    = get_opt(opts, 'align_peak_min_prom',  2);
%     peak_min_sep_m   = get_opt(opts, 'align_peak_min_sep_m', 10);
%     max_offset_m     = get_opt(opts, 'align_max_offset_m',   60);
%     dist_res         = get_opt(opts, 'align_dist_res',        1);   % m
% 
%     align_ch = '';
%     if isfield(pd, 'align_channel') && ~isempty(pd.align_channel)
%         align_ch = pd.align_channel;
%     end
% 
%     leg_h = []; leg_l = {}; leg_seen = {};
% 
%     % ------------------------------------------------------------------ %
%     %  Pass 1: collect best-lap data + compute alignment offsets
%     % ------------------------------------------------------------------ %
%     n_runs      = numel(run_list);
%     dist_grids  = cell(n_runs, 1);   % resampled distance axis per car
%     ch_data     = cell(n_runs, numel(pd.y_channels));  % channel data on dist grid
%     align_data  = cell(n_runs, 1);   % alignment channel on dist grid
%     offsets_m   = zeros(n_runs, 1);
%     labels      = cell(n_runs, 1);
%     colours     = cell(n_runs, 1);
% 
%     common_len = Inf;
% 
%     for r = 1:n_runs
%         entry = run_list(r);
% 
%         % ---- get best lap channels ----
%         if strcmp(entry.mode, 'stream')
%             tr = entry.traces;
%             if isempty(tr) || ~isstruct(tr) || tr.n_traces == 0, continue; end
% 
%             % pick best lap index
%             valid_k = find(tr.lap_numbers >= -1 & tr.lap_numbers ~= 0 & isfinite(tr.lap_times));
%             if isempty(valid_k), valid_k = 1:tr.n_traces; end
%             [~, rel_best] = min(tr.lap_times(valid_k));
%             best_k        = valid_k(rel_best);
% 
%             % Build distance from stored dist vector in first y-channel trace
%             y0_field = sanitise_fn(pd.y_channels{1});
%             if ~isfield(tr, y0_field), continue; end
%             d_raw = tr.(y0_field)(best_k).dist(:);
%             if isempty(d_raw), continue; end
% 
%             % Build common dist grid for this car
%             common_len = min(common_len, d_raw(end));
%             dist_grids{r} = d_raw;
% 
%             % Store y-channel data
%             for yi = 1:numel(pd.y_channels)
%                 yf = sanitise_fn(pd.y_channels{yi});
%                 if isfield(tr, yf)
%                     ch_data{r, yi} = tr.(yf)(best_k).data(:);
%                 end
%             end
% 
%             % Store alignment channel data
%             if ~isempty(align_ch)
%                 af = sanitise_fn(align_ch);
%                 if isfield(tr, af)
%                     align_data{r} = tr.(af)(best_k).data(:);
%                 end
%             end
% 
%         else
%             % bulk mode
%             laps = entry.laps;
%             if isempty(laps), continue; end
%             lap_times = [laps.lap_time];
%             [~, best] = min(lap_times);
% 
%             ch_names_b = fieldnames(laps(best).channels);
%             if isempty(ch_names_b) || ~isfield(laps(best).channels.(ch_names_b{1}), 'dist')
%                 fprintf('  [WARN] .dist not found for %s\n', entry.driver);
%                 continue;
%             end
%             ref_ch = laps(best).channels.(ch_names_b{1});
%             d_raw  = ref_ch.dist(:);
%             common_len    = min(common_len, d_raw(end));
%             dist_grids{r} = d_raw;
% 
%             for yi = 1:numel(pd.y_channels)
%                 yf = find_ch_field(laps(best).channels, pd.y_channels{yi});
%                 if ~isempty(yf)
%                     ch_data{r, yi} = laps(best).channels.(yf).data(:);
%                 end
%             end
% 
%             if ~isempty(align_ch)
%                 af = find_ch_field(laps(best).channels, align_ch);
%                 if ~isempty(af)
%                     align_data{r} = laps(best).channels.(af).data(:);
%                 end
%             end
%         end
% 
%         labels{r}  = build_label(entry, pd, 1, driver_map);
%         colours{r} = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  Pass 2: resample everything onto a common 1m grid, compute offsets
%     % ------------------------------------------------------------------ %
%     if isinf(common_len) || common_len <= 0
%         warning('timeseries_align: no valid data found.'); return;
%     end
% 
%     dist_vec  = (0 : dist_res : common_len)';
%     n_pts     = numel(dist_vec);
% 
%     align_on_grid = cell(n_runs, 1);
%     ch_on_grid    = cell(n_runs, numel(pd.y_channels));
% 
%     for r = 1:n_runs
%         if isempty(dist_grids{r}), continue; end
%         d_raw = dist_grids{r};
% 
%         % resample alignment channel
%         if ~isempty(align_data{r}) && ~isempty(align_ch)
%             a_vals = align_data{r};
%             n_min  = min(numel(d_raw), numel(a_vals));
%             d_r    = d_raw(1:n_min);
%             a_r    = a_vals(1:n_min);
%             mono   = [true; diff(d_r) > 0];
%             d_r    = d_r(mono); a_r = a_r(mono);
%             dq     = min(max(dist_vec, d_r(1)), d_r(end));
%             align_on_grid{r} = interp1(d_r, a_r, dq, 'linear');
%         end
% 
%         % resample y channels
%         for yi = 1:numel(pd.y_channels)
%             if isempty(ch_data{r, yi}), continue; end
%             y_vals = ch_data{r, yi};
%             n_min  = min(numel(d_raw), numel(y_vals));
%             d_r    = d_raw(1:n_min);
%             y_r    = y_vals(1:n_min);
%             mono   = [true; diff(d_r) > 0];
%             d_r    = d_r(mono); y_r = y_r(mono);
%             dq     = min(max(dist_vec, d_r(1)), d_r(end));
%             ch_on_grid{r, yi} = interp1(d_r, y_r, dq, 'linear');
%         end
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  Compute peak-based offsets (alignTrack 'peaks' method)
%     % ------------------------------------------------------------------ %
%     peak_min_sep_samples = max(1, round(peak_min_sep_m / dist_res));
%     peak_dists = NaN(n_runs, 1);
% 
%     if ~isempty(align_ch) && ~isempty(align_window)
%         win_mask = dist_vec >= align_window(1) & dist_vec <= align_window(2);
%         win_dist = dist_vec(win_mask);
%         if sum(win_mask) >= 5
%             ref_r = [];
%             for r = 1:n_runs
%                 if ~isempty(align_on_grid{r})
%                     ref_r = r; break;
%                 end
%             end
% 
%             for r = 1:n_runs
%                 if isempty(align_on_grid{r}), continue; end
%                 sig = align_on_grid{r}(win_mask);
%                 [locs, prom] = align_local_peaks(sig, peak_min_sep_samples, peak_min_prom);
%                 if isempty(locs)
%                     [~, locs] = max(sig);
%                     prom      = 0;
%                     warning('timeseries_align: car %d no peak met prominence — using global max.', r);
%                 end
%                 [~, best_pk]  = max(prom);
%                 peak_dists(r) = win_dist(locs(best_pk));
%                 fprintf('  [align] %s: peak at %.1fm\n', labels{r}, peak_dists(r));
%             end
% 
%             if ~isnan(peak_dists(ref_r))
%                 for r = 1:n_runs
%                     if r == ref_r || isnan(peak_dists(r)), continue; end
%                     off = peak_dists(ref_r) - peak_dists(r);
%                     if abs(off) > max_offset_m
%                         warning('timeseries_align: %s offset %.1fm capped at %.0fm.', labels{r}, off, max_offset_m);
%                         off = sign(off) * max_offset_m;
%                     end
%                     offsets_m(r) = off;
%                     fprintf('  [align] %s offset: %+.1fm\n', labels{r}, off);
%                 end
%             end
%         else
%             warning('timeseries_align: alignment window too small (%d pts) — no alignment applied.', sum(win_mask));
%         end
%     else
%         if isempty(align_ch)
%             fprintf('  [timeseries_align] No yAxis2 channel — plotting without alignment.\n');
%         else
%             fprintf('  [timeseries_align] No alignWindow set — plotting without alignment.\n');
%         end
%     end
% 
%     % ------------------------------------------------------------------ %
%     %  Pass 3: Plot with offset applied to x-axis
%     % ------------------------------------------------------------------ %
%     for r = 1:n_runs
%         if isempty(labels{r}), continue; end
%         col = colours{r};
%         dv  = dist_vec + offsets_m(r);
% 
%         for yi = 1:numel(pd.y_channels)
%             if isempty(ch_on_grid{r, yi}), continue; end
%             h = plot(ax, dv, ch_on_grid{r, yi}, '-', 'Color', col, 'LineWidth', lw);
% 
%             lbl = labels{r};
%             if ~any(strcmp(leg_seen, lbl))
%                 leg_h(end+1)    = h; %#ok
%                 if offsets_m(r) ~= 0
%                     leg_l{end+1} = sprintf('%s  [%+.1fm]', lbl, offsets_m(r)); %#ok
%                 else
%                     leg_l{end+1} = lbl; %#ok
%                 end
%                 leg_seen{end+1} = lbl; %#ok
%             end
%         end
%     end
% 
%     % Mark alignment window
%     if ~isempty(align_window)
%         xline(ax, align_window(1), '--k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
%         xline(ax, align_window(2), '--k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
%     end
% 
%     xlabel(ax, 'Distance (m)', 'FontSize', fs, 'Interpreter', 'none');
%     ylabel(ax, strjoin(pd.y_channels, ' / '), 'FontSize', fs, 'Interpreter', 'none');
%     apply_legend(ax, leg_h, leg_l, opts);
% end
% 
% 
% % ======================================================================= %
% %  LOCAL PEAK FINDER (self-contained copy — no toolbox needed)
% %  Identical logic to alignTrack.m's local_peaks
% % ======================================================================= %
% function [locs, prom] = align_local_peaks(sig, min_sep, min_prom)
%     n    = numel(sig);
%     locs = []; prom = [];
%     if n < 3, return; end
% 
%     is_peak = false(n, 1);
%     for k = 2:n-1
%         if sig(k) > sig(k-1) && sig(k) > sig(k+1)
%             is_peak(k) = true;
%         end
%     end
%     cands = find(is_peak);
%     if isempty(cands), return; end
% 
%     sig_cands = sig(cands);
%     n_cands   = numel(cands);
%     p         = zeros(n_cands, 1);
% 
%     for j = 1:n_cands
%         k    = cands(j);
%         pk_v = sig(k);
%         taller_left = cands(1:j-1);
%         taller_left = taller_left(sig_cands(1:j-1) >= pk_v);
%         if isempty(taller_left), left_base = min(sig(1:k));
%         else,                    left_base = min(sig(taller_left(end):k)); end
% 
%         taller_right = cands(j+1:end);
%         taller_right = taller_right(sig_cands(j+1:end) >= pk_v);
%         if isempty(taller_right), right_base = min(sig(k:n));
%         else,                     right_base = min(sig(k:taller_right(1))); end
% 
%         p(j) = pk_v - max(left_base, right_base);
%     end
% 
%     keep  = p >= min_prom;
%     cands = cands(keep);
%     p     = p(keep);
%     if isempty(cands), return; end
% 
%     [~, sort_idx] = sort(p, 'descend');
%     kept = false(numel(cands), 1);
%     for j = 1:numel(sort_idx)
%         idx = sort_idx(j);
%         if ~any(kept & abs(cands - cands(idx)) < min_sep)
%             kept(idx) = true;
%         end
%     end
%     locs = sort(cands(kept));
%     prom = p(kept);
% end
% 
% % ======================================================================= %
% %  DISTRIBUTION DATA HELPER
% % ======================================================================= %
% function vals = get_dist_vals(entry, y_field, math_fn)
%     agg_fns = {'max','min','mean','variance','var', ...
%                'mean non zero','min non zero','max non zero', ...
%                'median non zero','std non zero'};
%     if ismember(lower(math_fn), agg_fns)
%         vals = local_apply_math(entry.stats.(y_field), math_fn);
%         vals = vals(isfinite(vals));
%     else
%         if isempty(entry.laps)
%             warning('get_dist_vals: math_fn "%s" requires raw laps (bulk mode only).', math_fn);
%             vals = []; return;
%         end
%         vals = [];
%         for k = 1:numel(entry.laps)
%             ch_field = find_ch_field(entry.laps(k).channels, y_field);
%             if isempty(ch_field), continue; end
%             ch = entry.laps(k).channels.(ch_field);
%             t  = ch.time;  dt = median(diff(t));
%             if isnan(dt) || dt <= 0, dt = 1; end
%             v = local_apply_math_sample(ch.data, math_fn, dt);
%             vals = [vals; v(:)]; %#ok
%         end
%         vals = vals(isfinite(vals));
%     end
% end
% 
% 
% % ======================================================================= %
% %  BOXPLOT COLOURING
% % ======================================================================= %
% function colour_boxplot(bp, colours)
%     boxes = findobj(bp,'Tag','Box');
%     meds  = findobj(bp,'Tag','Median');
%     n = numel(boxes);
%     for i = 1:n
%         j = n - i + 1;
%         if j > size(colours,1), continue; end
%         col = colours(j,:);
%         patch(get(boxes(i),'XData'), get(boxes(i),'YData'), col, ...
%             'FaceAlpha',0.75,'EdgeColor',col*0.7,'LineWidth',1.2);
%         set(meds(i),'Color',col*0.5,'LineWidth',2);
%     end
% end
% 
% 
% % ======================================================================= %
% %  SHAPE KEY
% % ======================================================================= %
% function add_shape_key(fig, y_channels, SHAPES, fs)
%     names = {'Circle','Square','Triangle','Diamond'};
%     lines = {'Shapes:'};
%     for i = 1:min(numel(y_channels), numel(SHAPES))
%         lines{end+1} = sprintf('  %s = %s', names{i}, y_channels{i}); %#ok
%     end
%     annotation(fig,'textbox','Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
%         'String',lines,'FontSize',fs-2,'FontName','Arial', ...
%         'EdgeColor',[0.7 0.7 0.7],'BackgroundColor','white', ...
%         'FitBoxToText','on','Interpreter','none');
% end
% 
% 
% % ======================================================================= %
% %  LABEL BUILDER
% % ======================================================================= %
% function lbl = build_label(entry, pd, yi, driver_map)
% % Legend label is driven by pd.differentiator if set to a label mode,
% % otherwise falls back to pd.colour_mode. This allows colour and legend
% % to be controlled independently from the Excel sheet.
% %
% % Label modes: 'number'       -> #18
% %              'driver'/'tla' -> DRV_TLA (via driver_map) or full name fallback
% %              'manufacturer' -> manufacturer name
% %              'team'         -> team name
% % If differentiator is 'shapes' or empty, colour_mode drives the label.
% 
%     if nargin < 4, driver_map = []; end
% 
%     % Determine which field drives the label
%     diff_lower  = lower(strtrim(char(string(pd.differentiator))));
%     label_modes = {'number','driver','tla','manufacturer','team'};
%     if ismember(diff_lower, label_modes)
%         label_mode = diff_lower;
%     else
%         label_mode = lower(pd.colour_mode);
%     end
% 
%     switch label_mode
%         case 'manufacturer'
%             base = entry.manufacturer;
%             if isempty(base), base = entry.driver; end
%         case 'team'
%             base = entry.team;
%             if isempty(base), base = entry.driver; end
%         case 'number'
%             car = strtrim(char(string(entry.car)));
%             if isempty(car), car = entry.driver; end
%             base = sprintf('#%s', car);
%         otherwise   % 'driver', 'tla', or anything else — resolve TLA
%             base = resolve_tla(entry.driver, driver_map);
%     end
% 
%     if numel(pd.y_channels) > 1
%         lbl = sprintf('%s  [%s]', base, pd.y_channels{yi});
%     else
%         lbl = base;
%     end
% end
% 
% 
% % ======================================================================= %
% %  UTILITIES
% % ======================================================================= %
% function tf = is_keyword(str)
%     tf = is_keyword_lap(str) || contains(lower(str),'falling');
% end
% 
% function tf = is_keyword_lap(str)
%     tf = any(strcmpi(str, {'Lap Number','Lap_Number','lap'}));
% end
% 
% function name = sanitise_fn(ch)
%     name = regexprep(strtrim(ch), '[^a-zA-Z0-9]', '_');
%     if ~isempty(name) && isstrprop(name(1),'digit'), name = ['ch_', name]; end
% end
% 
% function field = find_ch_field(channels, name)
%     if isfield(channels, name), field = name; return; end
%     san = regexprep(name, '[^a-zA-Z0-9_]', '_');
%     if isfield(channels, san), field = san; return; end
%     ch_names = fieldnames(channels);
%     for i = 1:numel(ch_names)
%         if strcmpi(ch_names{i}, name) || strcmpi(ch_names{i}, san)
%             field = ch_names{i}; return;
%         end
%     end
%     field = '';
% end
% 
% function v = get_opt(s, f, default)
%     if isfield(s,f) && ~isempty(s.(f)), v = s.(f);
%     else,                                v = default; end
% end
% 
% 
% % ======================================================================= %
% %  MATH HELPERS
% % ======================================================================= %
% function vals = local_apply_math(stat, math_fn)
%     switch lower(strtrim(math_fn))
%         case 'max',                vals = stat.max;
%         case 'min',                vals = stat.min;
%         case {'mean','average'},   vals = stat.mean;
%         case {'variance','var'},   vals = stat.var;
%         case {'derivative','diff'},vals = gradient(stat.max);
%         case {'integral','int'},   vals = cumtrapz(stat.max);
%         case 'mean non zero'
%             if isfield(stat,'mean_non_zero'), vals = stat.mean_non_zero;
%             else, vals = stat.mean; warning('local_apply_math: mean_non_zero not in stats.'); end
%         case 'min non zero'
%             if isfield(stat,'min_non_zero'),  vals = stat.min_non_zero;
%             else, vals = stat.min;  warning('local_apply_math: min_non_zero not in stats.');  end
%         case 'max non zero'
%             if isfield(stat,'max_non_zero'),  vals = stat.max_non_zero;
%             else, vals = stat.max;  warning('local_apply_math: max_non_zero not in stats.');  end
%         case 'median non zero'
%             if isfield(stat,'median_non_zero'), vals = stat.median_non_zero;
%             else, vals = stat.mean; warning('local_apply_math: median_non_zero not in stats.'); end
%         case 'std non zero'
%             if isfield(stat,'std_non_zero'),  vals = stat.std_non_zero;
%             else, vals = stat.max;  warning('local_apply_math: std_non_zero not in stats.');  end
%         otherwise
%             warning('local_apply_math: unknown "%s" — using max.', math_fn);
%             vals = stat.max;
%     end
% end
% 
% function result = local_apply_math_sample(data, math_fn, dt)
%     if nargin < 3, dt = 1; end
%     d = data(:);  d_fin = d(isfinite(d));
%     if isempty(d_fin), result = NaN; return; end
%     switch lower(math_fn)
%         case 'max',                result = max(d_fin);
%         case 'min',                result = min(d_fin);
%         case {'mean','average'},   result = mean(d_fin);
%         case {'variance','var'},   result = var(d_fin);
%         case {'derivative','diff'},result = gradient(d, dt);
%         case {'integral','int'},   result = cumtrapz(d) * dt;
%         otherwise
%             warning('local_apply_math_sample: unknown "%s".', math_fn); result = NaN;
%     end
% end
% 
% function col = local_driver_colour(driver_map, name)
%     col = [0.55 0.55 0.55];
%     if isempty(driver_map) || ~isstruct(driver_map), return; end
%     name_lower = lower(strtrim(name));
%     name_strip = regexprep(name_lower, '[^a-z0-9]', '');
%     keys = fieldnames(driver_map);
%     for k = 1:numel(keys)
%         entry = driver_map.(keys{k});
%         for a = 1:numel(entry.aliases)
%             alias_raw   = entry.aliases{a};
%             alias_strip = regexprep(alias_raw, '[^a-z0-9]', '');
%             if strcmp(name_lower, alias_raw) || strcmp(name_strip, alias_strip)
%                 col = entry.colour; return;
%             end
%         end
%     end
% end
% 
% % function car = resolve_car_number(driver_name, driver_map, fallback)
% %     car = fallback;
% %     if isempty(driver_map) || ~isstruct(driver_map), return; end
% %     name_lower = lower(strtrim(driver_name));
% %     keys = fieldnames(driver_map);
% %     for k = 1:numel(keys)
% %         entry = driver_map.(keys{k});
% %         if any(strcmp(entry.aliases, name_lower))
% %             if isfield(entry, 'num') && ~isempty(entry.num), car = entry.num; end
% %             return;
% %         end
% %     end
% % end
% function car = resolve_car_number(driver_name, driver_map, fallback)
%     car = fallback;
%     if isempty(driver_map) || ~isstruct(driver_map), return; end
%     name_lower  = lower(strtrim(driver_name));
%     name_strip  = regexprep(name_lower, '[^a-z0-9]', '');
%     keys = fieldnames(driver_map);
%     for k = 1:numel(keys)
%         entry = driver_map.(keys{k});
%         for a = 1:numel(entry.aliases)
%             alias_strip = regexprep(entry.aliases{a}, '[^a-z0-9]', '');
%             if strcmp(name_lower, entry.aliases{a}) || strcmp(name_strip, alias_strip)
%                 if isfield(entry, 'num') && ~isempty(entry.num)
%                     car = entry.num;
%                 end
%                 return;
%             end
%         end
%     end
%     % No match found — using MoTeC fallback
%     fprintf('  [WARN] resolve_car_number: no alias match for "%s" — using fallback "%s"\n', ...
%         driver_name, fallback);
% end
% 
% % ======================================================================= %
% %  ROBUST DISTANCE INTERPOLATION
% % ======================================================================= %
% function y_out = interp_onto_dist(t_dist, d_raw, t_y, y_raw, d_grid)
%     n_pts = numel(d_grid);
%     y_out = NaN(n_pts, 1);
%     d_raw=d_raw(:); t_dist=t_dist(:); y_raw=y_raw(:); t_y=t_y(:);
%     ok_d = isfinite(d_raw) & isfinite(t_dist);
%     ok_y = isfinite(y_raw) & isfinite(t_y);
%     if sum(ok_d)<2 || sum(ok_y)<2, return; end
%     d_raw=d_raw(ok_d); t_dist=t_dist(ok_d);
%     y_raw=y_raw(ok_y); t_y=t_y(ok_y);
%     mono=[true; diff(d_raw)>0];
%     d_raw=d_raw(mono); t_dist=t_dist(mono);
%     if numel(d_raw)<2, return; end
%     t_clip=min(max(t_y,t_dist(1)),t_dist(end));
%     d_at_y=interp1(t_dist,d_raw,t_clip,'linear');
%     mono2=[true; diff(d_at_y)>0];
%     d_at_y=d_at_y(mono2); y_raw=y_raw(mono2);
%     if numel(d_at_y)<2, return; end
%     d_q=min(max(d_grid,d_at_y(1)),d_at_y(end));
%     y_interp=interp1(d_at_y,y_raw,d_q,'linear');
%     y_interp(d_grid<d_at_y(1)|d_grid>d_at_y(end))=NaN;
%     y_out=y_interp(:);
% end
% 
% % ======================================================================= %
% %  BIG SCATTER
% % ======================================================================= %
% function fig = make_big_scatter(run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in)
% % MAKE_BIG_SCATTER  Multi-session scatter with continuous lap-number x axis.
% %
% % Sessions are laid out left-to-right in the order they appear in run_list
% % (which reflects SESSION_FILTER order). A dashed vertical separator is
% % drawn at max_laps_in_session + 1 between sessions. Session name and venue
% % are drawn as centred labels below the x axis. X ticks are thinned
% % dynamically so they never become crowded (minimum every 3 laps).
% 
%     if nargin < 7, ax_in = []; end
%     [fig, ax] = new_fig(pd, opts, ax_in);
%     fs    = get_opt(opts, 'font_size', 11);
%     venue = get_opt(opts, 'venue',     '');
% 
%     y_ch    = pd.y_channels{1};
%     y_field = sanitise_fn(y_ch);
% 
%     % ------------------------------------------------------------------
%     %  Pass 1 — determine session order and max laps per session
%     % ------------------------------------------------------------------
%     % Preserve the order sessions appear in run_list (= SESSION_FILTER order)
%     session_order = {};
%     for r = 1:numel(run_list)
%         sess = run_list(r).session;
%         if ~any(strcmp(session_order, sess))
%             session_order{end+1} = sess; %#ok
%         end
%     end
%     n_sessions = numel(session_order);
% 
%     % Max lap number per session across all runs
%     sess_max_lap = zeros(1, n_sessions);
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         if ~isfield(entry.stats, y_field), continue; end
%         si = find(strcmp(session_order, entry.session), 1);
%         if isempty(si), continue; end
%         lap_nums = entry.stats.(y_field).lap_numbers;
%         valid    = isfinite(local_apply_math(entry.stats.(y_field), pd.math_fn));
%         lap_nums = lap_nums(valid);
%         if ~isempty(lap_nums)
%             sess_max_lap(si) = max(sess_max_lap(si), max(lap_nums));
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  Compute global x offset for each session
%     %  Session N starts at: sum of (max_laps + 2) for all previous sessions
%     %  The +2 creates a gap of 2 laps for the separator
%     % ------------------------------------------------------------------
%     sess_offset = zeros(1, n_sessions);
%     for si = 2:n_sessions
%         sess_offset(si) = sess_offset(si-1) + sess_max_lap(si-1) + 2;
%     end
% 
%     total_laps = sess_offset(end) + sess_max_lap(end);
% 
%     % ------------------------------------------------------------------
%     %  Pass 2 — plot points
%     % ------------------------------------------------------------------
%     leg_h = []; leg_l = {}; leg_seen = {};
% 
%     for r = 1:numel(run_list)
%         entry = run_list(r);
%         if ~isfield(entry.stats, y_field), continue; end
% 
%         si = find(strcmp(session_order, entry.session), 1);
%         if isempty(si), continue; end
% 
%         col    = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
%         marker = 'o';
%         if strcmpi(pd.differentiator, 'shapes') && numel(SHAPES) >= 1
%             marker = SHAPES{mod(r-1, numel(SHAPES)) + 1};
%         end
% 
%         y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
%         lap_nums = entry.stats.(y_field).lap_numbers;
%         valid    = isfinite(y_vals);
%         y_vals   = y_vals(valid);
%         lap_nums = lap_nums(valid);
%         if isempty(y_vals), continue; end
% 
%         % Shift lap numbers to global x axis
%         x_vals = lap_nums + sess_offset(si);
% 
%         h = scatter(ax, x_vals, y_vals, 36, col, marker, 'filled', ...
%             'MarkerEdgeColor', col * 0.7, 'MarkerFaceAlpha', 0.75);
% 
%         lbl = build_label(entry, pd, 1, driver_map);
%         if ~any(strcmp(leg_seen, lbl))
%             leg_h(end+1) = h; leg_l{end+1} = lbl; leg_seen{end+1} = lbl; %#ok
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  Session separators — dashed vertical lines
%     % ------------------------------------------------------------------
%     y_lims = ylim(ax);
%     for si = 1:n_sessions - 1
%         x_sep = sess_offset(si) + sess_max_lap(si) + 1;
%         plot(ax, [x_sep x_sep], y_lims, '--', ...
%             'Color', [0.5 0.5 0.5], 'LineWidth', 1.2);
%     end
% 
%     % ------------------------------------------------------------------
%     %  X axis ticks — thin dynamically, minimum every 3 laps
%     % ------------------------------------------------------------------
%     ax_pos   = get(ax, 'Position');
%     ax_width = ax_pos(3) * get(fig, 'Position') * [0;0;1;0];  % pixels
%     if ax_width <= 0, ax_width = 900; end                      % fallback
% 
%     target_ticks  = max(5, round(ax_width / 55));   % ~55px per tick
%     raw_step      = total_laps / target_ticks;
%     step          = max(3, ceil(raw_step / 3) * 3); % round up to multiple of 3
% 
%     tick_vals = 1 : step : total_laps;
%     % Filter out ticks that fall in separator gaps
%     in_gap = false(size(tick_vals));
%     for si = 1:n_sessions - 1
%         gap_lo = sess_offset(si) + sess_max_lap(si) + 0.5;
%         gap_hi = sess_offset(si) + sess_max_lap(si) + 1.5;
%         in_gap = in_gap | (tick_vals >= gap_lo & tick_vals <= gap_hi);
%     end
%     tick_vals = tick_vals(~in_gap);
% 
%     % Convert global x back to local lap numbers for tick labels
%     tick_lbls = cell(size(tick_vals));
%     for k = 1:numel(tick_vals)
%         xg = tick_vals(k);
%         % Find which session this tick belongs to
%         for si = n_sessions : -1 : 1
%             if xg >= sess_offset(si)
%                 local_lap = xg - sess_offset(si);
%                 tick_lbls{k} = num2str(round(local_lap));
%                 break;
%             end
%         end
%     end
% 
%     set(ax, 'XTick', tick_vals, 'XTickLabel', tick_lbls, ...
%         'XTickLabelRotation', 0);
%     xlim(ax, [0 total_laps + 2]);
% 
%     % ------------------------------------------------------------------
%     %  Layout: shrink axes to leave room for session labels + legend
%     % ------------------------------------------------------------------
%     % Strip allocation (normalised figure units, bottom to top):
%     %   LEG_STRIP   — legend box height (dynamic: scales with n_rows)
%     %   VENUE_STRIP — venue label row (SMP)
%     %   SESS_STRIP  — session label row height (RA1/RA2/RA3)
%     %   SESS_GAP    — white space between axes bottom and session label
%     ROW_H       = 0.045;   % normalised height per legend row
%     VENUE_STRIP = 0.04;
%     SESS_STRIP  = 0.04;
%     SESS_GAP    = 0.025;
% 
%     % Calculate legend rows now so LEG_STRIP is sized correctly
%     n_leg_items  = numel(leg_h);
%     n_leg_cols   = min(8, max(1, n_leg_items));
%     n_leg_rows   = ceil(n_leg_items / n_leg_cols);
%     LEG_STRIP    = max(ROW_H, n_leg_rows * ROW_H + 0.01);  % +0.01 for border padding
%     TOTAL_STRIP  = LEG_STRIP + VENUE_STRIP + SESS_STRIP + SESS_GAP;
% 
%     ax_pos = get(ax, 'Position');
%     new_bottom = ax_pos(2) + TOTAL_STRIP;
%     new_height = ax_pos(4) - TOTAL_STRIP;
%     if new_height > 0.15
%         set(ax, 'Position', [ax_pos(1), new_bottom, ax_pos(3), new_height]);
%     end
% 
%     % Re-read after resize
%     ax_pos        = get(ax, 'Position');
%     ax_left_norm  = ax_pos(1);
%     ax_bot_norm   = ax_pos(2);
%     ax_width_norm = ax_pos(3);
%     ax_right_norm = ax_left_norm + ax_width_norm;
% 
%     xl      = xlim(ax);
%     x_range = xl(2) - xl(1);
% 
%     % ------------------------------------------------------------------
%     %  Session name labels (RA1/RA2/RA3) — row just below axes
%     % ------------------------------------------------------------------
%     sess_row_y = ax_bot_norm - SESS_GAP - SESS_STRIP;
% 
%     for si = 1:n_sessions
%         x_centre_data = sess_offset(si) + sess_max_lap(si) / 2;
%         x_norm = ax_left_norm + ax_width_norm * (x_centre_data - xl(1)) / x_range;
% 
%         annotation(fig, 'textbox', [x_norm - 0.08, sess_row_y, 0.16, SESS_STRIP], ...
%             'String',              session_order{si}, ...
%             'HorizontalAlignment', 'center', ...
%             'VerticalAlignment',   'middle', ...
%             'FontSize',            fs, ...
%             'FontWeight',          'bold', ...
%             'Color',               [0.2 0.2 0.2], ...
%             'EdgeColor',           'none', ...
%             'FitBoxToText',        'off');
%     end
% 
%     % ------------------------------------------------------------------
%     %  Venue labels (SMP) — row below session labels
%     % ------------------------------------------------------------------
%     if ~isempty(venue)
%         venue_row_y = sess_row_y - VENUE_STRIP;
%         for si = 1:n_sessions
%             x_centre_data = sess_offset(si) + sess_max_lap(si) / 2;
%             x_norm = ax_left_norm + ax_width_norm * (x_centre_data - xl(1)) / x_range;
% 
%             annotation(fig, 'textbox', [x_norm - 0.08, venue_row_y, 0.16, VENUE_STRIP], ...
%                 'String',              venue, ...
%                 'HorizontalAlignment', 'center', ...
%                 'VerticalAlignment',   'middle', ...
%                 'FontSize',            fs - 1, ...
%                 'Color',               [0.55 0.55 0.55], ...
%                 'EdgeColor',           'none', ...
%                 'FitBoxToText',        'off');
%         end
%     else
%         venue_row_y = sess_row_y;
%     end
% 
%     % ------------------------------------------------------------------
%     %  Horizontal legend box — below venue row, spanning axes width
%     % ------------------------------------------------------------------
%     % Turn off the default axes legend
%     legend(ax, 'off');
% 
%     if ~isempty(leg_h)
%         leg_box_y = venue_row_y - LEG_STRIP;
%         leg_box_h = LEG_STRIP;
% 
%         % Draw a light border box for the legend area
%         annotation(fig, 'rectangle', ...
%             [ax_left_norm, leg_box_y, ax_width_norm, leg_box_h], ...
%             'EdgeColor', [0.75 0.75 0.75], 'LineWidth', 0.8, ...
%             'FaceColor', [0.98 0.98 0.98]);
% 
%         % Use pre-calculated n_leg_cols / n_leg_rows from strip sizing
%         n_cols = n_leg_cols;
%         n_rows = n_leg_rows;
%         col_w  = ax_width_norm / n_cols;
%         row_h  = leg_box_h / n_rows;
%         dot_r     = 0.007;   % marker radius in normalised units
% 
%         for k = 1:n_leg_items
%             col_i = mod(k-1, n_cols);
%             row_i = floor((k-1) / n_cols);
% 
%             item_x = ax_left_norm + col_i * col_w;
%             item_y = leg_box_y + leg_box_h - (row_i + 0.5) * row_h;
% 
%             % Coloured dot
%             try
%                 ec = get(leg_h(k), 'CData');
%                 if isnumeric(ec) && numel(ec) == 3
%                     dot_col = ec;
%                 else
%                     dot_col = [0.4 0.4 0.4];
%                 end
%             catch
%                 dot_col = [0.4 0.4 0.4];
%             end
% 
%             annotation(fig, 'ellipse', ...
%                 [item_x + 0.005, item_y - dot_r, dot_r*2, dot_r*2], ...
%                 'Color', dot_col, 'FaceColor', dot_col, 'LineWidth', 0.5);
% 
%             % Label text
%             annotation(fig, 'textbox', ...
%                 [item_x + 0.022, item_y - row_h*0.4, col_w - 0.024, row_h*0.8], ...
%                 'String',              leg_l{k}, ...
%                 'HorizontalAlignment', 'left', ...
%                 'VerticalAlignment',   'middle', ...
%                 'FontSize',            max(fs - 2, 8), ...
%                 'Color',               [0.15 0.15 0.15], ...
%                 'EdgeColor',           'none', ...
%                 'FitBoxToText',        'off', ...
%                 'Interpreter',         'none');
%         end
%     end
% 
%     % ------------------------------------------------------------------
%     %  Axis labels and title
%     % ------------------------------------------------------------------
%     ylabel(ax, y_ch,   'FontSize', fs, 'Interpreter', 'none');
%     title(ax,  pd.name,'FontSize', fs, 'Interpreter', 'none');
%     set(ax, 'XLabel', text('String', ''));   % remove 'Lap' xlabel
%     apply_axis_limits(ax, pd);
% end
% 
% % ======================================================================= %
% %  DRV_TLA RESOLVER  (used by make_big_scatter)
% % ======================================================================= %
% function tla = resolve_tla(driver_name, driver_map)
% % Return the DRV_TLA for a driver, falling back to the full name if not found.
%     tla = driver_name;
%     if isempty(driver_map) || ~isstruct(driver_map) || isempty(driver_name)
%         return;
%     end
%     name_lower = lower(strtrim(strrep(driver_name, '_', ' ')));
%     keys = fieldnames(driver_map);
%     for k = 1:numel(keys)
%         entry = driver_map.(keys{k});
%         if isfield(entry, 'aliases') && any(strcmp(entry.aliases, name_lower))
%             if isfield(entry, 'tla') && ~isempty(entry.tla)
%                 tla = entry.tla;
%             end
%             return;
%         end
%     end
% end

function figs = smp_plot_from_config(SMP, plots, cfg, driver_map, opts)
% SMP_PLOT_FROM_CONFIG  Generate all plots defined in a plot config struct.
%
% Supports two data modes automatically:
%
%   Stream mode  — SMP struct came from smp_filter_cache().
%                  node.stats{r} and node.traces{r} are pre-compiled.
%
%   Bulk mode    — SMP struct came from smp_filter() / smp_load_teams.
%                  node.channels{r} contains raw channel data.
%
% New plot types added:
%   sessionlapwise  — per-car line, x = continuous session lap
%
% New post-render features (driven by smp_plot_config_load fields):
%   x_lim / y_lim           — axis limits from Excel '[lo, hi]'
%   highlight_outliers       — annotate outlier laps (manufacturer mode only)
%   outlier_method           — 'mad' or 'iqr'
%   outlier_threshold        — scalar multiplier

    % ------------------------------------------------------------------
    %  Defaults
    % ------------------------------------------------------------------
    if nargin < 4, driver_map = []; end
    if nargin < 5 || isempty(opts), opts = struct(); end

    min_lt     = get_opt(opts, 'min_lap_time',  85);
    max_lt     = get_opt(opts, 'max_lap_time',  115);
    n_laps_avg = get_opt(opts, 'n_laps_avg',    3);
    verbose    = get_opt(opts, 'verbose',        true);
    save_path  = get_opt(opts, 'save_path',      '');
    dist_ch    = get_opt(opts, 'dist_channel',   'Odometer');
    dist_npts  = get_opt(opts, 'dist_n_points',  1000);

    SHAPES = {'o','s','^','d'};

    if isfield(cfg, 'colours'), colour_cfg = cfg.colours;
    else,                       colour_cfg = cfg; end

    if verbose, fprintf('\n=== smp_plot_from_config ===\n'); end

    % ------------------------------------------------------------------
    %  Collect channel names needed across all plots
    % ------------------------------------------------------------------
    all_y = {};
    all_x = {};
    for p = 1:numel(plots)
        all_y = [all_y, plots(p).y_channels]; %#ok
        xa = plots(p).x_axis;
        if ~is_keyword(xa), all_x{end+1} = xa; end %#ok
    end
    stat_channels = unique([all_y, all_x]);

    % ------------------------------------------------------------------
    %  Build run_list
    % ------------------------------------------------------------------
    run_list = [];
    team_keys = fieldnames(SMP);

    for t = 1:numel(team_keys)
        tk   = team_keys{t};
        node = SMP.(tk);
        n_runs = height(node.meta);

        for r = 1:n_runs

            has_stats    = isfield(node, 'stats')    && numel(node.stats)    >= r && ~isempty(node.stats{r});
            has_channels = isfield(node, 'channels') && numel(node.channels) >= r && ~isempty(node.channels{r});

            if has_stats
                entry = build_entry_stream(node, r, tk, driver_map);
                if isempty(entry), continue; end
                if verbose
                    fprintf('  [stream] %-6s | %-22s | %-12s | %-10s | %d laps\n', ...
                        entry.car, entry.driver, entry.manufacturer, entry.session, entry.n_laps);
                end

            elseif has_channels
                entry = build_entry_bulk(node, r, tk, driver_map, ...
                            stat_channels, min_lt, max_lt, verbose);
                if isempty(entry), continue; end
                if verbose
                    fprintf('  [bulk]   %-6s | %-22s | %-12s | %-10s | %d laps\n', ...
                        entry.car, entry.driver, entry.manufacturer, entry.session, entry.n_laps);
                end

            else
                if verbose
                    fprintf('  [SKIP] %s run %d — no stats or channels available.\n', tk, r);
                end
                continue;
            end

            if isempty(run_list), run_list = entry;
            else,                 run_list(end+1) = entry; end %#ok
        end
    end

    if isempty(run_list)
        warning('smp_plot_from_config: no valid runs found.');
        figs = {};
        return;
    end
    fprintf('\n%d runs ready for plotting.\n\n', numel(run_list));

    % ------------------------------------------------------------------
    %  Pre-build figures with subplot layouts
    % ------------------------------------------------------------------
    fig_handles = containers.Map('KeyType','int32','ValueType','any');
    fig_axes    = containers.Map('KeyType','int32','ValueType','any');
    fig_layouts = containers.Map('KeyType','int32','ValueType','any');

    fw = get_opt(opts, 'fig_width',  1200);
    fh = get_opt(opts, 'fig_height', 650);

    for p = 1:numel(plots)
        pd = plots(p);
        if ~isfield(pd,'fig_num') || isnan(pd.fig_num), continue; end
        fn = int32(pd.fig_num);
        if ~isKey(fig_handles, fn)
            lay = pd.fig_layout;
            if isempty(lay),    lay = [1 1]; end
            if numel(lay) == 1, lay = [lay(1) 1]; end
            lay = lay(1:2);
            fig_layouts(fn) = lay;
            f = figure('Visible','off','Color','white','Position',[100 100 fw fh]);
            fig_handles(fn) = f;
            ax_all = gobjects(lay(1), lay(2));
            for ri = 1:lay(1)
                for ci = 1:lay(2)
                    ax_all(ri,ci) = subplot(lay(1), lay(2), (ri-1)*lay(2)+ci, 'Parent', f);
                end
            end
            fig_axes(fn) = ax_all;
        end
    end

    % ------------------------------------------------------------------
    %  Generate each plot
    % ------------------------------------------------------------------
    figs = cell(numel(plots), 1);

    for p = 1:numel(plots)
        pd = plots(p);
        if verbose
            fprintf('--- Plot %d: "%s"  [%s / %s / colour=%s]\n', ...
                p, pd.name, pd.type, pd.math_fn, pd.colour_mode);
        end

        try
            if isfield(pd, 'plot_filter') && ~isempty(pd.plot_filter)
                filter_groups = smp_parse_plot_filter(pd.plot_filter);
                plot_run_list = smp_apply_plot_filter(run_list, filter_groups);
            else
                plot_run_list = run_list;
            end

            if isempty(plot_run_list)
                warning('smp_plot_from_config: plot "%s" — no runs after filter.', pd.name);
                continue;
            end

            % Resolve axes handle
            ax_in = [];
            use_subplot = isfield(pd,'fig_num') && ~isnan(pd.fig_num) && ...
                          isfield(pd,'fig_pos')  && ~isempty(pd.fig_pos);
            fprintf('  [subplot] fig_num=%s  fig_pos=%s  use_subplot=%d\n', ...
                num2str(pd.fig_num), mat2str(pd.fig_pos), use_subplot);
            if use_subplot
                fn  = int32(pd.fig_num);
                pos = pd.fig_pos;
                if isKey(fig_axes, fn)
                    ax_grid = fig_axes(fn);
                    lay     = fig_layouts(fn);
                    ri = min(round(pos(1)), lay(1));
                    ci = min(round(pos(2)), lay(2));
                    ax_in = ax_grid(ri, ci);
                end
            end

            switch pd.type
                case 'scatter'
                    figs{p} = make_scatter(plot_run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in);
                case 'line'
                    figs{p} = make_line(plot_run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in);
                case 'boxplot'
                    figs{p} = make_boxplot(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
                case 'violin'
                    figs{p} = make_violin(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
                case 'histogram'
                    figs{p} = make_histogram(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
                case 'timeseries'
                    figs{p} = make_timeseries(plot_run_list, pd, colour_cfg, driver_map, opts, ...
                                              dist_ch, dist_npts, n_laps_avg, ax_in);
                case 'ranked_box'
                    figs{p} = make_ranked_box(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
                case 'lapwise_box'
                    figs{p} = make_lapwise_box(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
                case 'sessionlapwise'
                    figs{p} = make_session_lap_wise(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
                case 'timeseries_align'
                    figs{p} = make_timeseries_align(plot_run_list, pd, colour_cfg, driver_map, opts, ax_in);
                case 'psd'
%                     figs{p} = make_psd(plot_run_list, pd, colour_cfg, driver_map, opts);
                    [fig{p}, psd_stats] = make_psd(run_list, pd, colour_cfg, driver_map, opts, ax_in)
                case 'psd_scatter'
                    figs{p} = make_psd_scatter(plot_run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in);
                case 'big_scatter'
                    figs{p} = make_big_scatter(plot_run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in);
                otherwise
                    warning('smp_plot_from_config: plot type "%s" not supported.', pd.type);
            end

            % For subplot figures, figs{p} = parent figure
            if use_subplot && isKey(fig_handles, int32(pd.fig_num))
                figs{p} = fig_handles(int32(pd.fig_num));
            end

        catch ME
            fprintf('  [ERROR] plot "%s": %s\n%s\n', ...
                pd.name, ME.message, ME.getReport('basic'));
        end

        % ---- Post-processing: axis limits + outlier highlighting ----
        if ~isempty(figs{p})
            if ~strcmpi(pd.type, 'timeseries_align')
                % Pass ax_in directly for subplot plots so limits go to the
                % correct axes, not just the last axes in the parent figure.
                if use_subplot && ~isempty(ax_in)
                    apply_axis_limits(ax_in, pd);
                else
                    apply_axis_limits(figs{p}, pd);
                end
            end
            if isfield(pd,'highlight_outliers') && pd.highlight_outliers && ...
                    strcmpi(pd.colour_mode, 'manufacturer') && ...
                    ismember(pd.type, {'scatter','line','sessionlapwise'})
                draw_outlier_highlights(figs{p}, pd, plot_run_list, colour_cfg, driver_map, ax_in);
            end
        end

        if ~isempty(save_path) && ~isempty(figs{p})
            if ~use_subplot
                safe = regexprep(pd.name, '[^a-zA-Z0-9_\- ]', '');
                safe = strrep(strtrim(safe), ' ', '_');
                exportgraphics(figs{p}, fullfile(save_path, [safe '.png']), 'Resolution', 150);
            end
        end
    end
    % Save subplot figures
    if ~isempty(save_path)
        fn_keys = keys(fig_handles);
        for k = 1:numel(fn_keys)
            f = fig_handles(fn_keys{k});
            exportgraphics(f, fullfile(save_path, sprintf('figure_%d.png', fn_keys{k})), ...
                'Resolution', 150);
        end
    end
end


% ======================================================================= %
%  ENTRY BUILDERS
% ======================================================================= %
function entry = build_entry_stream(node, r, tk, driver_map)
    entry = [];
    stats_s  = node.stats{r};
    traces_s = [];
    if isfield(node, 'traces') && numel(node.traces) >= r
        traces_s = node.traces{r};
    end
    if isempty(stats_s), return; end

    entry.driver       = strtrim(char(string(node.meta.Driver(r))));
    entry.team         = tk;
    entry.manufacturer = strtrim(char(string(node.meta.Manufacturer(r))));
    entry.session      = strtrim(char(string(node.meta.Session(r))));
    entry.car          = resolve_car_number(entry.driver, driver_map, ...
                             strtrim(char(string(node.meta.CarNumber(r)))));
    entry.stats        = stats_s;
    entry.traces       = traces_s;
    entry.mode         = 'stream';

    fields = fieldnames(stats_s);
    if ~isempty(fields) && isfield(stats_s.(fields{1}), 'lap_numbers')
        entry.n_laps = numel(stats_s.(fields{1}).lap_numbers);
    else
        entry.n_laps = 0;
    end

    entry.best_lap_time = Inf;
    if ~isempty(traces_s) && isfield(traces_s, 'lap_times') && ~isempty(traces_s.lap_times)
        entry.best_lap_time = min(traces_s.lap_times);
    elseif ~isempty(fields) && isfield(stats_s.(fields{1}), 'lap_times')
        lt = stats_s.(fields{1}).lap_times;
        lt = lt(isfinite(lt));
        if ~isempty(lt), entry.best_lap_time = min(lt); end
    end
    entry.laps = [];
end


function entry = build_entry_bulk(node, r, tk, driver_map, ...
                                   stat_channels, min_lt, max_lt, verbose)
    entry = [];
    ch_struct = node.channels{r};
    if isempty(ch_struct), return; end

    lap_opts.min_lap_time = min_lt;
    lap_opts.max_lap_time = max_lt;
    lap_opts.verbose      = false;

    try
        laps = lap_slicer(ch_struct, lap_opts);
    catch ME
        if verbose, fprintf('  [WARN] %s r%d lap_slicer: %s\n', tk, r, ME.message); end
        return;
    end
    if isempty(laps), return; end

    nz_ops = {'mean non zero','min non zero','max non zero', ...
              'median non zero','std non zero'};
    try
        stats = lap_stats(laps, stat_channels, ...
            struct('operations', {[{'max','min','mean','median','var'}, nz_ops]}));
    catch ME
        if verbose, fprintf('  [WARN] %s r%d lap_stats: %s\n', tk, r, ME.message); end
        return;
    end

    entry.driver       = strtrim(char(string(node.meta.Driver{r})));
    entry.team         = tk;
    entry.manufacturer = strtrim(char(string(node.meta.Manufacturer{r})));
    entry.session      = strtrim(char(string(node.meta.Session{r})));
    entry.car          = resolve_car_number(entry.driver, driver_map, ...
                             strtrim(char(string(node.meta.CarNumber{r}))));
    entry.stats        = stats;
    entry.traces       = [];
    entry.laps         = laps;
    entry.n_laps       = numel(laps);
    entry.best_lap_time = min([laps.lap_time]);
    entry.mode         = 'bulk';
end


% ======================================================================= %
%  COLOUR HELPER
% ======================================================================= %
function col = resolve_colour(entry, colour_mode, colour_cfg, driver_map)
    switch lower(colour_mode)
        case {'driver', 'number'}
            if ~isempty(driver_map) && isstruct(driver_map)
                col = local_driver_colour(driver_map, entry.driver);
            else
                col = get_colour(colour_cfg, entry.driver, 'driver');
            end
        case 'team'
            col = get_colour(colour_cfg, entry.team, 'manufacturer');
        otherwise
            col = get_colour(colour_cfg, entry.manufacturer, 'manufacturer');
    end
end


% ======================================================================= %
%  FIGURE FACTORY
% ======================================================================= %
function [fig, ax_left, ax_right] = new_fig(pd, opts, ax_in)
    fw = get_opt(opts, 'fig_width',  1200);
    fh = get_opt(opts, 'fig_height', 650);
    fs = get_opt(opts, 'font_size',  11);

    if nargin >= 3 && ~isempty(ax_in) && isgraphics(ax_in)
        ax_left = ax_in;
        fig     = ax_left.Parent;
        while ~isa(fig, 'matlab.ui.Figure'), fig = fig.Parent; end
    else
        fig = figure('Visible','off','Color','white','Position',[100 100 fw fh]);
        ax_left = axes(fig);
    end

    ax_right = [];
    hold(ax_left,'on'); box(ax_left,'on'); grid(ax_left,'on');
    set(ax_left,'FontSize',fs,'FontName','Arial', ...
           'GridAlpha',0.25,'GridLineStyle','--','GridColor',[0.7 0.7 0.7]);
    ax_left.Color  = [0.97 0.97 0.97];
    fig.Color = 'white';
    ax_left.XColor = [0.2 0.2 0.2];
    ax_left.YColor = [0.2 0.2 0.2];

    if isfield(pd,'use_secondary') && pd.use_secondary && numel(pd.y_channels) >= 2
        yyaxis(ax_left, 'right');
        ax_right = ax_left;
        ax_left.YAxis(2).Color = [0.2 0.2 0.2];
        yyaxis(ax_left, 'left');
    end

    title(ax_left, pd.name, 'FontSize', fs+1, 'FontWeight', 'bold', 'Interpreter', 'none');
end

function apply_legend(ax, handles, labels, opts)
    valid = isgraphics(handles);
    if ~any(valid), return; end
    fs = get_opt(opts, 'font_size', 11);
    legend(ax, handles(valid), labels(valid), ...
        'Location','best','FontSize',fs-1,'Box','off','Interpreter','none');
end


% ======================================================================= %
%  SCATTER
% ======================================================================= %
function fig = make_scatter(run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in)
    if nargin < 7, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs = get_opt(opts, 'font_size', 11);
    use_secondary = isfield(pd,'use_secondary') && pd.use_secondary && numel(pd.y_channels) >= 2;
    use_shapes    = strcmpi(pd.differentiator, 'shapes');
    is_falling    = contains(lower(pd.name),'falling') || contains(lower(pd.x_axis),'falling');

    leg_h = []; leg_l = {}; leg_seen = {};
    x_lbl = 'Lap Number';

    for r = 1:numel(run_list)
        entry = run_list(r);
        col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);

        for yi = 1:numel(pd.y_channels)
            y_ch    = pd.y_channels{yi};
            y_field = sanitise_fn(y_ch);
            if ~isfield(entry.stats, y_field), continue; end

            if use_secondary && yi == 2
                yyaxis(ax, 'right');
                ylabel(ax, pd.y_channels{yi}, 'FontSize', fs, 'Interpreter','none');
            elseif use_secondary && yi == 1
                yyaxis(ax, 'left');
                ylabel(ax, pd.y_channels{1}, 'FontSize', fs, 'Interpreter','none');
            end

            y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
            lap_nums = entry.stats.(y_field).lap_numbers;
            valid    = isfinite(y_vals);
            y_vals   = y_vals(valid);  lap_nums = lap_nums(valid);
            if isempty(y_vals), continue; end

            if is_falling
                [y_vals, ~] = sort(y_vals, 'descend');
                x_vals = 1:numel(y_vals);  x_lbl = 'Rank';
            elseif is_keyword_lap(pd.x_axis)
                x_vals = lap_nums;  x_lbl = 'Lap Number';
            else
                x_field = sanitise_fn(pd.x_axis);
                if isfield(entry.stats, x_field)
                    xv = local_apply_math(entry.stats.(x_field), pd.math_fn);
                    x_vals = xv(valid);  x_lbl = pd.x_axis;
                else
                    x_vals = lap_nums;  x_lbl = 'Lap Number';
                end
            end

            marker = 'o';
            if use_shapes && yi <= numel(SHAPES), marker = SHAPES{yi}; end

            h = scatter(ax, x_vals, y_vals, 40, col, marker, 'filled', ...
                'MarkerEdgeColor', col*0.7, 'MarkerFaceAlpha', 0.8);

            lbl = build_label(entry, pd, yi, driver_map);
            if ~any(strcmp(leg_seen, lbl))
                leg_h(end+1) = h; leg_l{end+1} = lbl; leg_seen{end+1} = lbl; %#ok
            end
        end
    end

    if use_secondary, yyaxis(ax, 'left'); end
    xlabel(ax, x_lbl, 'FontSize', fs, 'Interpreter','none');
    if ~use_secondary
        ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
    end
    apply_legend(ax, leg_h, leg_l, opts);
    if use_shapes && numel(pd.y_channels) > 1
        add_shape_key(fig, pd.y_channels, SHAPES, fs);
    end
    apply_axis_limits(ax, pd);   % <-- ADD THIS
end


% ======================================================================= %
%  RANKED BOX
% ======================================================================= %
function fig = make_ranked_box(run_list, pd, colour_cfg, driver_map, opts, ax_in) %#ok<INUSL>
    if nargin < 6, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs  = get_opt(opts, 'font_size', 11);
    bw  = 0.06;  off = 0.10;

    MFR_LIST   = {'Ford',      'Toyota',    'Chevrolet'};
    MFR_OFFSET = [-off,         0,           +off      ];
    MFR_COLOUR = {[0.0 0.3 0.7],[0.8 0.1 0.1],[0.9 0.7 0.0]};

    y_ch    = pd.y_channels{1};
    y_field = sanitise_fn(y_ch);

    spd_min = -Inf;  spd_max = Inf;
    season_file = get_opt(opts, 'season_file', 'C:\SimEnv\trackDB\seasonOverview.xlsx');
    venue = get_opt(opts, 'venue', '');
    if ~isempty(venue)
        try
            T = readtable(season_file, 'Sheet', '2026');
            track_col = T.Track;
            if iscell(track_col)
                row = find(strcmpi(strtrim(track_col), strtrim(venue)), 1);
            else
                row = find(strcmpi(strtrim(string(track_col)), strtrim(venue)), 1);
            end
            if ~isempty(row)
                if ismember('TopSpeedMin', T.Properties.VariableNames), spd_min = T.TopSpeedMin(row); end
                if ismember('TopSpeedMax', T.Properties.VariableNames), spd_max = T.TopSpeedMax(row); end
                fprintf('  [ranked_box] Speed bounds: %.1f - %.1f km/h\n', spd_min, spd_max);
            else
                warning('make_ranked_box: venue "%s" not found in seasonOverview.', venue);
            end
        catch ME
            warning('make_ranked_box: could not load seasonOverview: %s', ME.message);
        end
    end

driver_mfr = {}; driver_vals = {}; driver_car = {};
    for r = 1:numel(run_list)
        entry = run_list(r);
        if ~isfield(entry.stats, y_field), continue; end
        vals = local_apply_math(entry.stats.(y_field), pd.math_fn);
%         vals = vals(isfinite(vals) & vals >= spd_min & vals <= spd_max);
vals = vals(isfinite(vals));
        is_speed_ch = any(contains(lower(y_ch), {'speed','gps','velocity'}));
        if is_speed_ch
            vals = vals(vals >= spd_min & vals <= spd_max);
        end
        if isempty(vals), continue; end
        driver_vals{end+1} = sort(vals, 'descend'); %#ok
        driver_mfr{end+1}  = entry.manufacturer;    %#ok
        driver_car{end+1}  = entry.car;             %#ok
    end
    if isempty(driver_vals), warning('make_ranked_box: no valid data.'); return; end

    max_rank = max(cellfun(@numel, driver_vals));
    leg_h = []; leg_l = {}; leg_seen = {};

    for rank = 1:max_rank
        for mi = 1:numel(MFR_LIST)
            mfr = MFR_LIST{mi};  col = MFR_COLOUR{mi};  x0 = rank + MFR_OFFSET(mi);
            mfr_vals = [];
            for d = 1:numel(driver_vals)
                if strcmpi(driver_mfr{d}, mfr) && rank <= numel(driver_vals{d})
                    mfr_vals(end+1) = driver_vals{d}(rank); %#ok
                end
            end
            if numel(mfr_vals) <= 1, continue; end
            iq = prctile(mfr_vals,[25 75]);  med_ = median(mfr_vals);
            mfr_vals = mfr_vals(mfr_vals >= med_ - 3*(iq(2)-iq(1)) & ...
                                mfr_vals <= med_ + 3*(iq(2)-iq(1)));
            if numel(mfr_vals) <= 1, continue; end
%             q   = prctile(mfr_vals,[25 50 75]);
%             iqr = q(3)-q(1);
%             w_lo = max(mfr_vals(mfr_vals >= q(1)-1.5*iqr));
%             w_hi = min(mfr_vals(mfr_vals <= q(3)+1.5*iqr));
%             otl  = mfr_vals(mfr_vals < q(1)-1.5*iqr | mfr_vals > q(3)+1.5*iqr);
            q    = prctile(mfr_vals,[25 50 75]);
            iqr  = q(3)-q(1);
            w_lo = max(mfr_vals(mfr_vals >= q(1)-1.5*iqr));
            w_hi = min(mfr_vals(mfr_vals <= q(3)+1.5*iqr));
            % Outlier detection — respects pd.outlier_method and threshold
            if isfield(pd,'highlight_outliers') && pd.highlight_outliers
                thr = pd.outlier_threshold;
                switch pd.outlier_method
                    case 'iqr'
                        otl = mfr_vals(mfr_vals < q(1)-thr*iqr | mfr_vals > q(3)+thr*iqr);
                    otherwise % mad
                        med_v = q(2);
                        mad_v = median(abs(mfr_vals - med_v));
                        otl   = mfr_vals(mfr_vals < med_v-thr*mad_v | mfr_vals > med_v+thr*mad_v);
                end
            else
                otl = mfr_vals(mfr_vals < q(1)-1.5*iqr | mfr_vals > q(3)+1.5*iqr);
            end
            xb = [x0-bw,x0+bw,x0+bw,x0-bw,x0-bw];
            yb = [q(1),q(1),q(3),q(3),q(1)];
            fill(ax,xb,yb,col,'FaceAlpha',0.4,'EdgeColor',col,'LineWidth',1.2);
            plot(ax,[x0-bw,x0+bw],[q(2),q(2)],'-','Color',col,'LineWidth',2);
            plot(ax,[x0,x0],[q(1),w_lo],'-','Color',col,'LineWidth',1);
            plot(ax,[x0,x0],[q(3),w_hi],'-','Color',col,'LineWidth',1);
            plot(ax,[x0-bw*0.5,x0+bw*0.5],[w_lo,w_lo],'-','Color',col,'LineWidth',1);
            plot(ax,[x0-bw*0.5,x0+bw*0.5],[w_hi,w_hi],'-','Color',col,'LineWidth',1);
            if ~isempty(otl)
                scatter(ax, repmat(x0,size(otl)), otl, 20, col, 'o', ...
                    'MarkerEdgeColor', col, 'MarkerFaceAlpha', 0);
                % Label which car is the outlier
                for oi = 1:numel(otl)
                    % Find which car produced this value at this rank
                    for d = 1:numel(driver_vals)
                        if strcmpi(driver_mfr{d}, mfr) && rank <= numel(driver_vals{d}) ...
                                && driver_vals{d}(rank) == otl(oi)
                            text(ax, x0 + bw*1.2, otl(oi), ...
                                sprintf('#%s', driver_car{d}), ...
                                'FontSize', 8, 'Color', col*0.75, ...
                                'VerticalAlignment', 'middle', ...
                                'HorizontalAlignment', 'left', ...
                                'Interpreter', 'none');
                            break;
                        end
                    end
                end
            end
            if ~any(strcmp(leg_seen, mfr))
                h = fill(ax,NaN,NaN,col,'FaceAlpha',0.4,'EdgeColor',col);
                leg_h(end+1)=h; leg_l{end+1}=mfr; leg_seen{end+1}=mfr; %#ok
            end
        end
    end
    xlabel(ax,'Rank','FontSize',fs,'Interpreter','none');
    ylabel(ax,y_ch,'FontSize',fs,'Interpreter','none');
    smart_xticks(ax, 1:max_rank, [], fs);
    apply_legend(ax, leg_h, leg_l, opts);
end


% ======================================================================= %
%  LAPWISE BOX
% ======================================================================= %
function fig = make_lapwise_box(run_list, pd, colour_cfg, driver_map, opts, ax_in) %#ok<INUSL>
    if nargin < 6, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs  = get_opt(opts, 'font_size', 11);
    bw  = 0.06;  off = 0.10;

    MFR_LIST   = {'Ford',      'Toyota',    'Chevrolet'};
    MFR_OFFSET = [-off,         0,           +off      ];
    MFR_COLOUR = {[0.0 0.3 0.7],[0.8 0.1 0.1],[0.9 0.7 0.0]};

    y_ch    = pd.y_channels{1};
    y_field = sanitise_fn(y_ch);

    spd_min = -Inf;  spd_max = Inf;
    season_file = get_opt(opts, 'season_file', 'C:\SimEnv\trackDB\seasonOverview.xlsx');
    venue = get_opt(opts, 'venue', '');
    if ~isempty(venue)
        try
            T = readtable(season_file, 'Sheet', '2026');
            track_col = T.Track;
            if iscell(track_col)
                row = find(strcmpi(strtrim(track_col), strtrim(venue)), 1);
            else
                row = find(strcmpi(strtrim(string(track_col)), strtrim(venue)), 1);
            end
            if ~isempty(row)
                if ismember('TopSpeedMin', T.Properties.VariableNames), spd_min = T.TopSpeedMin(row); end
                if ismember('TopSpeedMax', T.Properties.VariableNames), spd_max = T.TopSpeedMax(row); end
            end
        catch, end
    end

    driver_mfr = {}; driver_vals = {}; driver_car = {};
    for r = 1:numel(run_list)
        entry = run_list(r);
        if ~isfield(entry.stats, y_field), continue; end
        vals = local_apply_math(entry.stats.(y_field), pd.math_fn);
        if strcmpi(y_field,'Speed')
            vals = vals(isfinite(vals) & vals >= spd_min & vals <= spd_max);
        else
            vals = vals(isfinite(vals));
        end
        if isempty(vals), continue; end
        driver_vals{end+1} = vals;            %#ok
        driver_mfr{end+1}  = entry.manufacturer; %#ok
    end
    if isempty(driver_vals), warning('make_lapwise_box: no valid data.'); return; end

    max_lap = max(cellfun(@numel, driver_vals));
    leg_h = []; leg_l = {}; leg_seen = {};

    for lap = 1:max_lap
        for mi = 1:numel(MFR_LIST)
            mfr = MFR_LIST{mi};  col = MFR_COLOUR{mi};  x0 = lap + MFR_OFFSET(mi);
            mfr_vals = [];
            for d = 1:numel(driver_vals)
                if strcmpi(driver_mfr{d}, mfr) && lap <= numel(driver_vals{d})
                    mfr_vals(end+1) = driver_vals{d}(lap); %#ok
                end
            end
            if numel(mfr_vals) <= 1, continue; end
                       iq = prctile(mfr_vals,[25 75]);  med_ = median(mfr_vals);
            mfr_vals = mfr_vals(mfr_vals >= med_ - 3*(iq(2)-iq(1)) & ...
                                mfr_vals <= med_ + 3*(iq(2)-iq(1)));
            if numel(mfr_vals) <= 1, continue; end
            q    = prctile(mfr_vals,[25 50 75]);
            iqr_ = q(3)-q(1);
            w_lo = max(mfr_vals(mfr_vals >= q(1)-1.5*iqr_));
            w_hi = min(mfr_vals(mfr_vals <= q(3)+1.5*iqr_));
            if isfield(pd,'highlight_outliers') && pd.highlight_outliers
                thr = pd.outlier_threshold;
                switch pd.outlier_method
                    case 'iqr'
                        otl = mfr_vals(mfr_vals < q(1)-thr*iqr_ | mfr_vals > q(3)+thr*iqr_);
                    otherwise % mad
                        mad_v = median(abs(mfr_vals - q(2)));
                        otl   = mfr_vals(mfr_vals < q(2)-thr*mad_v | mfr_vals > q(2)+thr*mad_v);
                end
            else
                otl = mfr_vals(mfr_vals < q(1)-1.5*iqr_ | mfr_vals > q(3)+1.5*iqr_);
            end
            xb = [x0-bw,x0+bw,x0+bw,x0-bw,x0-bw];
            yb = [q(1),q(1),q(3),q(3),q(1)];
            fill(ax,xb,yb,col,'FaceAlpha',0.4,'EdgeColor',col,'LineWidth',1.2);
            plot(ax,[x0-bw,x0+bw],[q(2),q(2)],'-','Color',col,'LineWidth',2);
            plot(ax,[x0,x0],[q(1),w_lo],'-','Color',col,'LineWidth',1);
            plot(ax,[x0,x0],[q(3),w_hi],'-','Color',col,'LineWidth',1);
            plot(ax,[x0-bw*0.5,x0+bw*0.5],[w_lo,w_lo],'-','Color',col,'LineWidth',1);
            plot(ax,[x0-bw*0.5,x0+bw*0.5],[w_hi,w_hi],'-','Color',col,'LineWidth',1);
            if ~isempty(otl)
                scatter(ax,repmat(x0,size(otl)),otl,20,col,'o','MarkerEdgeColor',col,'MarkerFaceAlpha',0);
            end
            if ~any(strcmp(leg_seen, mfr))
                h = fill(ax,NaN,NaN,col,'FaceAlpha',0.4,'EdgeColor',col);
                leg_h(end+1)=h; leg_l{end+1}=mfr; leg_seen{end+1}=mfr; %#ok
            end
        end
    end
    xlabel(ax,'Lap Number','FontSize',fs,'Interpreter','none');
    ylabel(ax,y_ch,'FontSize',fs,'Interpreter','none');
    smart_xticks(ax, 1:max_lap, [], fs);
    apply_legend(ax, leg_h, leg_l, opts);
end


% ======================================================================= %
%  SESSION LAP WISE  (NEW)
%  Groups by session, then car. Outings stacked in run_list order.
% ======================================================================= %
function fig = make_session_lap_wise(run_list, pd, colour_cfg, driver_map, opts, ax_in)
    if nargin < 6, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs = get_opt(opts, 'font_size', 11);

    sessions = unique({run_list.session}, 'stable');
    cars     = unique({run_list.car},     'stable');

    leg_h = []; leg_l = {}; leg_seen = {};

    for s = 1:numel(sessions)
        sess      = sessions{s};
        sess_runs = run_list(strcmp({run_list.session}, sess));

        for c = 1:numel(cars)
            car_runs = sess_runs(strcmp({sess_runs.car}, cars{c}));
            if isempty(car_runs), continue; end

            col = resolve_colour(car_runs(1), pd.colour_mode, colour_cfg, driver_map);

            for yi = 1:numel(pd.y_channels)
                y_ch    = pd.y_channels{yi};
                y_field = sanitise_fn(y_ch);

                x_all = []; y_all = [];
                lap_offset = 0;

                for r = 1:numel(car_runs)
                    entry = car_runs(r);
                    if ~isfield(entry.stats, y_field), continue; end
                    y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
                    lap_nums = entry.stats.(y_field).lap_numbers;
                    valid    = isfinite(y_vals);
                    y_vals   = y_vals(valid);  lap_nums = lap_nums(valid);
                    if isempty(y_vals), continue; end
                    x_all = [x_all; lap_nums(:) + lap_offset]; %#ok
                    y_all = [y_all; y_vals(:)];                %#ok
                    lap_offset = lap_offset + max(lap_nums);
                end
                if isempty(x_all), continue; end

                h = plot(ax, x_all, y_all, '-o', ...
                    'Color', col, 'LineWidth', 1.8, 'MarkerSize', 4, ...
                    'MarkerFaceColor', col, 'MarkerEdgeColor', col*0.7);

                % Build legend label — group by colour_mode key, not car number
                switch lower(pd.colour_mode)
                    case 'manufacturer'
                        leg_key = car_runs(1).manufacturer;
                        if isempty(leg_key), leg_key = sprintf('#%s', cars{c}); end
                    case 'team'
                        leg_key = car_runs(1).team;
                        if isempty(leg_key), leg_key = sprintf('#%s', cars{c}); end
                    otherwise  % driver — keep individual car identity
                        if numel(sessions) > 1
                            leg_key = sprintf('#%s  %s', cars{c}, sess);
                        else
                            leg_key = sprintf('#%s', cars{c});
                        end
                end
                if numel(pd.y_channels) > 1, leg_key = sprintf('%s  [%s]', leg_key, y_ch); end
                if ~any(strcmp(leg_seen, leg_key))
                    leg_h(end+1) = h; leg_l{end+1} = leg_key; leg_seen{end+1} = leg_key; %#ok
                end
            end
        end
    end

    xlabel(ax, 'Session Lap', 'FontSize', fs, 'Interpreter','none');
    ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
    apply_legend(ax, leg_h, leg_l, opts);
end


% ======================================================================= %
%  AXIS LIMITS  (NEW)
% ======================================================================= %
function smart_xticks(ax, tick_vals, labels, font_size)
% SMART_XTICKS  Set x-axis ticks without overlapping labels.
%
% Computes the largest step size from the candidate sequence
% [1 2 5 10 20 25 50 100 ...] such that labels fit without overlap,
% based on figure width and font size.  Works for both integer lap
% numbers and arbitrary label strings.
%
% Inputs:
%   ax         — axes handle
%   tick_vals  — numeric vector of all candidate tick positions
%   labels     — cell array of label strings (same length as tick_vals)
%                Pass [] to auto-generate from tick_vals as integers.
%   font_size  — base font size (used for char-width estimate)

    if isempty(tick_vals), return; end
    if nargin < 3 || isempty(labels)
        labels = arrayfun(@(v) num2str(round(v)), tick_vals, 'UniformOutput', false);
    end
    if nargin < 4 || isempty(font_size)
        font_size = 10;
    end

    % Estimate character width in data units.
    % Approach: map axes width (pixels) → data range → chars per data unit.
    fig = ancestor(ax, 'figure');
    fig_pos  = get(fig, 'Position');          % [x y w h] in pixels
    ax_pos   = get(ax,  'Position');          % normalised [x y w h]
    ax_px    = ax_pos(3) * fig_pos(3);        % axes width in pixels

    xl       = xlim(ax);
    x_range  = xl(2) - xl(1);
    if x_range <= 0, x_range = numel(tick_vals); end

    px_per_data = ax_px / x_range;

    % Approximate pixels per character at given font size
    % (empirically ~0.6 × font_size pts; assume 1pt ≈ 1.33px at 96dpi)
    px_per_char = font_size * 0.6 * 1.33;

    % Longest label determines the minimum spacing needed
    max_chars   = max(cellfun(@numel, labels));
    min_spacing_px = max_chars * px_per_char * 1.2;   % 20% padding
    min_spacing_data = min_spacing_px / px_per_data;

    % Candidate step sizes
    steps = [1 2 5 10 15 20 25 50 100 200 500];
    chosen_step = steps(end);
    for s = 1:numel(steps)
        if steps(s) >= min_spacing_data
            chosen_step = steps(s);
            break;
        end
    end

    % Select ticks that land on multiples of chosen_step
    % (relative to first tick value so we always include lap 1)
    first = tick_vals(1);
    keep  = mod(tick_vals - first, chosen_step) == 0;
    sel_vals   = tick_vals(keep);
    sel_labels = labels(keep);

    set(ax, 'XTick', sel_vals, 'XTickLabel', sel_labels, 'XTickLabelRotation', 0);
end


function apply_axis_limits(fig_or_ax, pd)
    % Accepts either a figure handle or an axes handle directly.
    if isa(fig_or_ax, 'matlab.graphics.axis.Axes')
        ax = fig_or_ax;
    else
        % Figure handle — find primary axes (last in findobj = first created)
        all_ax = findobj(fig_or_ax, 'Type', 'axes');
        plot_ax = [];
        for i = 1:numel(all_ax)
            t = get(all_ax(i), 'Tag');
            if isempty(t) || strcmpi(t, '')
                plot_ax(end+1) = all_ax(i); %#ok
            end
        end
        if isempty(plot_ax), return; end
        ax = plot_ax(end);
    end
    if isfield(pd,'x_lim') && numel(pd.x_lim) == 2, xlim(ax, pd.x_lim); end
    if isfield(pd,'y_lim') && numel(pd.y_lim) == 2, ylim(ax, pd.y_lim); end
end


% ======================================================================= %
%  OUTLIER HIGHLIGHTING  (NEW)
% ======================================================================= %
function draw_outlier_highlights(fig, pd, run_list, colour_cfg, driver_map, ax_in)
    if nargin >= 6 && ~isempty(ax_in) && isgraphics(ax_in)
        ax = ax_in;
    else
        ax = findobj(fig, 'Type', 'axes');
        if isempty(ax), return; end
        ax = ax(end);
    end

    method       = pd.outlier_method;
    threshold    = pd.outlier_threshold;
    fs_ann       = 8;
    MAX_OUTLIERS = 5;

    all_laps = []; all_vals = []; all_cars = {};
    all_cols = {}; all_devs = []; all_mfrs = {};
    mfrs = unique({run_list.manufacturer}, 'stable');

    for m = 1:numel(mfrs)
        mfr      = mfrs{m};
        mfr_runs = run_list(strcmp({run_list.manufacturer}, mfr));
        col      = resolve_colour(mfr_runs(1), 'manufacturer', colour_cfg, driver_map);

        for yi = 1:numel(pd.y_channels)
            y_field = sanitise_fn(pd.y_channels{yi});

            pool = [];
            for r = 1:numel(mfr_runs)
                if ~isfield(mfr_runs(r).stats, y_field), continue; end
                v = local_apply_math(mfr_runs(r).stats.(y_field), pd.math_fn);
                pool = [pool, v(isfinite(v))]; %#ok
            end
            if numel(pool) < 4, continue; end

            switch method
                case 'iqr'
                    q1 = prctile(pool,25);  q3 = prctile(pool,75);
                    iq = q3 - q1;
                    lo = q1 - threshold*iq;  hi = q3 + threshold*iq;
                    centre = (q1 + q3) / 2;
                otherwise % mad
                    med_  = median(pool);
                    mad_  = median(abs(pool - med_));
                    lo = med_ - threshold*mad_;  hi = med_ + threshold*mad_;
                    centre = med_;
            end

            for r = 1:numel(mfr_runs)
                entry = mfr_runs(r);
                if ~isfield(entry.stats, y_field), continue; end
                y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
                lap_nums = entry.stats.(y_field).lap_numbers;
                valid    = isfinite(y_vals);
                y_vals   = y_vals(valid);  lap_nums = lap_nums(valid);

                out_idx = find(y_vals < lo | y_vals > hi);
                for k = 1:numel(out_idx)
                    i = out_idx(k);
                    all_laps(end+1) = lap_nums(i);             %#ok
                    all_vals(end+1) = y_vals(i);               %#ok
                    all_cars{end+1} = entry.car;               %#ok
                    all_cols{end+1} = col;                     %#ok
                    all_devs(end+1) = abs(y_vals(i) - centre); %#ok
                    all_mfrs{end+1} = mfr;                     %#ok
                end
            end
        end
    end

    if isempty(all_laps), return; end

    scope = 'manufacturer';
    if isfield(pd, 'outlier_scope') && strcmpi(pd.outlier_scope, 'global')
        scope = 'global';
    end

    if strcmpi(scope, 'global')
        [~, rank_order] = sort(all_devs, 'descend');
        keep = rank_order(1 : min(MAX_OUTLIERS, numel(rank_order)));
    else
        mfr_tags = unique(all_mfrs, 'stable');
        keep = [];
        for m = 1:numel(mfr_tags)
            mfr_idx = find(strcmp(all_mfrs, mfr_tags{m}));
            [~, rank_order] = sort(all_devs(mfr_idx), 'descend');
            keep = [keep, mfr_idx(rank_order(1 : min(MAX_OUTLIERS, numel(rank_order))))]; %#ok
        end
    end

    scat_handles = gobjects(numel(keep), 1);
    for k = 1:numel(keep)
        i   = keep(k);
        col = all_cols{i};
        scat_handles(k) = scatter(ax, all_laps(i), all_vals(i), 80, ...
            'MarkerEdgeColor', col, 'MarkerFaceColor', 'none', ...
            'LineWidth', 2.0, 'HandleVisibility', 'off');
        text(ax, all_laps(i), all_vals(i), ...
            sprintf('  #%s L%d', all_cars{i}, all_laps(i)), ...
            'FontSize', fs_ann, 'Color', col*0.75, ...
            'VerticalAlignment', 'middle', ...
            'HorizontalAlignment', 'left', 'Interpreter', 'none');
    end
    uistack(scat_handles, 'top');
end


% ======================================================================= %
%  LINE
% ======================================================================= %
function fig = make_line(run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in)
    if nargin < 7, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs = get_opt(opts, 'font_size', 11);
    use_secondary = isfield(pd,'use_secondary') && pd.use_secondary && numel(pd.y_channels) >= 2;
    use_shapes    = strcmpi(pd.differentiator, 'shapes');

    leg_h = []; leg_l = {}; leg_seen = {};
    x_lbl = 'Lap Number';

    for r = 1:numel(run_list)
        entry = run_list(r);
        col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);

        for yi = 1:numel(pd.y_channels)
            y_ch    = pd.y_channels{yi};
            y_field = sanitise_fn(y_ch);
            if ~isfield(entry.stats, y_field), continue; end

            if use_secondary && yi == 2
                yyaxis(ax, 'right');
                ylabel(ax, pd.y_channels{yi}, 'FontSize', fs, 'Interpreter','none');
            elseif use_secondary && yi == 1
                yyaxis(ax, 'left');
                ylabel(ax, pd.y_channels{1}, 'FontSize', fs, 'Interpreter','none');
            end

            y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
            lap_nums = entry.stats.(y_field).lap_numbers;
            valid    = isfinite(y_vals);
            y_vals   = y_vals(valid);  lap_nums = lap_nums(valid);
            if isempty(y_vals), continue; end

            if is_keyword_lap(pd.x_axis)
                x_vals = lap_nums;  x_lbl = 'Lap Number';
            else
                x_field = sanitise_fn(pd.x_axis);
                if isfield(entry.stats, x_field)
                    xv = local_apply_math(entry.stats.(x_field), pd.math_fn);
                    x_vals = xv(valid);  x_lbl = pd.x_axis;
                else
                    x_vals = lap_nums;  x_lbl = 'Lap Number';
                end
            end

            marker = 'none';
            if use_shapes && yi <= numel(SHAPES), marker = SHAPES{yi}; end

            h = plot(ax, x_vals, y_vals, '-', ...
                'Color', col, 'LineWidth', 1.8, 'Marker', marker, 'MarkerSize', 5);

            lbl = build_label(entry, pd, yi, driver_map);
            if ~any(strcmp(leg_seen, lbl))
                leg_h(end+1)=h; leg_l{end+1}=lbl; leg_seen{end+1}=lbl; %#ok
            end
        end
    end

    if use_secondary, yyaxis(ax, 'left'); end
    xlabel(ax, x_lbl, 'FontSize', fs, 'Interpreter','none');
    if ~use_secondary
        ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
    end
    apply_legend(ax, leg_h, leg_l, opts);
end


% ======================================================================= %
%  BOXPLOT
% ======================================================================= %
function fig = make_boxplot(run_list, pd, colour_cfg, driver_map, opts, ax_in)
    if nargin < 6, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);

    all_vals = []; all_grp = []; grp_labels = {}; colours = [];
    gi = 0;

    for r = 1:numel(run_list)
        entry = run_list(r);
        col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
        for yi = 1:numel(pd.y_channels)
            y_field = sanitise_fn(pd.y_channels{yi});
            if ~isfield(entry.stats, y_field), continue; end
            vals = get_dist_vals(entry, y_field, pd.math_fn);
            if isempty(vals), continue; end
            gi = gi + 1;
            all_vals(end+1:end+numel(vals)) = vals(:)';  %#ok
            all_grp(end+1:end+numel(vals))  = gi;        %#ok
            grp_labels{gi} = build_label(entry, pd, yi, driver_map); %#ok
            colours(gi,:)  = col;                        %#ok
        end
    end
    if isempty(all_vals), return; end
    bp = boxplot(ax, all_vals, all_grp, 'Labels', grp_labels, 'Widths', 0.4, 'Symbol', '+');
    colour_boxplot(bp, colours);
    ax.XTickLabelRotation = 30;
end


% ======================================================================= %
%  VIOLIN
% ======================================================================= %
function fig = make_violin(run_list, pd, colour_cfg, driver_map, opts, ax_in)
    if nargin < 6, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);

    gi = 0; tick_pos = []; tick_labels = {};
    for r = 1:numel(run_list)
        entry = run_list(r);
        col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
        for yi = 1:numel(pd.y_channels)
            y_field = sanitise_fn(pd.y_channels{yi});
            if ~isfield(entry.stats, y_field), continue; end
            vals = get_dist_vals(entry, y_field, pd.math_fn);
            if numel(vals) < 3, continue; end
            gi = gi + 1;
            [f, xi] = ksdensity(vals);
            f = f / max(f) * 0.4;
            fill(ax, [gi+f, fliplr(gi-f)], [xi, fliplr(xi)], col, ...
                'FaceAlpha',0.65,'EdgeColor',col*0.75,'LineWidth',0.8);
            plot(ax, [gi-0.15 gi+0.15], [median(vals) median(vals)], '-','Color',col*0.5,'LineWidth',2);
            plot(ax, [gi gi], [prctile(vals,25) prctile(vals,75)], '-','Color',col*0.5,'LineWidth',3);
            tick_pos(end+1)    = gi;                          %#ok
            tick_labels{end+1} = build_label(entry, pd, yi, driver_map); %#ok
        end
    end
    if gi == 0, return; end
    set(ax,'XTick',tick_pos,'XTickLabel',tick_labels);
    ax.XTickLabelRotation = 30;
    xlim(ax,[0.5, gi+0.5]);
end


% ======================================================================= %
%  HISTOGRAM
% ======================================================================= %
function fig = make_histogram(run_list, pd, colour_cfg, driver_map, opts, ax_in)
    if nargin < 6, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs = get_opt(opts, 'font_size', 11);

    leg_h = []; leg_l = {}; leg_seen = {};
    
    for r = 1:numel(run_list)
        entry = run_list(r);
        col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
        for yi = 1:numel(pd.y_channels)
            y_field = sanitise_fn(pd.y_channels{yi});
            if ~isfield(entry.stats, y_field), continue; end
            vals = get_dist_vals(entry, y_field, pd.math_fn);
            if isempty(vals), continue; end
            
            % plotting magic of the PSD
            
            h = histogram(ax, vals, 'FaceColor', col, 'EdgeColor', col*0.7, ...
                'FaceAlpha', 0.5, 'Normalization', 'probability');
            lbl = build_label(entry, pd, yi, driver_map);
            if ~any(strcmp(leg_seen, lbl))
                leg_h(end+1)=h; leg_l{end+1}=lbl; leg_seen{end+1}=lbl; %#ok
            end
        end
    end
    xlabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
    ylabel(ax, 'Probability', 'FontSize', fs);
    apply_legend(ax, leg_h, leg_l, opts);
end
% ======================================================================= %
%  Make PSD
% ======================================================================= %

% ======================================================================= %
%  PSD  (Welch, no toolbox)
%  pd.y_channels{1} = signal channel
%  pd.z_axis        = gate channel (0/1 mask); empty = no gating
% ======================================================================= %
function [fig, psd_stats] = make_psd(run_list, pd, colour_cfg, driver_map, opts, ax_in)
    if nargin < 6, ax_in = []; end

    % --- PSD config (overridable via opts) ---
    win_len  = get_opt(opts, 'psd_win_len',  256);
    overlap  = get_opt(opts, 'psd_overlap',  128);
    nfft     = get_opt(opts, 'psd_nfft',     512);
    freq_max = get_opt(opts, 'psd_freq_max', 12);
    fs_font  = get_opt(opts, 'font_size',    11);

    % --- Figure / axes ---
    if isempty(ax_in)
        fw  = get_opt(opts, 'fig_width',  1200);
        fh  = get_opt(opts, 'fig_height', 650);
        fig = figure('Visible','off','Color','white','Position',[100 100 fw fh]);
        ax  = axes(fig);
    else
        ax  = ax_in;
        fig = ancestor(ax, 'figure');
    end
    hold(ax, 'on');
    box(ax, 'on');
    grid(ax, 'on');
    set(ax, 'FontSize', fs_font, 'FontName', 'Arial', ...
        'GridAlpha', 0.25, 'GridLineStyle', '--', 'GridColor', [0.7 0.7 0.7]);
    ax.Color  = [0.97 0.97 0.97];
    fig.Color = 'white';

    y_ch     = pd.y_channels{1};
    y_field  = sanitise_fn(y_ch);
    has_gate = isfield(pd, 'z_axis') && ~isempty(pd.z_axis);
    if has_gate
        gate_field = sanitise_fn(pd.z_axis);
    end

    leg_h = []; leg_l = {};

    psd_stats = struct('driver',{}, 'lap_time',{}, 'value',{}, 'col',{});
    for r = 1:numel(run_list)
        entry = run_list(r);
        col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);

        % --- Get fastest lap channels ---
        laps = entry;
        if isempty(laps), continue; end
        [~, best] = min([laps.best_lap_time]);
        lap_ch = laps(best).traces;

        % --- Find signal ---
        fn    = fieldnames(lap_ch);
        match = fn(strcmpi(fn, y_field));
        if isempty(match)
            fprintf('  [WARN] PSD: channel "%s" not found for %s\n', y_ch, entry.driver);
            continue;
        end
        sig = lap_ch.(match{1})(best).data(:);
        Fs  =  unique(entry.stats.(match{1})(best).sample_rate);

        % --- Apply gate (zero out where gate == 0) ---
        if has_gate
            gmatch = fn(strcmpi(fn, gate_field));
            if ~isempty(gmatch)
                gate = lap_ch.(gmatch{1}).data(:);
                % Align lengths
                n = min(numel(sig), numel(gate));
                sig  = sig(1:n);
                gate = gate(1:n);
                sig(gate == 0) = 0;
            else
                fprintf('  [WARN] PSD: gate channel "%s" not found for %s — no gating applied\n', ...
                    pd.z_axis, entry.driver);
            end
        end

        sig(isnan(sig)) = 0;
        sig = sig - mean(sig);

        % --- Welch PSD (manual) ---
        w       = 0.5 * (1 - cos(2*pi*(0:win_len-1)' / (win_len-1)));
        w_power = sum(w.^2);
        starts  = 1:(win_len-overlap):numel(sig)-win_len+1;
        n_segs  = numel(starts);
        if n_segs < 1, continue; end
        pxx = zeros(nfft/2+1, 1);
        for k = 1:n_segs
            seg = sig(starts(k):starts(k)+win_len-1) .* w;
            X   = fft(seg, nfft);
            pxx = pxx + abs(X(1:nfft/2+1)).^2;
        end
        pxx = pxx ./ (n_segs * unique(Fs) * w_power);
        pxx(2:end-1) = 2 * pxx(2:end-1);
        f = (0:nfft/2)' * Fs / nfft;

        f_mask = f > 0.2 & f < freq_max;

        lbl = build_label(entry, pd, 1, driver_map);
        h   = semilogy(ax, f(f_mask), pxx(f_mask), '-', ...
            'Color', col, 'LineWidth', 1.5, 'DisplayName', lbl);
        
        set(ax, 'YScale', 'log');

        leg_h(end+1) = h;    %#ok
        leg_l{end+1} = lbl;  %#ok
        
        % --- Extract scalar stat from frequency band ---
        stat_range = get_opt(opts, 'psd_stat_freq_range', [1 4]);
        stat_fn    = get_opt(opts, 'psd_stat_fn',         'max');
        band_mask  = f >= stat_range(1) & f <= stat_range(2);
        band_pxx   = pxx(band_mask);
        if strcmp(stat_fn, 'min')
            scalar = min(band_pxx);
        else
            scalar = max(band_pxx);
        end
        
        psd_stats(r).driver   = entry.driver;
        psd_stats(r).lap_time = laps.best_lap_time;
        psd_stats(r).value    = scalar;
        psd_stats(r).col      = col;
        
    end

    title(ax, pd.name, 'FontSize', fs_font+1, 'FontWeight', 'bold', 'Interpreter', 'none');
    xlabel(ax, 'Frequency (Hz)', 'FontSize', fs_font, 'Interpreter', 'none');
    ylabel(ax, sprintf('PSD (%s²/Hz)', y_ch), 'FontSize', fs_font, 'Interpreter', 'none');
    xlim(ax, [0.2 freq_max]);
    apply_legend(ax, leg_h, leg_l, opts);
end
% ======================================================================= %
%  TIMESERIES
% ======================================================================= %

% ======================================================================= %
%  PSD SCATTER  — lap time vs PSD scalar extracted from make_psd
% ======================================================================= %
% function fig = make_psd_scatter(run_list, pd, colour_cfg, driver_map, opts, SHAPES)
function fig = make_psd_scatter(run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in)
    if nargin < 7, ax_in = []; end
    if isempty(ax_in)
        [fig, ax] = new_fig(pd, opts);
    else
        ax  = ax_in;
        fig = ancestor(ax, 'figure');
    end
    hold(ax, 'on');

    fs         = get_opt(opts, 'font_size',           11);
    stat_range = get_opt(opts, 'psd_stat_freq_range', [3 5]);
    stat_fn    = get_opt(opts, 'psd_stat_fn',         'max');
    win_len    = get_opt(opts, 'psd_win_len',          256);
    overlap    = get_opt(opts, 'psd_overlap',          128);
    nfft       = get_opt(opts, 'psd_nfft',             512);

    has_gate = isfield(pd, 'z_axis') && ~isempty(pd.z_axis);
    if has_gate, gate_field = sanitise_fn(pd.z_axis); end

    y_ch    = pd.y_channels{1};
    y_field = sanitise_fn(y_ch);

    leg_h = []; leg_l = {};

    for r = 1:numel(run_list)
        entry = run_list(r);
        col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
        col   = col(:)';

        tr = entry.traces;
        if isempty(tr) || ~isstruct(tr) || tr.n_traces == 0
            fprintf('  [WARN] psd_scatter: no traces for %s\n', entry.driver);
            continue;
        end

        % --- Find signal field using strcmpi (same as working psd code) ---
        tr_fn = fieldnames(tr);
        match = tr_fn(strcmpi(tr_fn, y_field));
        if isempty(match)
            fprintf('  [WARN] psd_scatter: channel "%s" not found for %s\n', y_ch, entry.driver);
            continue;
        end
        lap_traces = tr.(match{1});

        % --- Gate field ---
        gate_traces = [];
        if has_gate
            gmatch = tr_fn(strcmpi(tr_fn, gate_field));
            if ~isempty(gmatch)
                gate_traces = tr.(gmatch{1});
            else
                fprintf('  [WARN] psd_scatter: gate "%s" not found for %s\n', pd.z_axis, entry.driver);
            end
        end

        x_vals = []; y_vals = [];

        for li = 1:tr.n_traces
            sig = lap_traces(li).data(:);
            Fs  = unique(entry.stats.(match{1}).sample_rate);   % sample_rate on the trace struct directly

            % --- Gate ---
            if ~isempty(gate_traces) && li <= numel(gate_traces)
                gate = gate_traces(li).data(:);
                n    = min(numel(sig), numel(gate));
                sig  = sig(1:n);
                gate = gate(1:n);
                sig(gate == 0) = 0;
            end

            sig(isnan(sig)) = 0;
            sig = sig - mean(sig);

            if numel(sig) < win_len, continue; end

            % --- Welch PSD ---
            w       = 0.5*(1 - cos(2*pi*(0:win_len-1)'/(win_len-1)));
            w_power = sum(w.^2);
            starts  = 1:(win_len-overlap):numel(sig)-win_len+1;
            n_segs  = numel(starts);
            if n_segs < 1, continue; end

            pxx = zeros(nfft/2+1, 1);
            for k = 1:n_segs
                seg = sig(starts(k):starts(k)+win_len-1) .* w;
                X   = fft(seg, nfft);
                pxx = pxx + abs(X(1:nfft/2+1)).^2;
            end
            pxx = pxx ./ (n_segs .* Fs .* w_power);
            pxx(2:end-1) = 2*pxx(2:end-1);
            f = (0:nfft/2)' .* Fs ./ nfft;

            band_mask = f >= stat_range(1) & f <= stat_range(2);
            band_pxx  = pxx(band_mask);
            if isempty(band_pxx), continue; end

            if strcmp(stat_fn, 'min')
                scalar = min(band_pxx);
            else
                scalar = max(band_pxx);
            end

            x_vals(end+1) = tr.lap_times(li);  %#ok
            y_vals(end+1) = scalar;             %#ok
        end

        if isempty(x_vals), continue; end

        h = scatter(ax, y_vals, x_vals, 40, col, 'o', 'filled', ...
            'MarkerEdgeColor', col*0.7, 'MarkerFaceAlpha', 0.8);
        lbl = build_label(entry, pd, 1, driver_map);
        leg_h(end+1) = h;    %#ok
        leg_l{end+1} = lbl;  %#ok
    end

    ylabel(ax, 'Lap Time (s)', 'FontSize', fs, 'Interpreter', 'none');
    xlabel(ax, sprintf('%s PSD %s [%.0f-%.0f Hz]', y_ch, stat_fn, ...
        stat_range(1), stat_range(2)), 'FontSize', fs, 'Interpreter', 'none');
    apply_legend(ax, leg_h, leg_l, opts);
end


function fig = make_timeseries(run_list, pd, colour_cfg, driver_map, opts, ...
                                dist_ch, dist_npts, n_laps_avg, ax_in)
    if nargin < 9, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs  = get_opt(opts, 'font_size', 11);
    lw  = 2.0;  lwa = 0.8;

    leg_h = []; leg_l = {}; leg_seen = {};

    for r = 1:numel(run_list)
        entry = run_list(r);
        col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);

        if strcmp(entry.mode, 'stream')
            tr = entry.traces;
            if isempty(tr) || ~isstruct(tr) || tr.n_traces == 0
                fprintf('  [WARN] No traces for %s — skipping timeseries.\n', entry.driver);
                continue;
            end
            for yi = 1:numel(pd.y_channels)
                y_ch    = pd.y_channels{yi};
                y_field = sanitise_fn(y_ch);
                if ~isfield(tr, y_field)
                    fprintf('  [WARN] Trace "%s" not found for %s\n', y_ch, entry.driver);
                    continue;
                end
% ==========================Editted and commented out=================
% lap_traces = tr.(y_field);
% 
% d_best = lap_traces(1).dist(:);
% y_best = lap_traces(1).data(:);
% if isempty(d_best) || isempty(y_best), continue; end
% 
% h_best = plot(ax, d_best, y_best, '-', 'Color', col, 'LineWidth', lw);
% lbl = build_label(entry, pd, 1, driver_map);
% if ~any(strcmp(leg_seen, lbl))
%     leg_h(end+1)    = h_best; %#ok
%     leg_l{end+1}    = sprintf('%s  [%.2fs]', lbl, tr.lap_times(1)); %#ok
%     leg_seen{end+1} = lbl; %#ok
% end
% 
% for k = 2:n_show
                lap_traces = tr.(y_field);

                % Select best lap — exclude lap 0 (pitlane/install lap in non-race sessions)
                valid_k = find(tr.lap_numbers >= -1 & isfinite(tr.lap_times));
                if isempty(valid_k)
                    valid_k = 1:tr.n_traces;   % fallback: use all
                end
                [~, rel_best] = min(tr.lap_times(valid_k));
                best_k = valid_k(rel_best);

                n_show = tr.n_traces;
                d_best = lap_traces(best_k).dist(:);
                y_best = lap_traces(best_k).data(:);
                if isempty(d_best) || isempty(y_best), continue; end

                h_best = plot(ax, d_best, y_best, '-', 'Color', col, 'LineWidth', lw);
                lbl = build_label(entry, pd, 1, driver_map);
                if ~any(strcmp(leg_seen, lbl))
                    leg_h(end+1) = h_best; %#ok
                    drv_str  = strrep(entry.driver, '_', ' ');
                    lap_str  = sprintf('Lap %d | %.3fs', tr.lap_numbers(best_k), tr.lap_times(best_k));
                    if numel(pd.y_channels) > 1
                        leg_l{end+1} = sprintf('%s  (%s)  [%s]  [%s]', lbl, drv_str, pd.y_channels{1}, lap_str); %#ok
                    else
                        leg_l{end+1} = sprintf('%s  (%s)  [%s]', lbl, drv_str, lap_str); %#ok
                    end
                    leg_seen{end+1} = lbl; %#ok
                end
% background laps not being plotted 
%                 for k = 1:n_show
%                     if k == best_k, continue; end
%                     d_k=lap_traces(k).dist(:); y_k=lap_traces(k).data(:);
%                     if isempty(d_k)||isempty(y_k), continue; end
%                     plot(ax,d_k,y_k,'-','Color',[col,0.25],'LineWidth',lwa);
%                 end
            end

        else
            laps = entry.laps;
            if isempty(laps), continue; end
            lap_times = [laps.lap_time];
            [~, best] = min(lap_times);
            ch_names_b = fieldnames(laps(best).channels);
            if isempty(ch_names_b) || ~isfield(laps(best).channels.(ch_names_b{1}), 'dist')
                fprintf('  [WARN] .dist not found for %s — delete cache and recompile.\n', entry.driver);
                continue;
            end
            ref_ch = laps(best).channels.(ch_names_b{1});
            d_grid = ref_ch.dist(:);
            n_pts  = numel(d_grid);

            for yi = 1:numel(pd.y_channels)
                y_ch    = pd.y_channels{yi};
                y_field = find_ch_field(laps(best).channels, y_ch);
                if isempty(y_field)
                    fprintf('  [WARN] Channel "%s" not found for %s\n', y_ch, entry.driver);
                    continue;
                end
                y_best = laps(best).channels.(y_field).data(:);
                if numel(y_best) ~= n_pts
                    fprintf('  [WARN] Size mismatch: %s %d vs dist %d for %s\n', ...
                        y_ch, numel(y_best), n_pts, entry.driver);
                    continue;
                end
                h_best = plot(ax, d_grid, y_best, '-', 'Color', col, 'LineWidth', lw);
                leg_h(end+1)=h_best; leg_l{end+1}=sprintf('%s  [fastest]', entry.driver); %#ok

                if n_laps_avg > 1 && numel(laps) >= n_laps_avg
                    [~, sorted_idx] = sort(lap_times,'ascend');
                    avg_idx = sorted_idx(1:n_laps_avg);
                    lap_mat = NaN(n_pts, n_laps_avg);
                    for k = 1:n_laps_avg
                        li = avg_idx(k);
                        yf_li = find_ch_field(laps(li).channels, y_ch);
                        if isempty(yf_li), continue; end
                        y_k = laps(li).channels.(yf_li).data(:);
                        if numel(y_k) == n_pts, lap_mat(:,k) = y_k; end
                        plot(ax,d_grid,lap_mat(:,k),'-','Color',[col,0.25],'LineWidth',lwa);
                    end
                    y_avg = mean(lap_mat,2,'omitnan');
                    h_avg = plot(ax,d_grid,y_avg,'--','Color',col,'LineWidth',lw);
                    leg_h(end+1)=h_avg; leg_l{end+1}=sprintf('%s  [%d-lap avg]',entry.driver,n_laps_avg); %#ok
                    y_p25=prctile(lap_mat,25,2); y_p75=prctile(lap_mat,75,2);
                    vb=~isnan(y_p25)&~isnan(y_p75);
                    if any(vb)
                        fill(ax,[d_grid(vb);flipud(d_grid(vb))],[y_p25(vb);flipud(y_p75(vb))], ...
                            col,'FaceAlpha',0.15,'EdgeColor','none');
                    end
                end
            end
        end
    end

    xlabel(ax, 'Distance (m)', 'FontSize', fs, 'Interpreter','none');
    ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter','none');
    apply_legend(ax, leg_h, leg_l, opts);
end

function fig = make_timeseries_align(run_list, pd, colour_cfg, driver_map, opts, ax_in, ~)
% Plots fastest lap traces from entry.traces, aligned via peak-shift on raw data.
% No resampling — each trace plots on its own native distance axis, shifted so
% the dominant peak of the alignment channel sits at a common reference point.

    if nargin < 6, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs  = get_opt(opts, 'font_size', 11);
    lw  = 2.0;

    align_ch = '';
    if isfield(pd, 'align_channel'), align_ch = pd.align_channel; end
    align_win = [];
    if isfield(pd, 'align_window') && numel(pd.align_window) == 2
        align_win = pd.align_window(:)';
    end
    max_offset = 60;
    if isfield(pd, 'align_max_offset') && isfinite(pd.align_max_offset)
        max_offset = pd.align_max_offset;
    end

    n         = numel(run_list);
    offsets_m = zeros(1, n);
    valid     = false(1, n);

    % ---- Validate: each run must have traces with the first y-channel ----
    y0_field = sanitise_fn(pd.y_channels{1});
    for r = 1:n
        tr = run_list(r).traces;
        if isempty(tr) || ~isstruct(tr), continue; end
        if ~isfield(tr, y0_field),       continue; end
        if isempty(tr.(y0_field)),        continue; end
        if ~isfield(tr.(y0_field)(1), 'dist') || isempty(tr.(y0_field)(1).dist)
            continue;
        end
        valid(r) = true;
    end

    valid_idx = find(valid);
    if numel(valid_idx) < 2
        warning('make_timeseries_align: fewer than 2 runs with valid traces for "%s".', ...
                pd.y_channels{1});
        return;
    end

    % ---- Compute peak-based offsets on raw data ----
    ref           = valid_idx(1);
    align_field   = sanitise_fn(align_ch);
    ref_peak_dist = NaN;

    if ~isempty(align_ch)
        tr_ref = run_list(ref).traces;
        if isfield(tr_ref, align_field) && ~isempty(tr_ref.(align_field))
            d_ref = tr_ref.(align_field)(1).dist(:);
            v_ref = tr_ref.(align_field)(1).data(:);
            if ~isempty(align_win)
                mask = d_ref >= align_win(1) & d_ref <= align_win(2);
            else
                mask = true(size(d_ref));
            end
            if sum(mask) >= 5
                [~, pk_idx]   = max(v_ref(mask));
                d_masked      = d_ref(mask);
                ref_peak_dist = d_masked(pk_idx);
            end
        end

        if isnan(ref_peak_dist)
            warning('make_timeseries_align: could not find peak in reference run — no alignment applied.');
        else
            fprintf('  Align reference peak at %.1fm\n', ref_peak_dist);
            for r = valid_idx(2:end)
                tr = run_list(r).traces;
                if ~isfield(tr, align_field) || isempty(tr.(align_field)), continue; end
                d_raw = tr.(align_field)(1).dist(:);
                v_raw = tr.(align_field)(1).data(:);
                if ~isempty(align_win)
                    mask = d_raw >= align_win(1) & d_raw <= align_win(2);
                else
                    mask = true(size(d_raw));
                end
                if sum(mask) < 5, continue; end
                [~, pk_idx]   = max(v_raw(mask));
                d_masked      = d_raw(mask);
                car_peak_dist = d_masked(pk_idx);
                offset_m      = ref_peak_dist - car_peak_dist;
                if abs(offset_m) > max_offset
                    warning('make_timeseries_align: %s offset %.1fm capped at %.0fm.', ...
                            run_list(r).driver, offset_m, max_offset);
                    offset_m = sign(offset_m) * max_offset;
                end
                offsets_m(r) = offset_m;
                fprintf('  Align %s vs %s: %+.1fm\n', ...
                        run_list(r).driver, run_list(ref).driver, offset_m);
            end
        end
    else
        fprintf('  [timeseries_align] No align_channel set — plotting without alignment.\n');
    end

    % ---- Compute global x range across all valid runs and channels ----
    % Done before plotting so xlim can be set once cleanly after all traces.
    x_max = 0;
    for r = valid_idx
        tr = run_list(r).traces;
        for yi = 1:numel(pd.y_channels)
            yf = sanitise_fn(pd.y_channels{yi});
            if ~isfield(tr, yf) || isempty(tr.(yf)), continue; end
            d = tr.(yf)(1).dist(:);
            if ~isempty(d)
                x_max = max(x_max, max(d) + offsets_m(r));
            end
        end
    end

    % ---- Plot each trace on its native axis + shift ----
    leg_h = []; leg_l = {}; leg_seen = {};

    for r = valid_idx
        entry = run_list(r);
        col   = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
        tr    = entry.traces;
        for yi = 1:numel(pd.y_channels)
            yf = sanitise_fn(pd.y_channels{yi});
            if ~isfield(tr, yf) || isempty(tr.(yf)), continue; end
            d_raw = tr.(yf)(1).dist(:);
            v_raw = tr.(yf)(1).data(:);
            if isempty(d_raw) || isempty(v_raw), continue; end
            h = plot(ax, d_raw + offsets_m(r), v_raw, '-', 'Color', col, 'LineWidth', lw);
            lbl = entry.driver;
            if ~any(strcmp(leg_seen, lbl))
                leg_h(end+1) = h; %#ok
                lap_num_str = '';
                if isfield(tr, 'lap_numbers') && numel(tr.lap_numbers) >= 1
                    lap_num_str = sprintf('Lap %d  |  ', tr.lap_numbers(1));
                end
                lap_time_str = '';
                if isfield(tr, 'lap_times') && numel(tr.lap_times) >= 1
                    lap_time_str = sprintf('  [%s%.3fs]', lap_num_str, tr.lap_times(1));
                end
                if offsets_m(r) ~= 0
                    leg_l{end+1} = sprintf('%s%s  [%+.1fm]', lbl, lap_time_str, offsets_m(r)); %#ok
                else
                    leg_l{end+1} = sprintf('%s%s', lbl, lap_time_str); %#ok
                end
                leg_seen{end+1} = lbl; %#ok
            end
        end
    end

    % ---- Mark alignment window ----
    if ~isempty(align_win)
        xline(ax, align_win(1), '--k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
        xline(ax, align_win(2), '--k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
    end

    % ---- Axis labels, legend, xlim ----
    if x_max > 0
        xlim(ax, [0, x_max]);
    end
    xlabel(ax, 'Distance (m)', 'FontSize', fs, 'Interpreter', 'none');
    ylabel(ax, strjoin(pd.y_channels,' / '), 'FontSize', fs, 'Interpreter', 'none');
    apply_legend(ax, leg_h, leg_l, opts);
end

function y_out = align_interp(d_raw, v_raw, dist_vec)
% Resample v_raw (already on its own distance axis d_raw) onto dist_vec.
    y_out = [];
    n_min = min(numel(d_raw), numel(v_raw));
    if n_min < 2, return; end
    d = d_raw(1:n_min);
    v = v_raw(1:n_min);
    mono = [true; diff(d) > 0];
    d = d(mono); v = v(mono);
    if numel(d) < 2, return; end
    dq    = min(max(dist_vec, d(1)), d(end));
    y_out = interp1(d, v, dq, 'linear');
end

function field = local_find_field(ch_struct, name)
    san    = regexprep(name, '[^a-zA-Z0-9_]', '_');
    fnames = fieldnames(ch_struct);
    field  = '';
    for i  = 1:numel(fnames)
        if strcmpi(fnames{i}, name) || strcmpi(fnames{i}, san)
            field = fnames{i}; return;
        end
    end
end

function [locs, prom] = local_peaks_simple(sig, min_prom)
% Toolbox-free peak finder — returns indices and prominences of local maxima.
% min_prom: minimum prominence threshold (default 0 = return all peaks)
    if nargin < 2, min_prom = 0; end
    n    = numel(sig);
    locs = []; prom = [];
    if n < 3, return; end
    is_pk = false(n,1);
    for k = 2:n-1
        if sig(k) > sig(k-1) && sig(k) > sig(k+1), is_pk(k) = true; end
    end
    cands = find(is_pk);
    if isempty(cands), return; end
    p = zeros(numel(cands),1);
    sv = sig(cands);
    for j = 1:numel(cands)
        k    = cands(j);
        pkv  = sig(k);
        tl   = cands(sv >= pkv & (1:numel(cands))' < j);
        tr   = cands(sv >= pkv & (1:numel(cands))' > j);
        lb   = min(sig(1:k));           if ~isempty(tl), lb = min(sig(tl(end):k)); end
        rb   = min(sig(k:n));           if ~isempty(tr), rb = min(sig(k:tr(1)));   end
        p(j) = pkv - max(lb, rb);
    end
    % Apply minimum prominence filter
    keep  = p >= min_prom;
    locs  = cands(keep);
    prom  = p(keep);
end



function fig = make_align(run_list, pd, colour_cfg, driver_map, opts, ax_in)
    if nargin < 6, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs  = get_opt(opts, 'font_size', 11);
    lw  = 2.0;

    % --- Alignment params from pd ---
    % x_lim doubles as the alignment window here
    align_window     = [];
    if isfield(pd, 'align_window') && numel(pd.align_window) == 2 && all(isfinite(pd.align_window))
        align_window = pd.align_window(:)';
    end

    peak_min_prom    = get_opt(opts, 'align_peak_min_prom',  2);
    peak_min_sep_m   = get_opt(opts, 'align_peak_min_sep_m', 10);
    max_offset_m     = get_opt(opts, 'align_max_offset_m',   60);
    dist_res         = get_opt(opts, 'align_dist_res',        1);   % m

    align_ch = '';
    if isfield(pd, 'align_channel') && ~isempty(pd.align_channel)
        align_ch = pd.align_channel;
    end

    leg_h = []; leg_l = {}; leg_seen = {};

    % ------------------------------------------------------------------ %
    %  Pass 1: collect best-lap data + compute alignment offsets
    % ------------------------------------------------------------------ %
    n_runs      = numel(run_list);
    dist_grids  = cell(n_runs, 1);   % resampled distance axis per car
    ch_data     = cell(n_runs, numel(pd.y_channels));  % channel data on dist grid
    align_data  = cell(n_runs, 1);   % alignment channel on dist grid
    offsets_m   = zeros(n_runs, 1);
    labels      = cell(n_runs, 1);
    colours     = cell(n_runs, 1);

    common_len = Inf;

    for r = 1:n_runs
        entry = run_list(r);

        % ---- get best lap channels ----
        if strcmp(entry.mode, 'stream')
            tr = entry.traces;
            if isempty(tr) || ~isstruct(tr) || tr.n_traces == 0, continue; end

            % pick best lap index
            valid_k = find(tr.lap_numbers >= -1 & tr.lap_numbers ~= 0 & isfinite(tr.lap_times));
            if isempty(valid_k), valid_k = 1:tr.n_traces; end
            [~, rel_best] = min(tr.lap_times(valid_k));
            best_k        = valid_k(rel_best);

            % Build distance from stored dist vector in first y-channel trace
            y0_field = sanitise_fn(pd.y_channels{1});
            if ~isfield(tr, y0_field), continue; end
            d_raw = tr.(y0_field)(best_k).dist(:);
            if isempty(d_raw), continue; end

            % Build common dist grid for this car
            common_len = min(common_len, d_raw(end));
            dist_grids{r} = d_raw;

            % Store y-channel data
            for yi = 1:numel(pd.y_channels)
                yf = sanitise_fn(pd.y_channels{yi});
                if isfield(tr, yf)
                    ch_data{r, yi} = tr.(yf)(best_k).data(:);
                end
            end

            % Store alignment channel data
            if ~isempty(align_ch)
                af = sanitise_fn(align_ch);
                if isfield(tr, af)
                    align_data{r} = tr.(af)(best_k).data(:);
                end
            end

        else
            % bulk mode
            laps = entry.laps;
            if isempty(laps), continue; end
            lap_times = [laps.lap_time];
            [~, best] = min(lap_times);

            ch_names_b = fieldnames(laps(best).channels);
            if isempty(ch_names_b) || ~isfield(laps(best).channels.(ch_names_b{1}), 'dist')
                fprintf('  [WARN] .dist not found for %s\n', entry.driver);
                continue;
            end
            ref_ch = laps(best).channels.(ch_names_b{1});
            d_raw  = ref_ch.dist(:);
            common_len    = min(common_len, d_raw(end));
            dist_grids{r} = d_raw;

            for yi = 1:numel(pd.y_channels)
                yf = find_ch_field(laps(best).channels, pd.y_channels{yi});
                if ~isempty(yf)
                    ch_data{r, yi} = laps(best).channels.(yf).data(:);
                end
            end

            if ~isempty(align_ch)
                af = find_ch_field(laps(best).channels, align_ch);
                if ~isempty(af)
                    align_data{r} = laps(best).channels.(af).data(:);
                end
            end
        end

        labels{r}  = build_label(entry, pd, 1, driver_map);
        colours{r} = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
    end

    % ------------------------------------------------------------------ %
    %  Pass 2: resample everything onto a common 1m grid, compute offsets
    % ------------------------------------------------------------------ %
    if isinf(common_len) || common_len <= 0
        warning('timeseries_align: no valid data found.'); return;
    end

    dist_vec  = (0 : dist_res : common_len)';
    n_pts     = numel(dist_vec);

    align_on_grid = cell(n_runs, 1);
    ch_on_grid    = cell(n_runs, numel(pd.y_channels));

    for r = 1:n_runs
        if isempty(dist_grids{r}), continue; end
        d_raw = dist_grids{r};

        % resample alignment channel
        if ~isempty(align_data{r}) && ~isempty(align_ch)
            a_vals = align_data{r};
            n_min  = min(numel(d_raw), numel(a_vals));
            d_r    = d_raw(1:n_min);
            a_r    = a_vals(1:n_min);
            mono   = [true; diff(d_r) > 0];
            d_r    = d_r(mono); a_r = a_r(mono);
            dq     = min(max(dist_vec, d_r(1)), d_r(end));
            align_on_grid{r} = interp1(d_r, a_r, dq, 'linear');
        end

        % resample y channels
        for yi = 1:numel(pd.y_channels)
            if isempty(ch_data{r, yi}), continue; end
            y_vals = ch_data{r, yi};
            n_min  = min(numel(d_raw), numel(y_vals));
            d_r    = d_raw(1:n_min);
            y_r    = y_vals(1:n_min);
            mono   = [true; diff(d_r) > 0];
            d_r    = d_r(mono); y_r = y_r(mono);
            dq     = min(max(dist_vec, d_r(1)), d_r(end));
            ch_on_grid{r, yi} = interp1(d_r, y_r, dq, 'linear');
        end
    end

    % ------------------------------------------------------------------ %
    %  Compute peak-based offsets (alignTrack 'peaks' method)
    % ------------------------------------------------------------------ %
    peak_min_sep_samples = max(1, round(peak_min_sep_m / dist_res));
    peak_dists = NaN(n_runs, 1);

    if ~isempty(align_ch) && ~isempty(align_window)
        win_mask = dist_vec >= align_window(1) & dist_vec <= align_window(2);
        win_dist = dist_vec(win_mask);
        if sum(win_mask) >= 5
            ref_r = [];
            for r = 1:n_runs
                if ~isempty(align_on_grid{r})
                    ref_r = r; break;
                end
            end

            for r = 1:n_runs
                if isempty(align_on_grid{r}), continue; end
                sig = align_on_grid{r}(win_mask);
                [locs, prom] = align_local_peaks(sig, peak_min_sep_samples, peak_min_prom);
                if isempty(locs)
                    [~, locs] = max(sig);
                    prom      = 0;
                    warning('timeseries_align: car %d no peak met prominence — using global max.', r);
                end
                [~, best_pk]  = max(prom);
                peak_dists(r) = win_dist(locs(best_pk));
                fprintf('  [align] %s: peak at %.1fm\n', labels{r}, peak_dists(r));
            end

            if ~isnan(peak_dists(ref_r))
                for r = 1:n_runs
                    if r == ref_r || isnan(peak_dists(r)), continue; end
                    off = peak_dists(ref_r) - peak_dists(r);
                    if abs(off) > max_offset_m
                        warning('timeseries_align: %s offset %.1fm capped at %.0fm.', labels{r}, off, max_offset_m);
                        off = sign(off) * max_offset_m;
                    end
                    offsets_m(r) = off;
                    fprintf('  [align] %s offset: %+.1fm\n', labels{r}, off);
                end
            end
        else
            warning('timeseries_align: alignment window too small (%d pts) — no alignment applied.', sum(win_mask));
        end
    else
        if isempty(align_ch)
            fprintf('  [timeseries_align] No yAxis2 channel — plotting without alignment.\n');
        else
            fprintf('  [timeseries_align] No alignWindow set — plotting without alignment.\n');
        end
    end

    % ------------------------------------------------------------------ %
    %  Pass 3: Plot with offset applied to x-axis
    % ------------------------------------------------------------------ %
    for r = 1:n_runs
        if isempty(labels{r}), continue; end
        col = colours{r};
        dv  = dist_vec + offsets_m(r);

        for yi = 1:numel(pd.y_channels)
            if isempty(ch_on_grid{r, yi}), continue; end
            h = plot(ax, dv, ch_on_grid{r, yi}, '-', 'Color', col, 'LineWidth', lw);

            lbl = labels{r};
            if ~any(strcmp(leg_seen, lbl))
                leg_h(end+1)    = h; %#ok
                if offsets_m(r) ~= 0
                    leg_l{end+1} = sprintf('%s  [%+.1fm]', lbl, offsets_m(r)); %#ok
                else
                    leg_l{end+1} = lbl; %#ok
                end
                leg_seen{end+1} = lbl; %#ok
            end
        end
    end

    % Mark alignment window
    if ~isempty(align_window)
        xline(ax, align_window(1), '--k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
        xline(ax, align_window(2), '--k', 'LineWidth', 0.8, 'HandleVisibility', 'off');
    end

    xlabel(ax, 'Distance (m)', 'FontSize', fs, 'Interpreter', 'none');
    ylabel(ax, strjoin(pd.y_channels, ' / '), 'FontSize', fs, 'Interpreter', 'none');
    apply_legend(ax, leg_h, leg_l, opts);
end


% ======================================================================= %
%  LOCAL PEAK FINDER (self-contained copy — no toolbox needed)
%  Identical logic to alignTrack.m's local_peaks
% ======================================================================= %
function [locs, prom] = align_local_peaks(sig, min_sep, min_prom)
    n    = numel(sig);
    locs = []; prom = [];
    if n < 3, return; end

    is_peak = false(n, 1);
    for k = 2:n-1
        if sig(k) > sig(k-1) && sig(k) > sig(k+1)
            is_peak(k) = true;
        end
    end
    cands = find(is_peak);
    if isempty(cands), return; end

    sig_cands = sig(cands);
    n_cands   = numel(cands);
    p         = zeros(n_cands, 1);

    for j = 1:n_cands
        k    = cands(j);
        pk_v = sig(k);
        taller_left = cands(1:j-1);
        taller_left = taller_left(sig_cands(1:j-1) >= pk_v);
        if isempty(taller_left), left_base = min(sig(1:k));
        else,                    left_base = min(sig(taller_left(end):k)); end

        taller_right = cands(j+1:end);
        taller_right = taller_right(sig_cands(j+1:end) >= pk_v);
        if isempty(taller_right), right_base = min(sig(k:n));
        else,                     right_base = min(sig(k:taller_right(1))); end

        p(j) = pk_v - max(left_base, right_base);
    end

    keep  = p >= min_prom;
    cands = cands(keep);
    p     = p(keep);
    if isempty(cands), return; end

    [~, sort_idx] = sort(p, 'descend');
    kept = false(numel(cands), 1);
    for j = 1:numel(sort_idx)
        idx = sort_idx(j);
        if ~any(kept & abs(cands - cands(idx)) < min_sep)
            kept(idx) = true;
        end
    end
    locs = sort(cands(kept));
    prom = p(kept);
end

% ======================================================================= %
%  DISTRIBUTION DATA HELPER
% ======================================================================= %
function vals = get_dist_vals(entry, y_field, math_fn)
    agg_fns = {'max','min','mean','variance','var', ...
               'mean non zero','min non zero','max non zero', ...
               'median non zero','std non zero'};
    if ismember(lower(math_fn), agg_fns)
        vals = local_apply_math(entry.stats.(y_field), math_fn);
        vals = vals(isfinite(vals));
    else
        if isempty(entry.laps)
            warning('get_dist_vals: math_fn "%s" requires raw laps (bulk mode only).', math_fn);
            vals = []; return;
        end
        vals = [];
        for k = 1:numel(entry.laps)
            ch_field = find_ch_field(entry.laps(k).channels, y_field);
            if isempty(ch_field), continue; end
            ch = entry.laps(k).channels.(ch_field);
            t  = ch.time;  dt = median(diff(t));
            if isnan(dt) || dt <= 0, dt = 1; end
            v = local_apply_math_sample(ch.data, math_fn, dt);
            vals = [vals; v(:)]; %#ok
        end
        vals = vals(isfinite(vals));
    end
end


% ======================================================================= %
%  BOXPLOT COLOURING
% ======================================================================= %
function colour_boxplot(bp, colours)
    boxes = findobj(bp,'Tag','Box');
    meds  = findobj(bp,'Tag','Median');
    n = numel(boxes);
    for i = 1:n
        j = n - i + 1;
        if j > size(colours,1), continue; end
        col = colours(j,:);
        patch(get(boxes(i),'XData'), get(boxes(i),'YData'), col, ...
            'FaceAlpha',0.75,'EdgeColor',col*0.7,'LineWidth',1.2);
        set(meds(i),'Color',col*0.5,'LineWidth',2);
    end
end


% ======================================================================= %
%  SHAPE KEY
% ======================================================================= %
function add_shape_key(fig, y_channels, SHAPES, fs)
    names = {'Circle','Square','Triangle','Diamond'};
    lines = {'Shapes:'};
    for i = 1:min(numel(y_channels), numel(SHAPES))
        lines{end+1} = sprintf('  %s = %s', names{i}, y_channels{i}); %#ok
    end
    annotation(fig,'textbox','Units','normalized','Position',[0.01 0.01 0.01 0.01], ...
        'String',lines,'FontSize',fs-2,'FontName','Arial', ...
        'EdgeColor',[0.7 0.7 0.7],'BackgroundColor','white', ...
        'FitBoxToText','on','Interpreter','none');
end


% ======================================================================= %
%  LABEL BUILDER
% ======================================================================= %
function lbl = build_label(entry, pd, yi, driver_map)
% Legend label is driven by pd.differentiator if set to a label mode,
% otherwise falls back to pd.colour_mode. This allows colour and legend
% to be controlled independently from the Excel sheet.
%
% Label modes: 'number'       -> #18
%              'driver'/'tla' -> DRV_TLA (via driver_map) or full name fallback
%              'manufacturer' -> manufacturer name
%              'team'         -> team name
% If differentiator is 'shapes' or empty, colour_mode drives the label.

    if nargin < 4, driver_map = []; end

    % Determine which field drives the label
    diff_lower  = lower(strtrim(char(string(pd.differentiator))));
    label_modes = {'number','driver','tla','manufacturer','team'};
    if ismember(diff_lower, label_modes)
        label_mode = diff_lower;
    else
        label_mode = lower(pd.colour_mode);
    end

    switch label_mode
        case 'manufacturer'
            base = entry.manufacturer;
            if isempty(base), base = entry.driver; end
        case 'team'
            base = entry.team;
            if isempty(base), base = entry.driver; end
        case 'number'
            car = strtrim(char(string(entry.car)));
            if isempty(car), car = entry.driver; end
            base = sprintf('#%s', car);
        otherwise   % 'driver', 'tla', or anything else — resolve TLA
            base = resolve_tla(entry.driver, driver_map);
    end

    if numel(pd.y_channels) > 1
        lbl = sprintf('%s  [%s]', base, pd.y_channels{yi});
    else
        lbl = base;
    end
end


% ======================================================================= %
%  UTILITIES
% ======================================================================= %
function tf = is_keyword(str)
    tf = is_keyword_lap(str) || contains(lower(str),'falling');
end

function tf = is_keyword_lap(str)
    tf = any(strcmpi(str, {'Lap Number','Lap_Number','lap'}));
end

function name = sanitise_fn(ch)
    name = regexprep(strtrim(ch), '[^a-zA-Z0-9]', '_');
    if ~isempty(name) && isstrprop(name(1),'digit'), name = ['ch_', name]; end
end

function field = find_ch_field(channels, name)
    if isfield(channels, name), field = name; return; end
    san = regexprep(name, '[^a-zA-Z0-9_]', '_');
    if isfield(channels, san), field = san; return; end
    ch_names = fieldnames(channels);
    for i = 1:numel(ch_names)
        if strcmpi(ch_names{i}, name) || strcmpi(ch_names{i}, san)
            field = ch_names{i}; return;
        end
    end
    field = '';
end

function v = get_opt(s, f, default)
    if isfield(s,f) && ~isempty(s.(f)), v = s.(f);
    else,                                v = default; end
end


% ======================================================================= %
%  MATH HELPERS
% ======================================================================= %
function vals = local_apply_math(stat, math_fn)
    switch lower(strtrim(math_fn))
        case 'max',                vals = stat.max;
        case 'min',                vals = stat.min;
        case {'mean','average'},   vals = stat.mean;
        case {'variance','var'},   vals = stat.var;
        case {'derivative','diff'},vals = gradient(stat.max);
        case {'integral','int'},   vals = cumtrapz(stat.max);
        case 'mean non zero'
            if isfield(stat,'mean_non_zero'), vals = stat.mean_non_zero;
            else, vals = stat.mean; warning('local_apply_math: mean_non_zero not in stats.'); end
        case 'min non zero'
            if isfield(stat,'min_non_zero'),  vals = stat.min_non_zero;
            else, vals = stat.min;  warning('local_apply_math: min_non_zero not in stats.');  end
        case 'max non zero'
            if isfield(stat,'max_non_zero'),  vals = stat.max_non_zero;
            else, vals = stat.max;  warning('local_apply_math: max_non_zero not in stats.');  end
        case 'median non zero'
            if isfield(stat,'median_non_zero'), vals = stat.median_non_zero;
            else, vals = stat.mean; warning('local_apply_math: median_non_zero not in stats.'); end
        case 'std non zero'
            if isfield(stat,'std_non_zero'),  vals = stat.std_non_zero;
            else, vals = stat.max;  warning('local_apply_math: std_non_zero not in stats.');  end
        otherwise
            warning('local_apply_math: unknown "%s" — using max.', math_fn);
            vals = stat.max;
    end
end

function result = local_apply_math_sample(data, math_fn, dt)
    if nargin < 3, dt = 1; end
    d = data(:);  d_fin = d(isfinite(d));
    if isempty(d_fin), result = NaN; return; end
    switch lower(math_fn)
        case 'max',                result = max(d_fin);
        case 'min',                result = min(d_fin);
        case {'mean','average'},   result = mean(d_fin);
        case {'variance','var'},   result = var(d_fin);
        case {'derivative','diff'},result = gradient(d, dt);
        case {'integral','int'},   result = cumtrapz(d) * dt;
        otherwise
            warning('local_apply_math_sample: unknown "%s".', math_fn); result = NaN;
    end
end

function col = local_driver_colour(driver_map, name)
    col = [0.55 0.55 0.55];
    if isempty(driver_map) || ~isstruct(driver_map), return; end
    name_lower = lower(strtrim(name));
    name_strip = regexprep(name_lower, '[^a-z0-9]', '');
    keys = fieldnames(driver_map);
    for k = 1:numel(keys)
        entry = driver_map.(keys{k});
        for a = 1:numel(entry.aliases)
            alias_raw   = entry.aliases{a};
            alias_strip = regexprep(alias_raw, '[^a-z0-9]', '');
            if strcmp(name_lower, alias_raw) || strcmp(name_strip, alias_strip)
                col = entry.colour; return;
            end
        end
    end
end

% function car = resolve_car_number(driver_name, driver_map, fallback)
%     car = fallback;
%     if isempty(driver_map) || ~isstruct(driver_map), return; end
%     name_lower = lower(strtrim(driver_name));
%     keys = fieldnames(driver_map);
%     for k = 1:numel(keys)
%         entry = driver_map.(keys{k});
%         if any(strcmp(entry.aliases, name_lower))
%             if isfield(entry, 'num') && ~isempty(entry.num), car = entry.num; end
%             return;
%         end
%     end
% end
function car = resolve_car_number(driver_name, driver_map, fallback)
    car = fallback;
    if isempty(driver_map) || ~isstruct(driver_map), return; end
    name_lower  = lower(strtrim(driver_name));
    name_strip  = regexprep(name_lower, '[^a-z0-9]', '');
    keys = fieldnames(driver_map);
    for k = 1:numel(keys)
        entry = driver_map.(keys{k});
        for a = 1:numel(entry.aliases)
            alias_strip = regexprep(entry.aliases{a}, '[^a-z0-9]', '');
            if strcmp(name_lower, entry.aliases{a}) || strcmp(name_strip, alias_strip)
                if isfield(entry, 'num') && ~isempty(entry.num)
                    car = entry.num;
                end
                return;
            end
        end
    end
    % No match found — using MoTeC fallback
    fprintf('  [WARN] resolve_car_number: no alias match for "%s" — using fallback "%s"\n', ...
        driver_name, fallback);
end

% ======================================================================= %
%  ROBUST DISTANCE INTERPOLATION
% ======================================================================= %
function y_out = interp_onto_dist(t_dist, d_raw, t_y, y_raw, d_grid)
    n_pts = numel(d_grid);
    y_out = NaN(n_pts, 1);
    d_raw=d_raw(:); t_dist=t_dist(:); y_raw=y_raw(:); t_y=t_y(:);
    ok_d = isfinite(d_raw) & isfinite(t_dist);
    ok_y = isfinite(y_raw) & isfinite(t_y);
    if sum(ok_d)<2 || sum(ok_y)<2, return; end
    d_raw=d_raw(ok_d); t_dist=t_dist(ok_d);
    y_raw=y_raw(ok_y); t_y=t_y(ok_y);
    mono=[true; diff(d_raw)>0];
    d_raw=d_raw(mono); t_dist=t_dist(mono);
    if numel(d_raw)<2, return; end
    t_clip=min(max(t_y,t_dist(1)),t_dist(end));
    d_at_y=interp1(t_dist,d_raw,t_clip,'linear');
    mono2=[true; diff(d_at_y)>0];
    d_at_y=d_at_y(mono2); y_raw=y_raw(mono2);
    if numel(d_at_y)<2, return; end
    d_q=min(max(d_grid,d_at_y(1)),d_at_y(end));
    y_interp=interp1(d_at_y,y_raw,d_q,'linear');
    y_interp(d_grid<d_at_y(1)|d_grid>d_at_y(end))=NaN;
    y_out=y_interp(:);
end

% ======================================================================= %
%  BIG SCATTER
% ======================================================================= %
function fig = make_big_scatter(run_list, pd, colour_cfg, driver_map, opts, SHAPES, ax_in)
% MAKE_BIG_SCATTER  Multi-session scatter with continuous lap-number x axis.
%
% Sessions are laid out left-to-right in the order they appear in run_list
% (which reflects SESSION_FILTER order). A dashed vertical separator is
% drawn at max_laps_in_session + 1 between sessions. Session name and venue
% are drawn as centred labels below the x axis. X ticks are thinned
% dynamically so they never become crowded (minimum every 3 laps).

    if nargin < 7, ax_in = []; end
    [fig, ax] = new_fig(pd, opts, ax_in);
    fs    = get_opt(opts, 'font_size', 11);
    venue = get_opt(opts, 'venue',     '');

    y_ch    = pd.y_channels{1};
    y_field = sanitise_fn(y_ch);

    % ------------------------------------------------------------------
    %  Pass 1 — determine session order and max laps per session
    % ------------------------------------------------------------------
    % Preserve the order sessions appear in run_list (= SESSION_FILTER order)
    session_order = {};
    for r = 1:numel(run_list)
        sess = run_list(r).session;
        if ~any(strcmp(session_order, sess))
            session_order{end+1} = sess; %#ok
        end
    end
    n_sessions = numel(session_order);

    % Max lap number per session across all runs
    sess_max_lap = zeros(1, n_sessions);
    for r = 1:numel(run_list)
        entry = run_list(r);
        if ~isfield(entry.stats, y_field), continue; end
        si = find(strcmp(session_order, entry.session), 1);
        if isempty(si), continue; end
        lap_nums = entry.stats.(y_field).lap_numbers;
        valid    = isfinite(local_apply_math(entry.stats.(y_field), pd.math_fn));
        lap_nums = lap_nums(valid);
        if ~isempty(lap_nums)
            sess_max_lap(si) = max(sess_max_lap(si), max(lap_nums));
        end
    end

    % ------------------------------------------------------------------
    %  Compute global x offset for each session
    %  Session N starts at: sum of (max_laps + 2) for all previous sessions
    %  The +2 creates a gap of 2 laps for the separator
    % ------------------------------------------------------------------
    sess_offset = zeros(1, n_sessions);
    for si = 2:n_sessions
        sess_offset(si) = sess_offset(si-1) + sess_max_lap(si-1) + 2;
    end

    total_laps = sess_offset(end) + sess_max_lap(end);

    % ------------------------------------------------------------------
    %  Pass 2 — plot points
    % ------------------------------------------------------------------
    leg_h = []; leg_l = {}; leg_seen = {};

    for r = 1:numel(run_list)
        entry = run_list(r);
        if ~isfield(entry.stats, y_field), continue; end

        si = find(strcmp(session_order, entry.session), 1);
        if isempty(si), continue; end

        col    = resolve_colour(entry, pd.colour_mode, colour_cfg, driver_map);
        marker = 'o';
        if strcmpi(pd.differentiator, 'shapes') && numel(SHAPES) >= 1
            marker = SHAPES{mod(r-1, numel(SHAPES)) + 1};
        end

        y_vals   = local_apply_math(entry.stats.(y_field), pd.math_fn);
        lap_nums = entry.stats.(y_field).lap_numbers;
        valid    = isfinite(y_vals);
        y_vals   = y_vals(valid);
        lap_nums = lap_nums(valid);
        if isempty(y_vals), continue; end

        % Shift lap numbers to global x axis
        x_vals = lap_nums + sess_offset(si);

        h = scatter(ax, x_vals, y_vals, 36, col, marker, 'filled', ...
            'MarkerEdgeColor', col * 0.7, 'MarkerFaceAlpha', 0.75);

        lbl = build_label(entry, pd, 1, driver_map);
        if ~any(strcmp(leg_seen, lbl))
            leg_h(end+1) = h; leg_l{end+1} = lbl; leg_seen{end+1} = lbl; %#ok
        end
    end

    % ------------------------------------------------------------------
    %  Session separators — dashed vertical lines
    % ------------------------------------------------------------------
    y_lims = ylim(ax);
    for si = 1:n_sessions - 1
        x_sep = sess_offset(si) + sess_max_lap(si) + 1;
        plot(ax, [x_sep x_sep], y_lims, '--', ...
            'Color', [0.5 0.5 0.5], 'LineWidth', 1.2);
    end

    % ------------------------------------------------------------------
    %  X axis ticks — thin dynamically, minimum every 3 laps
    % ------------------------------------------------------------------
    ax_pos   = get(ax, 'Position');
    ax_width = ax_pos(3) * get(fig, 'Position') * [0;0;1;0];  % pixels
    if ax_width <= 0, ax_width = 900; end                      % fallback

    target_ticks  = max(5, round(ax_width / 55));   % ~55px per tick
    raw_step      = total_laps / target_ticks;
    step          = max(3, ceil(raw_step / 3) * 3); % round up to multiple of 3

    tick_vals = 1 : step : total_laps;
    % Filter out ticks that fall in separator gaps
    in_gap = false(size(tick_vals));
    for si = 1:n_sessions - 1
        gap_lo = sess_offset(si) + sess_max_lap(si) + 0.5;
        gap_hi = sess_offset(si) + sess_max_lap(si) + 1.5;
        in_gap = in_gap | (tick_vals >= gap_lo & tick_vals <= gap_hi);
    end
    tick_vals = tick_vals(~in_gap);

    % Convert global x back to local lap numbers for tick labels
    tick_lbls = cell(size(tick_vals));
    for k = 1:numel(tick_vals)
        xg = tick_vals(k);
        % Find which session this tick belongs to
        for si = n_sessions : -1 : 1
            if xg >= sess_offset(si)
                local_lap = xg - sess_offset(si);
                tick_lbls{k} = num2str(round(local_lap));
                break;
            end
        end
    end

    set(ax, 'XTick', tick_vals, 'XTickLabel', tick_lbls, ...
        'XTickLabelRotation', 0);
    xlim(ax, [0 total_laps + 2]);

    % ------------------------------------------------------------------
    %  Layout: shrink axes to leave room for session labels + legend
    % ------------------------------------------------------------------
    % Strip allocation (normalised figure units, bottom to top):
    %   LEG_STRIP   — legend box height (dynamic: scales with n_rows)
    %   VENUE_STRIP — venue label row (SMP)
    %   SESS_STRIP  — session label row height (RA1/RA2/RA3)
    %   SESS_GAP    — white space between axes bottom and session label
    ROW_H       = 0.045;   % normalised height per legend row
    VENUE_STRIP = 0.04;
    SESS_STRIP  = 0.04;
    SESS_GAP    = 0.025;

    % Calculate legend rows now so LEG_STRIP is sized correctly
    n_leg_items  = numel(leg_h);
    n_leg_cols   = min(8, max(1, n_leg_items));
    n_leg_rows   = ceil(n_leg_items / n_leg_cols);
    LEG_STRIP    = max(ROW_H, n_leg_rows * ROW_H + 0.01);  % +0.01 for border padding
    TOTAL_STRIP  = LEG_STRIP + VENUE_STRIP + SESS_STRIP + SESS_GAP;

    ax_pos = get(ax, 'Position');
    new_bottom = ax_pos(2) + TOTAL_STRIP;
    new_height = ax_pos(4) - TOTAL_STRIP;
    if new_height > 0.15
        set(ax, 'Position', [ax_pos(1), new_bottom, ax_pos(3), new_height]);
    end

    % Re-read after resize
    ax_pos        = get(ax, 'Position');
    ax_left_norm  = ax_pos(1);
    ax_bot_norm   = ax_pos(2);
    ax_width_norm = ax_pos(3);
    ax_right_norm = ax_left_norm + ax_width_norm;

    xl      = xlim(ax);
    x_range = xl(2) - xl(1);

    % ------------------------------------------------------------------
    %  Session name labels (RA1/RA2/RA3) — row just below axes
    % ------------------------------------------------------------------
    sess_row_y = ax_bot_norm - SESS_GAP - SESS_STRIP;

    for si = 1:n_sessions
        x_centre_data = sess_offset(si) + sess_max_lap(si) / 2;
        x_norm = ax_left_norm + ax_width_norm * (x_centre_data - xl(1)) / x_range;

        annotation(fig, 'textbox', [x_norm - 0.08, sess_row_y, 0.16, SESS_STRIP], ...
            'String',              session_order{si}, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'middle', ...
            'FontSize',            fs, ...
            'FontWeight',          'bold', ...
            'Color',               [0.2 0.2 0.2], ...
            'EdgeColor',           'none', ...
            'FitBoxToText',        'off');
    end

    % ------------------------------------------------------------------
    %  Venue labels (SMP) — row below session labels
    % ------------------------------------------------------------------
    if ~isempty(venue)
        venue_row_y = sess_row_y - VENUE_STRIP;
        for si = 1:n_sessions
            x_centre_data = sess_offset(si) + sess_max_lap(si) / 2;
            x_norm = ax_left_norm + ax_width_norm * (x_centre_data - xl(1)) / x_range;

            annotation(fig, 'textbox', [x_norm - 0.08, venue_row_y, 0.16, VENUE_STRIP], ...
                'String',              venue, ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment',   'middle', ...
                'FontSize',            fs - 1, ...
                'Color',               [0.55 0.55 0.55], ...
                'EdgeColor',           'none', ...
                'FitBoxToText',        'off');
        end
    else
        venue_row_y = sess_row_y;
    end

    % ------------------------------------------------------------------
    %  Horizontal legend box — below venue row, spanning axes width
    % ------------------------------------------------------------------
    % Turn off the default axes legend
    legend(ax, 'off');

    if ~isempty(leg_h)
        leg_box_y = venue_row_y - LEG_STRIP;
        leg_box_h = LEG_STRIP;

        % Draw a light border box for the legend area
        annotation(fig, 'rectangle', ...
            [ax_left_norm, leg_box_y, ax_width_norm, leg_box_h], ...
            'EdgeColor', [0.75 0.75 0.75], 'LineWidth', 0.8, ...
            'FaceColor', [0.98 0.98 0.98]);

        % Use pre-calculated n_leg_cols / n_leg_rows from strip sizing
        n_cols = n_leg_cols;
        n_rows = n_leg_rows;
        col_w  = ax_width_norm / n_cols;
        row_h  = leg_box_h / n_rows;
        dot_r     = 0.007;   % marker radius in normalised units

        for k = 1:n_leg_items
            col_i = mod(k-1, n_cols);
            row_i = floor((k-1) / n_cols);

            item_x = ax_left_norm + col_i * col_w;
            item_y = leg_box_y + leg_box_h - (row_i + 0.5) * row_h;

            % Coloured dot
            try
                ec = get(leg_h(k), 'CData');
                if isnumeric(ec) && numel(ec) == 3
                    dot_col = ec;
                else
                    dot_col = [0.4 0.4 0.4];
                end
            catch
                dot_col = [0.4 0.4 0.4];
            end

            annotation(fig, 'ellipse', ...
                [item_x + 0.005, item_y - dot_r, dot_r*2, dot_r*2], ...
                'Color', dot_col, 'FaceColor', dot_col, 'LineWidth', 0.5);

            % Label text
            annotation(fig, 'textbox', ...
                [item_x + 0.022, item_y - row_h*0.4, col_w - 0.024, row_h*0.8], ...
                'String',              leg_l{k}, ...
                'HorizontalAlignment', 'left', ...
                'VerticalAlignment',   'middle', ...
                'FontSize',            max(fs - 2, 8), ...
                'Color',               [0.15 0.15 0.15], ...
                'EdgeColor',           'none', ...
                'FitBoxToText',        'off', ...
                'Interpreter',         'none');
        end
    end

    % ------------------------------------------------------------------
    %  Axis labels and title
    % ------------------------------------------------------------------
    ylabel(ax, y_ch,   'FontSize', fs, 'Interpreter', 'none');
    title(ax,  pd.name,'FontSize', fs, 'Interpreter', 'none');
    set(ax, 'XLabel', text('String', ''));   % remove 'Lap' xlabel
    apply_axis_limits(ax, pd);
end

% ======================================================================= %
%  DRV_TLA RESOLVER  (used by make_big_scatter)
% ======================================================================= %
function tla = resolve_tla(driver_name, driver_map)
% Return the DRV_TLA for a driver, falling back to the full name if not found.
    tla = driver_name;
    if isempty(driver_map) || ~isstruct(driver_map) || isempty(driver_name)
        return;
    end
    name_lower = lower(strtrim(strrep(driver_name, '_', ' ')));
    keys = fieldnames(driver_map);
    for k = 1:numel(keys)
        entry = driver_map.(keys{k});
        if isfield(entry, 'aliases') && any(strcmp(entry.aliases, name_lower))
            if isfield(entry, 'tla') && ~isempty(entry.tla)
                tla = entry.tla;
            end
            return;
        end
    end
end