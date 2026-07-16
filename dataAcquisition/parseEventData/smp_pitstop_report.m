function pit_figs = smp_pitstop_report(SMP, lap_opts, cfg, driver_map, varargin)
% SMP_PITSTOP_REPORT  Detect pit stops and generate visualisations.
%
% Combines smp_pitstop_detect() + plotPitStops() into a single call.
% Uses the same smp_colours cfg and driver_map as the rest of the pipeline.
%
% Usage:
%   pit_figs = smp_pitstop_report(SMP, lap_opts, cfg, driver_map)
%   pit_figs = smp_pitstop_report(SMP, lap_opts, cfg, driver_map, Name, Value)
%
%   % Append to existing figure list from smp_plot_from_config:
%   figs = smp_plot_from_config(SMP_filtered, plots, cfg, driver_map, plot_opts);
%   figs = smp_pitstop_report(SMP, lap_opts, cfg, driver_map, 'Figs', figs);
%
% ── Required inputs ─────────────────────────────────────────────────────────
%   SMP         - SMP struct from smp_filter() / smp_load_teams()
%   lap_opts    - options struct passed to lap_slicer() for stop detection
%   cfg         - colour config from smp_colours()
%   driver_map  - driver alias struct from smp_driver_alias_load()
%                 (pass [] to use manufacturer colours only)
%
% ── Optional name-value pairs ───────────────────────────────────────────────
%   'Figs'           cell array   Existing figure cell array to append to.
%                                 If provided, pit figures are appended and
%                                 the combined cell is returned. Default: {}
%
%   'FilterDriver'   cell array   DRV_TLA strings to include. Default: all.
%
%   'FilterCategory' char         '2 Tyre' | '4 Tyre' | 'All'. Default: 'All'.
%
%   'FigureSize'     [w h]        Pixel size per figure. Default: [1200 620].
%
%   'Verbose'        logical      Print detection progress. Default: true.
%
%   'Stops'          struct       Pre-computed stops from smp_pitstop_detect().
%                                 Pass this to skip re-detection (saves time).
%
% ── Output ──────────────────────────────────────────────────────────────────
%   pit_figs  - cell array of figure handles (existing Figs + pit figures).
%               Compatible with smp_plot_from_config output format.
%
% ── Figures produced ────────────────────────────────────────────────────────
%   Fig A  - Pit Stop Durations  (2-tyre vs 4-tyre scatter, split subplots)
%   Fig B  - Stop Counts by Type (grouped bar, 2-tyre changes per driver)
%   Fig C  - Pit Stop Timeline   (lap vs driver, bubble = duration)

% ── Parse optional arguments ────────────────────────────────────────────────
p = inputParser();
p.addParameter('Figs',           {});
p.addParameter('FilterDriver',   {});
p.addParameter('FilterCategory', 'All');
p.addParameter('FigureSize',     [1200 620]);
p.addParameter('Verbose',        true);
p.addParameter('Stops',          []);
p.parse(varargin{:});

existing_figs  = p.Results.Figs;
filterDrivers  = p.Results.FilterDriver;
filterCat      = p.Results.FilterCategory;
figSize        = p.Results.FigureSize;
verbose        = p.Results.Verbose;
pre_stops      = p.Results.Stops;

% ── Ensure existing_figs is a cell array ────────────────────────────────────
if ~iscell(existing_figs)
    existing_figs = num2cell(existing_figs);   % handles gobjects array
end

% ── Manufacturer colour map (from smp_colours cfg) ──────────────────────────
MFG_COLOURS = containers.Map( ...
    {'Ford',       'Chev',      'Chevrolet',  'Holden',    ...
     'Toyota',     'Camry',     'GR_Supra',   'Mustang',   'Camaro'}, ...
    {cfg.manufacturer.Ford,   cfg.manufacturer.Chev,   cfg.manufacturer.Chev, ...
     cfg.manufacturer.Chev,  cfg.manufacturer.Toyota, cfg.manufacturer.Toyota, ...
     cfg.manufacturer.Toyota, cfg.manufacturer.Ford,  cfg.manufacturer.Chev});

