function figs = plotPitStops(pitData, varargin)
% PLOTPITSTOPS  Generate pit stop report figures for all cars in pitData.
%
% Usage:
%   figs = plotPitStops(pitData)
%   figs = plotPitStops(pitData, 'Cfg', cfg, 'DriverMap', driver_map)
%   figs = plotPitStops(pitData, 'FilterDriver', {'Driver A','Driver B'})
%   figs = plotPitStops(pitData, 'FilterCategory', '2 Tyre')
%
% Inputs:
%   pitData        - struct array from smp_stops_to_pitdata()
%
% Optional name-value pairs:
%   'Cfg'             - colour config struct from smp_colours()
%                       Used for manufacturer fallback colours.
%   'DriverMap'       - driver alias struct from smp_driver_alias_load()
%                       Driver colours take priority over manufacturer colours.
%   'FilterDriver'    - cell array of driver names to include (default: all)
%   'FilterCategory'  - '2 Tyre', '4 Tyre', or 'All' (default: 'All')
%   'FigureSize'      - [width height] in pixels (default: [1200 600])
%
% Returns:
%   figs - array of figure handles

% ── Default manufacturer colours ─────────────────────────────────────────────
MFG_COLOURS = containers.Map( ...
    {'Ford',  'Chev', 'Chevrolet', 'Toyota', 'Camry', 'Mustang', 'Camaro'}, ...
    {[0.00 0.31 0.65], ...   % Ford Blue
     [1.00 0.84 0.00], ...   % Chev Yellow
     [1.00 0.84 0.00], ...   % Chev Yellow alias
     [0.85 0.10 0.10], ...   % Toyota Red
     [0.85 0.10 0.10], ...   % Toyota alias
     [0.00 0.31 0.65], ...   % Ford alias
     [1.00 0.84 0.00]});     % Chev alias

DEFAULT_COLOUR = [0.4 0.4 0.4];

% ── Parse optional arguments ─────────────────────────────────────────────────
p = inputParser();
p.addParameter('Cfg',            []);
p.addParameter('DriverMap',      []);
p.addParameter('FilterDriver',   {});
p.addParameter('FilterCategory', 'All');
p.addParameter('FigureSize',     [1200 600]);
p.parse(varargin{:});

cfg           = p.Results.Cfg;
driver_map    = p.Results.DriverMap;
filterDrivers = p.Results.FilterDriver;
filterCat     = p.Results.FilterCategory;
figSize       = p.Results.FigureSize;

% Merge cfg manufacturer colours if provided
if ~isempty(cfg) && isfield(cfg, 'manufacturer')
    mfr_fields = fieldnames(cfg.manufacturer);
    for i = 1:numel(mfr_fields)
        MFG_COLOURS(mfr_fields{i}) = cfg.manufacturer.(mfr_fields{i});
    end
end

% ── Apply driver filter ─────────────────────────────────────────────────────
if ~isempty(filterDrivers)
    keep = arrayfun(@(s) ismember(s.driver, filterDrivers), pitData);
    pitData = pitData(keep);
end

if isempty(pitData)
    warning('plotPitStops: no data after filtering.');
    figs = [];
    return
end

% ── All possible change types (for consistent x-axis ordering) ─────────────
ALL_TYPES_2 = {'FL','FR','RL','RR','FL+RL','FR+RR','FL+FR','RR+RL'};
ALL_TYPES_4 = {'4 Tyre'};

figs = gobjects(0);

% ────────────────────────────────────────────────────────────────────────────
%  FIGURE 1 — Stop Duration: 2-Tyre vs 4-Tyre split (all cars, scatter)
% ────────────────────────────────────────────────────────────────────────────
fig1 = makeFigure('Pit Stop Durations — All Cars', figSize);
figs(end+1) = fig1;

ax2 = subplot(1, 2, 1);
ax4 = subplot(1, 2, 2);
hold(ax2, 'on'); hold(ax4, 'on');
title(ax2, '2-Tyre Stops');
title(ax4, '4-Tyre Stops');
ylabel(ax2, 'Stop Duration [s]');
ylabel(ax4, 'Stop Duration [s]');
xlabel(ax2, 'Change Type');
xlabel(ax4, 'Change Type');
grid(ax2, 'on'); grid(ax4, 'on');

