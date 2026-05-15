function appData = tyreDataViewer_panel(parent)
% TYREDATAVIEWER_PANEL  Embeddable tyre data viewer panel.
%
%   appData = tyreDataViewer_panel(parent)
%
%   Builds all UI inside PARENT (a uitab, uipanel, or uigridlayout).
%   All components use the App Designer (uifigure-compatible) framework.
%   Returns appData struct so the caller can store state.
%
%   Standalone use: see tyreDataViewer.m

    thisDir = fileparts(mfilename('fullpath'));

    % ---- Initialize appData -------------------------------------------
    appData = struct();
    appData.data            = [];
    appData.currentTestType = '';
    appData.currentTest     = '';
    appData.pacejkaPath     = fullfile(thisDir, 'pacejkaFormula');
    appData.pacejkaOverlay  = [];
    appData.paramControls   = struct('labels', {}, 'edits', {}, 'name', {});

    % ---- Root grid inside parent (3 columns: left | centre | right) ----
    rootGrid = uigridlayout(parent, [1, 3]);
    rootGrid.ColumnWidth = {240, '1x', 200};
    rootGrid.RowHeight   = {'1x'};
    rootGrid.Padding     = [6 6 6 6];
    rootGrid.ColumnSpacing = 6;

    % ==================================================================
    %  LEFT PANEL — controls
    % ==================================================================
    leftPanel = uipanel(rootGrid, 'BorderType', 'none');
    leftPanel.Layout.Row    = 1;
    leftPanel.Layout.Column = 1;

    leftGrid = uigridlayout(leftPanel, [22, 2]);
    leftGrid.RowHeight = {28, 22, 16, 28, 16, 28, 16, 28, 28, 16, 22, 16, 22, 16, 22, 32, 16, 28, 28, 28, 28, 28};
    leftGrid.ColumnWidth = {'1x', '1x'};
    leftGrid.Padding = [4 4 4 4];
    leftGrid.RowSpacing = 3;

    % Row 1: Load button
    loadBtn = uibutton(leftGrid, 'push', 'Text', 'Load Data File', ...
        'FontWeight', 'bold', 'FontSize', 10, ...
        'ButtonPushedFcn', @loadDataCallback);
    loadBtn.Layout.Row    = 1;
    loadBtn.Layout.Column = [1 2];

    % Row 2: File label
    fileLabel = uilabel(leftGrid, 'Text', 'No file loaded', ...
        'FontColor', [0.5 0.5 0.5]);
    fileLabel.Layout.Row    = 2;
    fileLabel.Layout.Column = [1 2];

    % Row 3: Test Type header
    lbl = uilabel(leftGrid, 'Text', 'Test Type:', 'FontWeight', 'bold');
    lbl.Layout.Row = 3; lbl.Layout.Column = [1 2];

    % Row 4: Test Type dropdown
    testTypeDropdown = uidropdown(leftGrid, 'Items', {'Select test type...'}, ...
        'ValueChangedFcn', @testTypeChanged);
    testTypeDropdown.Layout.Row    = 4;
    testTypeDropdown.Layout.Column = [1 2];

    % Row 5: Test Name header
    lbl = uilabel(leftGrid, 'Text', 'Test Name:', 'FontWeight', 'bold');
    lbl.Layout.Row = 5; lbl.Layout.Column = [1 2];

    % Row 6: Test Name dropdown
    testNameDropdown = uidropdown(leftGrid, 'Items', {'Select test...'}, ...
        'ValueChangedFcn', @testNameChanged);
    testNameDropdown.Layout.Row    = 6;
    testNameDropdown.Layout.Column = [1 2];

    % Row 7: Plot Type header
    lbl = uilabel(leftGrid, 'Text', 'Plot Type:', 'FontWeight', 'bold');
    lbl.Layout.Row = 7; lbl.Layout.Column = [1 2];

    % Row 8: Plot Type dropdown
    plotTypeDropdown = uidropdown(leftGrid, 'Items', {'Scatter', '2D Line', 'Surface'}, ...
        'ValueChangedFcn', @plotTypeChanged);
    plotTypeDropdown.Layout.Row    = 8;
    plotTypeDropdown.Layout.Column = [1 2];

    % Row 9: X-axis header
    lbl = uilabel(leftGrid, 'Text', 'X-axis:', 'FontWeight', 'bold');
    lbl.Layout.Row = 9; lbl.Layout.Column = [1 2];

    % Row 10: X-axis dropdown
    xDropdown = uidropdown(leftGrid, 'Items', {'Select variable...'});
    xDropdown.Layout.Row    = 10;
    xDropdown.Layout.Column = [1 2];

    % Row 11: X filter label
    lbl = uilabel(leftGrid, 'Text', 'X filter (min,max,...):', 'FontSize', 10);
    lbl.Layout.Row = 11; lbl.Layout.Column = [1 2];

    % Row 12: X filter edit
    xFilterEdit = uieditfield(leftGrid, 'text', 'Value', '', ...
        'Tooltip', 'Range pairs: 0,2,4,6 means (0-2) or (4-6). Leave empty for no filter.');
    xFilterEdit.Layout.Row    = 12;
    xFilterEdit.Layout.Column = [1 2];

    % Row 13: Y-axis header
    lbl = uilabel(leftGrid, 'Text', 'Y-axis:', 'FontWeight', 'bold');
    lbl.Layout.Row = 13; lbl.Layout.Column = [1 2];

    % Row 14: Y-axis dropdown
    yDropdown = uidropdown(leftGrid, 'Items', {'Select variable...'});
    yDropdown.Layout.Row    = 14;
    yDropdown.Layout.Column = [1 2];

    % Row 15: Y filter label
    lbl = uilabel(leftGrid, 'Text', 'Y filter (min,max,...):', 'FontSize', 10);
    lbl.Layout.Row = 15; lbl.Layout.Column = [1 2];

    % Row 16: Y filter edit
    yFilterEdit = uieditfield(leftGrid, 'text', 'Value', '', ...
        'Tooltip', 'Range pairs: 0,2,4,6 means (0-2) or (4-6). Leave empty for no filter.');
    yFilterEdit.Layout.Row    = 16;
    yFilterEdit.Layout.Column = [1 2];

    % Row 17: Z-axis header
    zLabel = uilabel(leftGrid, 'Text', 'Color/Z-axis:', 'FontWeight', 'bold');
    zLabel.Layout.Row = 17; zLabel.Layout.Column = [1 2];

    % Row 18: Z-axis dropdown
    zDropdown = uidropdown(leftGrid, 'Items', {'None'});
    zDropdown.Layout.Row    = 18;
    zDropdown.Layout.Column = [1 2];

    % Row 19: Z filter label
    lbl = uilabel(leftGrid, 'Text', 'Z filter (min,max,...):', 'FontSize', 10);
    lbl.Layout.Row = 19; lbl.Layout.Column = [1 2];

    % Row 20: Z filter edit
    zFilterEdit = uieditfield(leftGrid, 'text', 'Value', '', ...
        'Tooltip', 'Range pairs: 0,2,4,6 means (0-2) or (4-6). Leave empty for no filter.');
    zFilterEdit.Layout.Row    = 20;
    zFilterEdit.Layout.Column = [1 2];

    % Row 21: Update Plot button
    updateBtn = uibutton(leftGrid, 'push', 'Text', 'Update Plot', ...
        'FontWeight', 'bold', 'FontSize', 10, ...
        'BackgroundColor', [0.2 0.6 0.9], 'FontColor', 'white', ...
        'ButtonPushedFcn', @updatePlot);
    updateBtn.Layout.Row    = 21;
    updateBtn.Layout.Column = [1 2];

    % Row 22: Export row — two buttons side by side
    exportPngBtn = uibutton(leftGrid, 'push', 'Text', 'Save Plot PNG', ...
        'FontSize', 9, 'ButtonPushedFcn', @exportPlotCallback);
    exportPngBtn.Layout.Row    = 22;
    exportPngBtn.Layout.Column = 1;

    exportCsvBtn = uibutton(leftGrid, 'push', 'Text', 'Save Data CSV', ...
        'FontSize', 9, 'ButtonPushedFcn', @exportDataCallback);
    exportCsvBtn.Layout.Row    = 22;
    exportCsvBtn.Layout.Column = 2;

    % ==================================================================
    %  CENTRE PANEL — axes
    % ==================================================================
    centrePanel = uipanel(rootGrid, 'BorderType', 'none');
    centrePanel.Layout.Row    = 1;
    centrePanel.Layout.Column = 2;

    centreGrid = uigridlayout(centrePanel, [2, 1]);
    centreGrid.RowHeight    = {28, '1x'};
    centreGrid.ColumnWidth  = {'1x'};
    centreGrid.Padding       = [2 2 2 2];
    centreGrid.RowSpacing    = 4;

    % Plot-tool buttons row
    toolGrid = uigridlayout(centreGrid, [1, 5]);
    toolGrid.Layout.Row    = 1;
    toolGrid.Layout.Column = 1;
    toolGrid.ColumnWidth   = {'1x','1x','1x','1x','1x'};
    toolGrid.RowHeight     = {'1x'};
    toolGrid.Padding       = [0 0 0 0];

    panBtn = uibutton(toolGrid, 'push', 'Text', 'Pan',   'FontSize', 9, 'ButtonPushedFcn', @(~,~) toggleTool('pan'));
    panBtn.Layout.Row = 1; panBtn.Layout.Column = 1;
    zoomBtn = uibutton(toolGrid, 'push', 'Text', 'Zoom', 'FontSize', 9, 'ButtonPushedFcn', @(~,~) toggleTool('zoom'));
    zoomBtn.Layout.Row = 1; zoomBtn.Layout.Column = 2;
    rotBtn  = uibutton(toolGrid, 'push', 'Text', 'Rotate 3D', 'FontSize', 9, 'ButtonPushedFcn', @(~,~) toggleTool('rotate'));
    rotBtn.Layout.Row = 1; rotBtn.Layout.Column = 3;
    dcBtn   = uibutton(toolGrid, 'push', 'Text', 'Data Cursor', 'FontSize', 9, 'ButtonPushedFcn', @(~,~) toggleTool('datacursor'));
    dcBtn.Layout.Row = 1; dcBtn.Layout.Column = 4;
    resetBtn = uibutton(toolGrid, 'push', 'Text', 'Reset View', 'FontSize', 9, 'ButtonPushedFcn', @resetView);
    resetBtn.Layout.Row = 1; resetBtn.Layout.Column = 5;

    % Main axes
    ax = uiaxes(centreGrid);
    ax.Layout.Row    = 2;
    ax.Layout.Column = 1;

    % ==================================================================
    %  RIGHT PANEL — Pacejka fitting
    % ==================================================================
    rightPanel = uipanel(rootGrid, 'BorderType', 'line', 'Title', 'Pacejka Formula');
    rightPanel.Layout.Row    = 1;
    rightPanel.Layout.Column = 3;

    rightGrid = uigridlayout(rightPanel, [8, 1]);
    rightGrid.RowHeight   = {16, 28, 16, '1x', 16, 28, 32, 28};
    rightGrid.ColumnWidth = {'1x'};
    rightGrid.Padding     = [6 6 6 6];
    rightGrid.RowSpacing  = 4;

    lbl = uilabel(rightGrid, 'Text', 'Formula:');
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;

    pacejkaDropdown = uidropdown(rightGrid, 'Items', {'None'}, ...
        'ValueChangedFcn', @updatePacejkaInputs);
    pacejkaDropdown.Layout.Row    = 2;
    pacejkaDropdown.Layout.Column = 1;

    lbl = uilabel(rightGrid, 'Text', 'Parameters:');
    lbl.Layout.Row = 3; lbl.Layout.Column = 1;

    % Scrollable panel for dynamic parameter controls
    paramPanel = uipanel(rightGrid, 'BorderType', 'none');
    paramPanel.Layout.Row    = 4;
    paramPanel.Layout.Column = 1;
    % paramGrid will be created/recreated inside updatePacejkaInputs
    appData.paramPanel = paramPanel;

    lbl = uilabel(rightGrid, 'Text', 'Additional Args:');
    lbl.Layout.Row = 5; lbl.Layout.Column = 1;

    vararginEdit = uieditfield(rightGrid, 'text', 'Value', '', ...
        'Tooltip', 'Comma-separated values (e.g., 1.3, 0.5)');
    vararginEdit.Layout.Row    = 6;
    vararginEdit.Layout.Column = 1;

    overlayBtn = uibutton(rightGrid, 'push', 'Text', 'Overlay Formula', ...
        'FontSize', 9, 'BackgroundColor', [0.3 0.7 0.3], 'FontColor', 'white', ...
        'ButtonPushedFcn', @overlayPacejka);
    overlayBtn.Layout.Row    = 7;
    overlayBtn.Layout.Column = 1;

    clearBtn = uibutton(rightGrid, 'push', 'Text', 'Clear Overlay', ...
        'FontSize', 9, 'ButtonPushedFcn', @clearPacejkaOverlay);
    clearBtn.Layout.Row    = 8;
    clearBtn.Layout.Column = 1;

    % ---- Startup actions -----------------------------------------------
    autoLoadDefaultData();
    loadPacejkaFormulas();

    % ====================================================================
    %  HELPER / CALLBACK FUNCTIONS
    % ====================================================================

    function [validRanges, errorMsg] = parseFilterString(filterStr)
        validRanges = {};
        errorMsg    = '';

        if isempty(strtrim(filterStr))
            return;
        end

        try
            values = str2num(filterStr); %#ok<ST2NM>

            if isempty(values)
                errorMsg = 'Invalid input: must be numeric values';
                return;
            end

            if mod(length(values), 2) ~= 0
                errorMsg = 'Invalid input: must have even number of values (pairs of min,max)';
                return;
            end

            for i = 1:2:length(values)
                minVal = values(i);
                maxVal = values(i+1);
                if maxVal < minVal
                    errorMsg = sprintf('Invalid range: max (%.2f) < min (%.2f)', maxVal, minVal);
                    return;
                end
                validRanges{end+1} = [minVal, maxVal]; %#ok<AGROW>
            end

        catch ME
            errorMsg = sprintf('Parse error: %s', ME.message);
        end
    end

    function mask = applyFilter(data, filterStr)
        [validRanges, errorMsg] = parseFilterString(filterStr);

        if ~isempty(errorMsg)
            error(errorMsg);
        end

        if isempty(validRanges)
            mask = true(size(data));
            return;
        end

        mask = false(size(data));
        for i = 1:length(validRanges)
            range = validRanges{i};
            mask  = mask | (data >= range(1) & data <= range(2));
        end
    end

    function updatePacejkaInputs(~, ~)
        selectedFormula = pacejkaDropdown.Value;

        if strcmp(selectedFormula, 'None') || contains(selectedFormula, 'not found')
            return;
        end

        % Remove old param controls from panel
        delete(appData.paramPanel.Children);
        appData.paramControls = struct('labels', {}, 'edits', {}, 'name', {});

        try
            funcPath = fullfile(appData.pacejkaPath, [selectedFormula, '.m']);

            fid = fopen(funcPath, 'r');
            if fid == -1
                warning('Could not open file: %s', funcPath);
                return;
            end
            firstLine = fgetl(fid);
            fclose(fid);

            tokens = regexp(firstLine, 'function.*\((.*)\)', 'tokens');
            if isempty(tokens)
                return;
            end

            paramStr = tokens{1}{1};
            params   = strtrim(strsplit(strtrim(paramStr), ','));

            % Remove first arg (xRange) and varargin
            if length(params) > 1
                params = params(2:end);
            else
                params = {};
            end
            params(strcmp(params, 'varargin')) = [];

            numParams = length(params);
            if numParams == 0
                return;
            end

            % Build a simple N-row grid inside paramPanel
            numRows = numParams * 2;  % label + edit per param
            pg = uigridlayout(appData.paramPanel, [numRows, 1]);
            rowH = repmat({16; 24}, numParams, 1);
            pg.RowHeight   = rowH(:)';
            pg.ColumnWidth = {'1x'};
            pg.Padding     = [2 2 2 2];
            pg.RowSpacing  = 2;

            for i = 1:numParams
                paramName              = params{i};
                [defaultVal, ~, ~]     = getParamDefaults(paramName);

                lbl2 = uilabel(pg, 'Text', [paramName, ':'], 'FontSize', 9);
                lbl2.Layout.Row    = (i-1)*2 + 1;
                lbl2.Layout.Column = 1;

                ef = uieditfield(pg, 'text', 'Value', num2str(defaultVal), 'Tag', paramName);
                ef.Layout.Row    = (i-1)*2 + 2;
                ef.Layout.Column = 1;

                appData.paramControls(i).labels = lbl2;
                appData.paramControls(i).edits  = ef;
                appData.paramControls(i).name   = paramName;
            end

        catch ME
            warning('Could not parse function signature: %s', ME.message);
        end
    end

    function [defaultVal, minVal, maxVal] = getParamDefaults(paramName)
        defaultVal = 1;
        minVal     = -10;
        maxVal     = 10;

        paramLower = lower(paramName);

        if strcmpi(paramName, 'B')
            defaultVal = 10; minVal = 0.1; maxVal = 50;
        elseif strcmpi(paramName, 'C')
            defaultVal = 1.3; minVal = 0.5; maxVal = 3;
        elseif strcmpi(paramName, 'D')
            defaultVal = 1; minVal = 0.1; maxVal = 5;
        elseif strcmpi(paramName, 'E')
            defaultVal = 0; minVal = -5; maxVal = 5;
        elseif contains(paramLower, 'x_m') || contains(paramLower, 'xm') || contains(paramLower, 'shift')
            defaultVal = 0;
        elseif contains(paramLower, 'stiffness') || contains(paramLower, 'stiff')
            defaultVal = 10; minVal = 0.1; maxVal = 50;
        elseif contains(paramLower, 'peak') || contains(paramLower, 'max')
            defaultVal = 1; minVal = 0.1; maxVal = 5;
        elseif contains(paramLower, 'shape') || contains(paramLower, 'curv')
            defaultVal = 1.3; minVal = 0.5; maxVal = 3;
        end
    end

    function autoLoadDefaultData()
        defaultPath = fullfile(thisDir, 'calspanData_2017_separated.mat');

        if exist(defaultPath, 'file')
            try
                loadedData = load(defaultPath);

                if isfield(loadedData, 'tyreData')
                    appData.data = loadedData.tyreData;
                    fileLabel.Text      = 'Loaded: calspanData_2017_separated.mat';
                    fileLabel.FontColor = [0 0.6 0];

                    testTypes = fieldnames(appData.data);
                    testTypeDropdown.Items = testTypes;
                    testTypeDropdown.Value = testTypes{1};
                    testTypeChanged();
                end
            catch
                % Silent fail — user can manually load
            end
        end
    end

    function loadPacejkaFormulas()
        if ~exist(appData.pacejkaPath, 'dir')
            pacejkaDropdown.Items = {'None (folder not found)'};
            return;
        end

        files = dir(fullfile(appData.pacejkaPath, '*.m'));

        if isempty(files)
            pacejkaDropdown.Items = {'None (no formulas found)'};
        else
            formulaNames = {'None'};
            for i = 1:length(files)
                [~, name, ~] = fileparts(files(i).name);
                formulaNames{end+1} = name; %#ok<AGROW>
            end
            pacejkaDropdown.Items = formulaNames;
            pacejkaDropdown.Value = 'None';
        end
    end

    function overlayPacejka(~, ~)
        if isempty(appData.data) || isempty(appData.currentTest)
            uialert(ancestor(parent, 'figure'), ...
                'Please load data and select a test first', 'No Data');
            return;
        end

        selectedFormula = pacejkaDropdown.Value;

        if strcmp(selectedFormula, 'None') || contains(selectedFormula, 'not found')
            uialert(ancestor(parent, 'figure'), ...
                'Please select a valid Pacejka formula', 'No Formula Selected');
            return;
        end

        currentData = appData.data.(appData.currentTestType).(appData.currentTest);
        xVar        = xDropdown.Value;
        xData       = currentData.(xVar);
        xRange      = linspace(min(xData), max(xData), 200);

        paramValues  = {};
        gammaParamIdx = [];

        for i = 1:length(appData.paramControls)
            editStr = appData.paramControls(i).edits.Value;

            if contains(editStr, ',')
                vals = str2num(['[', editStr, ']']); %#ok<ST2NM>
                if isempty(vals)
                    uialert(ancestor(parent, 'figure'), ...
                        sprintf('Invalid array format for parameter: %s', appData.paramControls(i).name), 'Input Error');
                    return;
                end
                paramValues{end+1} = vals; %#ok<AGROW>

                if strcmpi(appData.paramControls(i).name, 'gamma') || strcmpi(appData.paramControls(i).name, 'IA')
                    gammaParamIdx = i;
                end
            else
                val = str2double(editStr);
                if isnan(val)
                    uialert(ancestor(parent, 'figure'), ...
                        sprintf('Invalid value for parameter: %s', appData.paramControls(i).name), 'Input Error');
                    return;
                end
                paramValues{end+1} = val; %#ok<AGROW>
            end
        end

        vararginStr = vararginEdit.Value;
        if ~isempty(strtrim(vararginStr))
            try
                vararginVals = eval(['{', vararginStr, '}']);
                if ~isempty(vararginVals)
                    paramValues = [paramValues, vararginVals];
                end
            catch
                uialert(ancestor(parent, 'figure'), ...
                    'Invalid varargin format. Use MATLAB syntax: ''name'', value, ...', 'Input Error');
                return;
            end
        end

        try
            % Add pacejkaPath so feval can find the formula
            addpath(appData.pacejkaPath);

            yRange = feval(selectedFormula, xRange, paramValues{:});
            if size(yRange, 1) == 1
                yRange = yRange';
            end

            % Clear previous overlay
            clearPacejkaOverlay();
            appData.pacejkaOverlay = {};

            hold(ax, 'on');

            if size(yRange, 2) > 1
                colors = lines(size(yRange, 2));

                if ~isempty(gammaParamIdx)
                    gammaVals = paramValues{gammaParamIdx};
                else
                    gammaVals = 1:size(yRange, 2);
                end

                for i = 1:size(yRange, 2)
                    if ~isempty(gammaParamIdx)
                        legendStr = sprintf('%s (\x3b3=%.1f\xb0)', selectedFormula, gammaVals(i));
                    else
                        legendStr = sprintf('%s (curve %d)', selectedFormula, i);
                    end
                    appData.pacejkaOverlay{i} = plot(ax, xRange, yRange(:, i), ...
                        'LineWidth', 2, 'Color', colors(i, :), ...
                        'DisplayName', legendStr);
                end
            else
                appData.pacejkaOverlay{1} = plot(ax, xRange, yRange, 'r-', 'LineWidth', 2, ...
                    'DisplayName', sprintf('%s Fit', selectedFormula));
            end

            legend(ax, 'show', 'Location', 'best');
            hold(ax, 'off');

        catch ME
            uialert(ancestor(parent, 'figure'), ...
                sprintf('Error evaluating formula: %s', ME.message), 'Formula Error');
        end
    end

    function clearPacejkaOverlay(~, ~)
        if ~isempty(appData.pacejkaOverlay)
            if iscell(appData.pacejkaOverlay)
                for i = 1:length(appData.pacejkaOverlay)
                    if isvalid(appData.pacejkaOverlay{i})
                        delete(appData.pacejkaOverlay{i});
                    end
                end
            elseif isvalid(appData.pacejkaOverlay)
                delete(appData.pacejkaOverlay);
            end
        end
        appData.pacejkaOverlay = [];
        legend(ax, 'off');
    end

    function toggleTool(toolName)
        % uiaxes supports pan/zoom/rotate3d via the axes handle
        disableDefaultInteractivity(ax);
        switch toolName
            case 'pan'
                pan(ax, 'on');
            case 'zoom'
                zoom(ax, 'on');
            case 'rotate'
                rotate3d(ax, 'on');
            case 'datacursor'
                % datatip mode is always on for uiaxes; clicking activates it
                enableDefaultInteractivity(ax);
        end
    end

    function resetView(~, ~)
        disableDefaultInteractivity(ax);
        axis(ax, 'auto');
        plotType = plotTypeDropdown.Value;
        if strcmp(plotType, 'Surface')
            view(ax, 3);
        else
            view(ax, 2);
        end
    end

    function loadDataCallback(~, ~)
        [file, path] = uigetfile('*.mat', 'Select Calspan Data File');
        if isequal(file, 0)
            return;
        end

        try
            loadedData = load(fullfile(path, file));

            if ~isfield(loadedData, 'tyreData')
                uialert(ancestor(parent, 'figure'), ...
                    'File does not contain tyreData field', 'Invalid File');
                return;
            end

            appData.data        = loadedData.tyreData;
            fileLabel.Text      = sprintf('Loaded: %s', file);
            fileLabel.FontColor = [0 0.6 0];

            testTypes = fieldnames(appData.data);
            testTypeDropdown.Items = testTypes;
            testTypeDropdown.Value = testTypes{1};
            testTypeChanged();

        catch ME
            uialert(ancestor(parent, 'figure'), ...
                sprintf('Error loading file: %s', ME.message), 'Load Error');
        end
    end

    function testTypeChanged(~, ~)
        if isempty(appData.data)
            return;
        end

        appData.currentTestType = testTypeDropdown.Value;
        testNames               = fieldnames(appData.data.(appData.currentTestType));
        testNameDropdown.Items  = testNames;
        testNameDropdown.Value  = testNames{1};
        testNameChanged();
    end

    function testNameChanged(~, ~)
        if isempty(appData.data)
            return;
        end

        appData.currentTest = testNameDropdown.Value;
        currentData         = appData.data.(appData.currentTestType).(appData.currentTest);

        if istable(currentData)
            varNames = currentData.Properties.VariableNames;
        else
            uialert(ancestor(parent, 'figure'), ...
                'Selected test data is not a table', 'Data Error');
            return;
        end

        xDropdown.Items = varNames;
        yDropdown.Items = varNames;
        zDropdown.Items = [{'None'}, varNames];

        % Sensible defaults
        if any(strcmp(varNames, 'SA'))
            xDropdown.Value = 'SA';
        else
            xDropdown.Value = varNames{1};
        end

        if any(strcmp(varNames, 'FY'))
            yDropdown.Value = 'FY';
        else
            yDropdown.Value = varNames{min(2, end)};
        end

        if any(strcmp(varNames, 'FZ'))
            zDropdown.Value = 'FZ';
        else
            zDropdown.Value = 'None';
        end
    end

    function plotTypeChanged(~, ~)
        plotType = plotTypeDropdown.Value;

        if strcmp(plotType, 'Surface')
            zLabel.Text = 'Z-axis:';
            if strcmp(zDropdown.Value, 'None') && length(zDropdown.Items) > 1
                zDropdown.Value = zDropdown.Items{2};
            end
        else
            zLabel.Text = 'Color/Z-axis:';
        end
    end

    function updatePlot(~, ~)
        if isempty(appData.data) || isempty(appData.currentTest)
            uialert(ancestor(parent, 'figure'), ...
                'Please load data and select a test first', 'No Data');
            return;
        end

        disableDefaultInteractivity(ax);
        clearPacejkaOverlay();

        currentData = appData.data.(appData.currentTestType).(appData.currentTest);
        xVar        = xDropdown.Value;
        yVar        = yDropdown.Value;
        zVar        = zDropdown.Value;
        plotType    = plotTypeDropdown.Value;
        xFilterStr  = xFilterEdit.Value;
        yFilterStr  = yFilterEdit.Value;
        zFilterStr  = zFilterEdit.Value;

        cla(ax);

        try
            xData = currentData.(xVar);
            yData = currentData.(yVar);

            try
                xMask = applyFilter(xData, xFilterStr);
                yMask = applyFilter(yData, yFilterStr);
                combinedMask = xMask & yMask;

                if ~strcmp(zVar, 'None')
                    zData = currentData.(zVar);
                    zMask = applyFilter(zData, zFilterStr);
                    combinedMask = combinedMask & zMask;
                end

                xData = xData(combinedMask);
                yData = yData(combinedMask);

                if isempty(xData)
                    uialert(ancestor(parent, 'figure'), ...
                        'No data points match the filter criteria', 'Empty Result');
                    return;
                end

            catch ME
                uialert(ancestor(parent, 'figure'), ...
                    sprintf('Filter error: %s', ME.message), 'Invalid Filter');
                return;
            end

            switch plotType
                case 'Scatter'
                    if strcmp(zVar, 'None')
                        scatter(ax, xData, yData, 10, 'filled');
                    else
                        zData = currentData.(zVar);
                        zData = zData(combinedMask);
                        scatter(ax, xData, yData, 10, zData, 'filled');
                        colorbar(ax);
                    end

                case '2D Line'
                    plot(ax, xData, yData, 'LineWidth', 1.5);
                    grid(ax, 'on');

                case 'Surface'
                    if strcmp(zVar, 'None')
                        uialert(ancestor(parent, 'figure'), ...
                            'Surface plot requires Z variable', 'Missing Variable');
                        return;
                    end
                    zData = currentData.(zVar);
                    zData = zData(combinedMask);
                    try
                        [X, Y, Z] = griddata(xData, yData, zData, ...
                            linspace(min(xData), max(xData), 50)', ...
                            linspace(min(yData), max(yData), 50), ...
                            'natural');
                        surf(ax, X, Y, Z, 'EdgeColor', 'none');
                        colorbar(ax);
                        view(ax, 3);
                    catch
                        uialert(ancestor(parent, 'figure'), ...
                            'Unable to create surface. Data may not be suitable for gridding.', 'Surface Error');
                        return;
                    end
            end

            xlabel(ax, xVar);
            ylabel(ax, yVar);

            filterInfo = '';
            if ~isempty(strtrim(xFilterStr)), filterInfo = sprintf('X:%s ', xFilterStr); end
            if ~isempty(strtrim(yFilterStr)), filterInfo = [filterInfo, sprintf('Y:%s ', yFilterStr)]; end
            if ~strcmp(zVar, 'None') && ~isempty(strtrim(zFilterStr))
                filterInfo = [filterInfo, sprintf('Z:%s', zFilterStr)];
            end

            if strcmp(plotType, 'Surface')
                zlabel(ax, zVar);
                if ~isempty(filterInfo)
                    title(ax, sprintf('%s - %s [Filters: %s]', appData.currentTestType, appData.currentTest, strtrim(filterInfo)));
                else
                    title(ax, sprintf('%s - %s', appData.currentTestType, appData.currentTest));
                end
            else
                if ~strcmp(zVar, 'None')
                    if ~isempty(filterInfo)
                        title(ax, sprintf('%s - %s (Color: %s) [Filters: %s]', appData.currentTestType, appData.currentTest, zVar, strtrim(filterInfo)));
                    else
                        title(ax, sprintf('%s - %s (Color: %s)', appData.currentTestType, appData.currentTest, zVar));
                    end
                else
                    if ~isempty(filterInfo)
                        title(ax, sprintf('%s - %s [Filters: %s]', appData.currentTestType, appData.currentTest, strtrim(filterInfo)));
                    else
                        title(ax, sprintf('%s - %s', appData.currentTestType, appData.currentTest));
                    end
                end
            end

        catch ME
            uialert(ancestor(parent, 'figure'), ...
                sprintf('Error plotting: %s', ME.message), 'Plot Error');
        end
    end

    function exportPlotCallback(~, ~)
        [file, path] = uiputfile('*.png', 'Save Plot As');
        if isequal(file, 0)
            return;
        end
        exportgraphics(ax, fullfile(path, file), 'Resolution', 300);
        uialert(ancestor(parent, 'figure'), 'Plot saved successfully!', 'Success', 'Icon', 'success');
    end

    function exportDataCallback(~, ~)
        if isempty(appData.data) || isempty(appData.currentTest)
            uialert(ancestor(parent, 'figure'), 'No data to export', 'No Data');
            return;
        end

        [file, path] = uiputfile('*.csv', 'Save Data As');
        if isequal(file, 0)
            return;
        end

        currentData = appData.data.(appData.currentTestType).(appData.currentTest);
        writetable(currentData, fullfile(path, file));
        uialert(ancestor(parent, 'figure'), 'Data saved successfully!', 'Success', 'Icon', 'success');
    end

end