DEFAULT_COLOUR = cfg.fallback;

% ── Build driver -> manufacturer map (containers.Map) ───────────────────────
mfgMap = build_mfg_map(SMP, driver_map);

% ── Step 1: Detect pit stops ─────────────────────────────────────────────────
if isempty(pre_stops)
    if verbose, fprintf('\n[smp_pitstop_report] Running pit stop detection...\n'); end
    stops_raw = smp_pitstop_detect(SMP, lap_opts);
else
    if verbose, fprintf('\n[smp_pitstop_report] Using pre-computed stops.\n'); end
    stops_raw = pre_stops;
end

% ── Step 2: Flatten stops into pitData format (like readPitData output) ───────
pitData = flatten_stops(stops_raw, SMP, driver_map, mfgMap, verbose);

if isempty(pitData)
    warning('smp_pitstop_report: No pit stops detected — no figures generated.');
    pit_figs = existing_figs;
    return;
end

% ── Step 3: Apply driver filter ───────────────────────────────────────────────
if ~isempty(filterDrivers)
    keep = arrayfun(@(s) ismember(s.driver, filterDrivers), pitData);
    pitData = pitData(keep);
    if isempty(pitData)
        warning('smp_pitstop_report: No data after driver filter.');
        pit_figs = existing_figs;
        return;
    end
end

% ── Step 4: Generate figures ──────────────────────────────────────────────────
new_figs = make_pit_figures(pitData, mfgMap, MFG_COLOURS, DEFAULT_COLOUR, ...
                            filterCat, figSize, cfg);

% ── Step 5: Append to existing figs and return ────────────────────────────────
pit_figs = [existing_figs(:); new_figs(:)];

if verbose
    fprintf('[smp_pitstop_report] %d pit figure(s) generated. Total figs: %d\n', ...
        numel(new_figs), numel(pit_figs));
end

end  % ── end main ────────────────────────────────────────────────────────────


% ============================================================================
%  FIGURE GENERATION
% ============================================================================
function figs = make_pit_figures(pitData, mfgMap, MFG_COLOURS, DEFAULT_COLOUR, ...
                                  filterCat, figSize, cfg) %#ok<INUSD>

ALL_TYPES_2 = {'FL','FR','RL','RR','FL+RL','FR+RR','FL+FR','RR+RL'};
ALL_TYPES_4 = {'4 Tyre'};

figs = {};

% ─────────────────────────────────────────────────────────────────────────────
%  FIGURE A — Stop Durations (2-tyre / 4-tyre scatter, split subplots)
% ─────────────────────────────────────────────────────────────────────────────
figA = make_figure('Pit Stop Durations — All Cars', figSize);
ax2 = subplot(1, 2, 1, 'Parent', figA);
ax4 = subplot(1, 2, 2, 'Parent', figA);
hold(ax2, 'on'); hold(ax4, 'on');
style_ax(ax2, '2-Tyre Stops',  'Change Type', 'Stop Duration [s]');
style_ax(ax4, '4-Tyre Stops',  'Change Type', 'Stop Duration [s]');

handles2 = []; labels2 = {};
handles4 = []; labels4 = {};

for g = 1:numel(pitData)
    car    = pitData(g);
    stops  = car.stops;
    colour = get_car_colour(car, mfgMap, MFG_COLOURS, DEFAULT_COLOUR);

    [stops2, stops4] = split_by_category(stops, filterCat);

    if ~isempty(stops2)
        xPos = get_x_positions(stops2.ChangeType, ALL_TYPES_2);
        h = scatter(ax2, xPos, stops2.StopTime_s, 65, colour, 'filled', ...
                    'MarkerFaceAlpha', 0.78, 'MarkerEdgeColor', 'w', ...
                    'LineWidth', 0.5, 'DisplayName', car.driver);
        if ~ismember(car.driver, labels2)
            labels2{end+1}  = car.driver;
            handles2(end+1) = h;
        end
    end

    if ~isempty(stops4)
        xPos4 = ones(height(stops4), 1) + (rand(height(stops4), 1) - 0.5) * 0.15;
        h4 = scatter(ax4, xPos4, stops4.StopTime_s, 65, colour, 'filled', ...
                     'MarkerFaceAlpha', 0.78, 'MarkerEdgeColor', 'w', ...
                     'LineWidth', 0.5, 'DisplayName', car.driver);
        if ~ismember(car.driver, labels4)
            labels4{end+1}  = car.driver;
            handles4(end+1) = h4;
        end
    end