legendEntries2 = {};
legendHandles2 = [];
legendEntries4 = {};
legendHandles4 = [];

for g = 1:numel(pitData)
    car    = pitData(g);
    stops  = car.stops;
    colour = resolveColour(car.driver, car.manufacturer, driver_map, MFG_COLOURS, DEFAULT_COLOUR);

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

    if ~isempty(stops2)
        xPos = getXPositions(stops2.ChangeType, ALL_TYPES_2);
        h = scatter(ax2, xPos, stops2.StopTime_s, 60, colour, 'filled', ...
                    'MarkerFaceAlpha', 0.75, 'DisplayName', car.driver);
        if ~ismember(car.driver, legendEntries2)
            legendEntries2{end+1} = car.driver;
            legendHandles2(end+1) = h;
        end
    end

    if ~isempty(stops4)
        xPos4 = ones(height(stops4), 1);
        h4 = scatter(ax4, xPos4, stops4.StopTime_s, 60, colour, 'filled', ...
                     'MarkerFaceAlpha', 0.75, 'DisplayName', car.driver);
        ax4.Children(1).XData = ax4.Children(1).XData + (rand(1, height(stops4)) - 0.5) * 0.15;
        if ~ismember(car.driver, legendEntries4)
            legendEntries4{end+1} = car.driver;
            legendHandles4(end+1) = h4;
        end
    end
end

setXTicks(ax2, ALL_TYPES_2);
setXTicks(ax4, ALL_TYPES_4);
if ~isempty(legendHandles2), legend(ax2, legendHandles2, legendEntries2, 'Location','best', 'Interpreter','none'); end
if ~isempty(legendHandles4), legend(ax4, legendHandles4, legendEntries4, 'Location','best', 'Interpreter','none'); end

% ────────────────────────────────────────────────────────────────────────────
%  FIGURE 2 — Stop Count Bar Chart (2-tyre types per car)
% ────────────────────────────────────────────────────────────────────────────
fig2 = makeFigure('Pit Stop Counts by Type — 2 Tyre', figSize);
figs(end+1) = fig2;
axBar = axes(fig2);
hold(axBar, 'on');

allDrivers  = {pitData.driver};
nDrivers    = numel(pitData);
nTypes2     = numel(ALL_TYPES_2);
countMatrix = zeros(nDrivers, nTypes2);

for g = 1:nDrivers
    stops2 = pitData(g).stops(pitData(g).stops.TyreCategory == "2 Tyre", :);
    for t = 1:nTypes2
        countMatrix(g, t) = sum(stops2.ChangeType == ALL_TYPES_2{t});
    end
end

barWidth = 0.8 / nDrivers;
for g = 1:nDrivers
    colour  = resolveColour(pitData(g).driver, pitData(g).manufacturer, ...
                            driver_map, MFG_COLOURS, DEFAULT_COLOUR);
    xOffset = (g - (nDrivers+1)/2) * barWidth;
    bar(axBar, (1:nTypes2) + xOffset, countMatrix(g,:), barWidth, ...
        'FaceColor', colour, 'DisplayName', allDrivers{g});
end

setXTicks(axBar, ALL_TYPES_2);
ylabel(axBar, 'Number of Stops');
title(axBar, '2-Tyre Stop Counts by Change Type');
legend(axBar, 'Location', 'best', 'Interpreter', 'none');
grid(axBar, 'on');

% ────────────────────────────────────────────────────────────────────────────
%  FIGURE 3 — Stop Duration per Lap (one series per driver)
% ────────────────────────────────────────────────────────────────────────────
fig3 = makeFigure('Pit Stop Duration by Lap — All Cars', figSize);
figs(end+1) = fig3;
axTL = axes(fig3);
hold(axTL, 'on');

legHandles = [];
legLabels  = {};