end

set_x_ticks(ax2, ALL_TYPES_2);
set_x_ticks(ax4, ALL_TYPES_4);
if ~isempty(handles2), legend(ax2, handles2, labels2, 'Location','best','Box','off'); end
if ~isempty(handles4), legend(ax4, handles4, labels4, 'Location','best','Box','off'); end
figs{end+1} = figA;

% ─────────────────────────────────────────────────────────────────────────────
%  FIGURE B — Stop Count Bar Chart (2-tyre change types per driver)
% ─────────────────────────────────────────────────────────────────────────────
figB = make_figure('Pit Stop Counts by Type — 2 Tyre', figSize);
axB  = axes(figB);
hold(axB, 'on');
style_ax(axB, '2-Tyre Stop Counts by Change Type', 'Change Type', 'Number of Stops');

nDrivers = numel(pitData);
nTypes2  = numel(ALL_TYPES_2);
countMat = zeros(nDrivers, nTypes2);

for g = 1:nDrivers
    st2 = pitData(g).stops(pitData(g).stops.TyreCategory == "2 Tyre", :);
    for t = 1:nTypes2
        countMat(g, t) = sum(st2.ChangeType == ALL_TYPES_2{t});
    end
end

barW = 0.8 / max(nDrivers, 1);
for g = 1:nDrivers
    colour  = get_car_colour(pitData(g), mfgMap, MFG_COLOURS, DEFAULT_COLOUR);
    xOffset = (g - (nDrivers+1)/2) * barW;
    bar(axB, (1:nTypes2) + xOffset, countMat(g,:), barW, ...
        'FaceColor', colour, 'DisplayName', pitData(g).driver);
end

set_x_ticks(axB, ALL_TYPES_2);
legend(axB, 'Location','best', 'Box','off');
figs{end+1} = figB;

% ─────────────────────────────────────────────────────────────────────────────
%  FIGURE C — Timeline (lap vs driver, bubble ∝ duration, colour by type)
% ─────────────────────────────────────────────────────────────────────────────
figC  = make_figure('Pit Stop Timeline — All Cars', figSize);
axTL  = axes(figC);
hold(axTL, 'on');
style_ax(axTL, 'Pit Stop Timeline  (bubble size ∝ stop duration)', ...
         'Lap Number', 'Car / Driver');

allTypes     = [ALL_TYPES_2, {'4 Tyre'}];
typeColours  = lines(numel(allTypes));
typeHandles  = containers.Map('KeyType','char','ValueType','any');
yLabels      = cell(1, numel(pitData));

for g = 1:numel(pitData)
    yLabels{g} = pitData(g).driver;
    stops = pitData(g).stops;

    for s = 1:height(stops)
        ct   = char(stops.ChangeType(s));
        tIdx = find(strcmp(allTypes, ct), 1);
        if isempty(tIdx), tIdx = numel(allTypes); end
        c = typeColours(tIdx, :);

        sz = max(40, stops.StopTime_s(s) * 5);
        h  = scatter(axTL, stops.LapNumber(s), g, sz, c, 'filled', ...
                     'MarkerEdgeColor','k','LineWidth',0.5);
        if ~isKey(typeHandles, ct)
            h.DisplayName   = ct;
            typeHandles(ct) = h;
        else
            h.HandleVisibility = 'off';
        end
    end
end

yticks(axTL, 1:numel(pitData));
yticklabels(axTL, yLabels);
axTL.YLim = [0.5, numel(pitData) + 0.5];
grid(axTL, 'on');

if ~isempty(typeHandles)
    k    = keys(typeHandles);
    hArr = cellfun(@(kk) typeHandles(kk), k, 'UniformOutput', false);
    legend(axTL, [hArr{:}], k, 'Location','best','Box','off');
end
figs{end+1} = figC;

end  % make_pit_figures


% ============================================================================
%  FLATTEN smp_pitstop_detect OUTPUT → pitData struct array
% ============================================================================
function pitData = flatten_stops(stops_raw, SMP, driver_map, mfgMap, verbose)
% Converts the nested stops.(team){r} format from smp_pitstop_detect into
% a flat struct array matching the format expected by make_pit_figures.
% Each element: .driver .manufacturer .stops (table)

pitData  = struct('driver',{}, 'manufacturer',{}, 'stops',{});
teams    = fieldnames(stops_raw);

for t = 1:numel(teams)
    tm = teams{t};

    for r = 1:numel(stops_raw.(tm))
        run_stops = stops_raw.(tm){r};
        if isempty(run_stops), continue; end

        % Resolve driver name from SMP metadata
        drv = '';
        try
            drv = strtrim(char(string(SMP.(tm).meta.Driver{r})));
        catch
            drv = tm;
        end

        % Resolve manufacturer
        mfr = '';
        try
            mfr = strtrim(char(string(SMP.(tm).meta.Manufacturer{r})));
        catch
        end

        % Build a table of stops matching plotPitStops expectations
        n = numel(run_stops);
        LapNumber  = zeros(n,1);
        StopTime_s = zeros(n,1);
        FL         = false(n,1);
        FR         = false(n,1);
        RL         = false(n,1);
        RR         = false(n,1);
        ChangeType = strings(n,1);
        TyreCat    = strings(n,1);

        for s = 1:n
            st              = run_stops(s);
            LapNumber(s)    = st.pit_lap;
            StopTime_s(s)   = st.stop_duration;
            FL(s)           = st.tyre_change_FL;
            FR(s)           = st.tyre_change_FR;
            RL(s)           = st.tyre_change_RL;
            RR(s)           = st.tyre_change_RR;
            ChangeType(s)   = build_change_type(FL(s), FR(s), RL(s), RR(s));
            TyreCat(s)      = classify_tyre_cat(FL(s)+FR(s)+RL(s)+RR(s));
        end

        T = table(LapNumber, StopTime_s, FL, FR, RL, RR, ChangeType, TyreCat, ...
                  'VariableNames', {'LapNumber','StopTime_s','FL','FR','RL','RR', ...
                                    'ChangeType','TyreCategory'});

        % Resolve TLA from driver_map if available
        tla = resolve_tla(drv, driver_map);
        if isempty(tla), tla = drv; end

        % Check if this driver is already in pitData (merge runs)
        idx = find(strcmp({pitData.driver}, tla), 1);
        if isempty(idx)
            entry.driver        = tla;
            entry.manufacturer  = mfr;
            entry.stops         = T;
            pitData(end+1) = entry; %#ok
        else
            pitData(idx).stops = [pitData(idx).stops; T];
        end

        if verbose
            fprintf('  [%s] run %d → driver "%s" (%s)  |  %d stop(s)\n', ...
                tm, r, tla, mfr, n);
        end
    end
end
end  % flatten_stops


% ============================================================================
%  BUILD DRIVER -> MANUFACTURER MAP
% ============================================================================
function mfgMap = build_mfg_map(SMP, driver_map)
% Returns a containers.Map of driver_TLA -> manufacturer string.
mfgMap = containers.Map('KeyType','char','ValueType','char');
teams  = fieldnames(SMP);

for t = 1:numel(teams)
    tm = teams{t};
    try
        meta = SMP.(tm).meta;
        nRuns = height(meta);
        for r = 1:nRuns
            drv = strtrim(char(string(meta.Driver{r})));
            mfr = strtrim(char(string(meta.Manufacturer{r})));
            tla = resolve_tla(drv, driver_map);
            if isempty(tla), tla = drv; end
            if ~isempty(tla) && ~isempty(mfr) && ~isKey(mfgMap, tla)
                mfgMap(tla) = mfr;
            end
        end
    catch
    end