for g = 1:numel(pitData)
    car    = pitData(g);
    stops  = car.stops;
    colour = resolveColour(car.driver, car.manufacturer, driver_map, MFG_COLOURS, DEFAULT_COLOUR);

    % Filter out No Change rows for cleaner plot
    valid = stops.TyreCategory ~= "No Change";
    stops = stops(valid, :);
    if isempty(stops), continue; end

    h = scatter(axTL, stops.LapNumber, stops.StopTime_s, 70, colour, 'filled', ...
                'MarkerEdgeColor', colour * 0.6, 'LineWidth', 0.8, ...
                'MarkerFaceAlpha', 0.85, 'DisplayName', car.driver);

    % Label each point with change type and manufacturer
    for s = 1:height(stops)
        text(axTL, stops.LapNumber(s), stops.StopTime_s(s), ...
             sprintf('  %s\n  %s', char(stops.ChangeType(s)), car.team), ...
             'FontSize', 8, 'Color', colour * 0.7, 'Interpreter', 'none');
    end

    legHandles(end+1) = h;  %#ok
    legLabels{end+1}  = car.driver;  %#ok
end

% Set x axis to max lap number across all drivers
maxLap = 0;
for g = 1:numel(pitData)
    if ~isempty(pitData(g).stops)
        maxLap = max(maxLap, max(pitData(g).stops.LapNumber));
    end
end
if maxLap > 0, axTL.XLim = [0, maxLap + 1]; end
axTL.YLim(1) = 0;

xlabel(axTL, 'Lap Number');
ylabel(axTL, 'Stop Duration [s]');
title(axTL, 'Pit Stop Duration by Lap');
grid(axTL, 'on');
box(axTL, 'on');
axTL.Color         = [0.97 0.97 0.97];
axTL.GridAlpha     = 0.25;
axTL.GridLineStyle = '--';

if ~isempty(legHandles)
   legend(axTL, legHandles, legLabels, 'Location', 'best', 'Box', 'off', 'Interpreter', 'none');
end

end  % ── end main ─────────────────────────────────────────────────────────────


% ════════════════════════════════════════════════════════════════════════════
%  LOCAL HELPERS
% ════════════════════════════════════════════════════════════════════════════

function colour = resolveColour(driverName, manufacturer, driver_map, mfgColours, defaultColour)
% Priority: driver_map colour > manufacturer colour > default
    colour = defaultColour;

    % 1. Try driver_map — match by TLA or sanitised name
    if ~isempty(driver_map) && isstruct(driver_map)
        keys = fieldnames(driver_map);
        for k = 1:numel(keys)
            entry = driver_map.(keys{k});
            % Match on TLA or the struct key itself (handles underscored names)
            if (isfield(entry, 'tla') && strcmpi(entry.tla, driverName)) || ...
               strcmpi(keys{k}, driverName) || ...
               strcmpi(strrep(keys{k}, '_', ' '), driverName)
                if isfield(entry, 'colour') && ~isempty(entry.colour)
                    colour = entry.colour(:)';
                    return;
                end
            end
        end
    end

    % 2. Fall back to manufacturer colour
    if ~isempty(manufacturer) && isKey(mfgColours, manufacturer)
        colour = mfgColours(manufacturer);
    end
end

function fig = makeFigure(titleStr, figSize)
    fig = figure('Name', titleStr, 'NumberTitle', 'off', ...
                 'Position', [100 100 figSize(1) figSize(2)], ...
                 'Color', 'white');
end

function xPos = getXPositions(changeTypes, allTypes)
    xPos = zeros(numel(changeTypes), 1);
    for i = 1:numel(changeTypes)
        idx = find(strcmp(allTypes, char(changeTypes(i))), 1);
        if isempty(idx), idx = numel(allTypes) + 1; end
        xPos(i) = idx;
    end
end

function setXTicks(ax, typeLabels)
    xticks(ax, 1:numel(typeLabels));
    xticklabels(ax, typeLabels);
    ax.XLim = [0.5, numel(typeLabels) + 0.5];
    xtickangle(ax, 30);
end