end
end


% ============================================================================
%  LOCAL HELPERS
% ============================================================================

function colour = get_car_colour(car, mfgMap, MFG_COLOURS, DEFAULT_COLOUR)
    colour = DEFAULT_COLOUR;
    drv    = car.driver;
    if isKey(mfgMap, drv)
        mfr = mfgMap(drv);
        if isKey(MFG_COLOURS, mfr)
            colour = MFG_COLOURS(mfr);
            return;
        end
    end
    % Fallback: try car.manufacturer directly
    if ~isempty(car.manufacturer) && isKey(MFG_COLOURS, car.manufacturer)
        colour = MFG_COLOURS(car.manufacturer);
    end
end

function [stops2, stops4] = split_by_category(stops, filterCat)
    if strcmpi(filterCat, '2 Tyre')
        stops2 = stops(stops.TyreCategory == "2 Tyre", :);
        stops4 = stops(false(height(stops),1), :);
    elseif strcmpi(filterCat, '4 Tyre')
        stops2 = stops(false(height(stops),1), :);
        stops4 = stops(stops.TyreCategory == "4 Tyre", :);
    else
        stops2 = stops(stops.TyreCategory == "2 Tyre", :);
        stops4 = stops(stops.TyreCategory == "4 Tyre", :);
    end
end

function xPos = get_x_positions(changeTypes, allTypes)
    xPos = zeros(numel(changeTypes), 1);
    for i = 1:numel(changeTypes)
        idx = find(strcmp(allTypes, char(changeTypes(i))), 1);
        xPos(i) = double(~isempty(idx)) * idx + double(isempty(idx)) * (numel(allTypes)+1);
    end
end

function set_x_ticks(ax, labels)
    xticks(ax, 1:numel(labels));
    xticklabels(ax, labels);
    ax.XLim = [0.5, numel(labels) + 0.5];
    xtickangle(ax, 30);
end

function style_ax(ax, ttl, xlbl, ylbl)
    title(ax, ttl, 'FontWeight','bold','Interpreter','none');
    xlabel(ax, xlbl);
    ylabel(ax, ylbl);
    grid(ax, 'on');
    ax.Color      = [0.97 0.97 0.97];
    ax.GridAlpha  = 0.25;
    ax.GridColor  = [0.7 0.7 0.7];
    ax.GridLineStyle = '--';
    ax.FontName   = 'Arial';
    ax.FontSize   = 11;
    box(ax, 'on');
end

function fig = make_figure(name, figSize)
    fig = figure('Name', name, 'NumberTitle','off', 'Visible','off', ...
                 'Color','white', ...
                 'Position', [100 100 figSize(1) figSize(2)]);
end

function ct = build_change_type(fl, fr, rl, rr)
    corners = {};
    if fl, corners{end+1} = 'FL'; end
    if fr, corners{end+1} = 'FR'; end
    if rl, corners{end+1} = 'RL'; end
    if rr, corners{end+1} = 'RR'; end
    n = numel(corners);
    if n == 0
        ct = "No Change";
    elseif n == 4
        ct = "4 Tyre";
    else
        ct = string(strjoin(corners, '+'));
    end
end

function cat = classify_tyre_cat(n_changed)
    if n_changed >= 4
        cat = "4 Tyre";
    elseif n_changed > 0
        cat = "2 Tyre";
    else
        cat = "No Change";
    end
end

function tla = resolve_tla(driver_str, driver_map)
% Try to find a TLA from the driver_map struct.
    tla = '';
    if isempty(driver_map) || ~isstruct(driver_map), return; end
    keys = fieldnames(driver_map);
    name_lower = lower(strtrim(driver_str));
    for k = 1:numel(keys)
        entry = driver_map.(keys{k});
        if isfield(entry, 'aliases')
            for a = 1:numel(entry.aliases)
                if strcmpi(entry.aliases{a}, name_lower)
                    tla = entry.tla;
                    return;
                end
            end
        end
        if isfield(entry, 'tla') && strcmpi(entry.tla, driver_str)
            tla = entry.tla;
            return;
        end
    end
end