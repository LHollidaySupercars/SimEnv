function tyreDataViewer()
% TYREDATAVIEWER Interactive GUI for viewing Calspan tyre data with Pacejka fitting
%
%   Launch with: tyreDataViewer()
%
%   Features:
%   - Load .mat file with tyre data (auto-loads default dataset)
%   - Select test type (FreeRoll, BrkDrv, etc.)
%   - Select individual test from dropdown
%   - Choose plot type: Scatter, 2D Line, Surface
%   - Select X, Y, Z (for scatter color or surface), variables
%   - Filter data by range pairs (e.g., "0,2,4,6" for ranges 0-2 and 4-6)
%   - Overlay Pacejka formula with adjustable parameters
%   - Export current plot as image or data as CSV
%   - Interactive plot tools: Pan, Zoom, Rotate, Data Cursor

    % Create figure
    fig = figure('Name', 'Tyre Data Viewer', 'Position', [100 100 1400 700], ...
        'MenuBar', 'none', 'NumberTitle', 'off', 'Resize', 'on', 'Toolbar', 'figure');
    
    % Initialize data storage
    appData = struct();
    appData.data = [];
    appData.currentTestType = '';
    appData.currentTest = '';
    appData.pacejkaPath = 'C:\SimEnv\vehicleModel\components\tyre\pacejkaFormula';
    appData.pacejkaOverlay = [];  % Handle for overlay plot
    
    % Control panel dimensions
    leftWidth = 250;
    margin = 10;
    controlY = 650;
    controlHeight = 25;
    controlSpacing = 22;
    
    % Load button
    uicontrol('Style', 'pushbutton', 'String', 'Load Data File', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'Callback', @loadDataCallback, 'FontSize', 10, 'FontWeight', 'bold');
    controlY = controlY - controlSpacing;
    
    % File label
    fileLabel = uicontrol('Style', 'text', 'String', 'No file loaded', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'HorizontalAlignment', 'left', 'ForegroundColor', [0.5 0.5 0.5]);
    controlY = controlY - controlSpacing - 5;
    
    % Test Type
    uicontrol('Style', 'text', 'String', 'Test Type:', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    controlY = controlY - controlSpacing;
    
    testTypeDropdown = uicontrol('Style', 'popupmenu', 'String', {'Select test type...'}, ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'Callback', @testTypeChanged);
    controlY = controlY - controlSpacing - 5;
    
    % Test Name
    uicontrol('Style', 'text', 'String', 'Test Name:', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    controlY = controlY - controlSpacing;
    
    testNameDropdown = uicontrol('Style', 'popupmenu', 'String', {'Select test...'}, ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'Callback', @testNameChanged);
    controlY = controlY - controlSpacing - 5;
    
    % Plot Type
    uicontrol('Style', 'text', 'String', 'Plot Type:', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    controlY = controlY - controlSpacing;
    
    plotTypeDropdown = uicontrol('Style', 'popupmenu', 'String', {'Scatter', '2D Line', 'Surface'}, ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'Callback', @plotTypeChanged);
    controlY = controlY - controlSpacing - 5;
    
    % X-axis
    uicontrol('Style', 'text', 'String', 'X-axis:', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    controlY = controlY - controlSpacing;
    
    xDropdown = uicontrol('Style', 'popupmenu', 'String', {'Select variable...'}, ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight]);
    controlY = controlY - controlSpacing;
    
    % X-axis filter
    uicontrol('Style', 'text', 'String', 'X filter (min,max,...):', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight-5], ...
        'HorizontalAlignment', 'left', 'FontSize', 8);
    controlY = controlY - 20;
    
    xFilterEdit = uicontrol('Style', 'edit', 'String', '', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'TooltipString', 'Range pairs: 0,2,4,6 means (0-2) or (4-6). Leave empty for no filter.');
    controlY = controlY - controlSpacing;
    
    % Y-axis
    uicontrol('Style', 'text', 'String', 'Y-axis:', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    controlY = controlY - controlSpacing;
    
    yDropdown = uicontrol('Style', 'popupmenu', 'String', {'Select variable...'}, ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight]);
    controlY = controlY - controlSpacing;
    
    % Y-axis filter
    uicontrol('Style', 'text', 'String', 'Y filter (min,max,...):', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight-5], ...
        'HorizontalAlignment', 'left', 'FontSize', 8);
    controlY = controlY - 20;
    
    yFilterEdit = uicontrol('Style', 'edit', 'String', '', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'TooltipString', 'Range pairs: 0,2,4,6 means (0-2) or (4-6). Leave empty for no filter.');
    controlY = controlY - controlSpacing;
    
    % Z-axis/Color
    zLabel = uicontrol('Style', 'text', 'String', 'Color/Z-axis:', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    controlY = controlY - controlSpacing;
    
    zDropdown = uicontrol('Style', 'popupmenu', 'String', {'None'}, ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight]);
    controlY = controlY - controlSpacing;
    
    % Z-axis filter
    uicontrol('Style', 'text', 'String', 'Z filter (min,max,...):', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight-5], ...
        'HorizontalAlignment', 'left', 'FontSize', 8);
    controlY = controlY - 20;
    
    zFilterEdit = uicontrol('Style', 'edit', 'String', '', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'TooltipString', 'Range pairs: 0,2,4,6 means (0-2) or (4-6). Leave empty for no filter.');
    controlY = controlY - controlSpacing;
    
    % Plot button
    uicontrol('Style', 'pushbutton', 'String', 'Update Plot', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight+5], ...
        'Callback', @updatePlot, 'FontSize', 10, 'FontWeight', 'bold', ...
        'BackgroundColor', [0.2 0.6 0.9], 'ForegroundColor', 'white');
    controlY = controlY - controlSpacing - 10;
    
    % Interaction tools label
    uicontrol('Style', 'text', 'String', 'Plot Tools:', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    controlY = controlY - controlSpacing;
    
    % Pan button
    uicontrol('Style', 'pushbutton', 'String', 'Pan', ...
        'Position', [margin, controlY, (leftWidth-3*margin)/2, controlHeight], ...
        'Callback', @(~,~) toggleTool('pan'), 'FontSize', 9);
    
    % Zoom button
    uicontrol('Style', 'pushbutton', 'String', 'Zoom', ...
        'Position', [margin + (leftWidth-margin)/2, controlY, (leftWidth-3*margin)/2, controlHeight], ...
        'Callback', @(~,~) toggleTool('zoom'), 'FontSize', 9);
    controlY = controlY - controlSpacing;
    
    % Rotate 3D button
    uicontrol('Style', 'pushbutton', 'String', 'Rotate 3D', ...
        'Position', [margin, controlY, (leftWidth-3*margin)/2, controlHeight], ...
        'Callback', @(~,~) toggleTool('rotate'), 'FontSize', 9);
    
    % Data Cursor button
    uicontrol('Style', 'pushbutton', 'String', 'Data Cursor', ...
        'Position', [margin + (leftWidth-margin)/2, controlY, (leftWidth-3*margin)/2, controlHeight], ...
        'Callback', @(~,~) toggleTool('datacursor'), 'FontSize', 9);
    controlY = controlY - controlSpacing;
    
    % Reset View button
    uicontrol('Style', 'pushbutton', 'String', 'Reset View', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'Callback', @resetView, 'FontSize', 9);
    controlY = controlY - controlSpacing - 5;
    
    % Export label
    uicontrol('Style', 'text', 'String', 'Export:', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    controlY = controlY - controlSpacing;
    
    % Export plot button
    uicontrol('Style', 'pushbutton', 'String', 'Save Plot as PNG', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'Callback', @exportPlotCallback, 'FontSize', 9);
    controlY = controlY - controlSpacing;
    
    % Export data button
    uicontrol('Style', 'pushbutton', 'String', 'Save Data as CSV', ...
        'Position', [margin, controlY, leftWidth-2*margin, controlHeight], ...
        'Callback', @exportDataCallback, 'FontSize', 9);
    
    % Create axes for plotting (main plot area)
    ax = axes('Parent', fig, 'Position', [0.2 0.1 0.58 0.85]);
    
    % ===== RIGHT PANEL: PACEJKA FITTING =====
    rightPanelX = 1200 - 90;
    rightWidth = 170;
    rightY = 650;

    % Pacejka section title
    uicontrol('Style', 'text', 'String', 'Pacejka Formula:', ...
        'Position', [rightPanelX, rightY, rightWidth, controlHeight], ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold', ...
        'BackgroundColor', [0.94 0.94 0.94]);
    rightY = rightY - controlSpacing;

    % Formula dropdown
    uicontrol('Style', 'text', 'String', 'Formula:', ...
        'Position', [rightPanelX, rightY, rightWidth, controlHeight-5], ...
        'HorizontalAlignment', 'left', 'FontSize', 8);
    rightY = rightY - 20;

    pacejkaDropdown = uicontrol('Style', 'popupmenu', 'String', {'None'}, ...
        'Position', [rightPanelX, rightY, rightWidth, controlHeight], ...
        'Callback', @updatePacejkaInputs);
    rightY = rightY - controlSpacing;

    % Dynamic parameter panel starting position
    paramPanelStartY = rightY;

    % Store handles for dynamic parameters
    appData.paramControls = struct('labels', {}, 'edits', {}, 'name', {});

    % varargin text box
    uicontrol('Style', 'text', 'String', 'Additional Args:', ...
        'Position', [rightPanelX, 150, rightWidth, controlHeight-5], ...
        'HorizontalAlignment', 'left', 'FontSize', 8);

    vararginEdit = uicontrol('Style', 'edit', 'String', '', ...
        'Position', [rightPanelX, 130, rightWidth, controlHeight], ...
        'TooltipString', 'Comma-separated values (e.g., 1.3, 0.5)');

    % Overlay button
    uicontrol('Style', 'pushbutton', 'String', 'Overlay Formula', ...
        'Position', [rightPanelX, 90, rightWidth, controlHeight+5], ...
        'Callback', @overlayPacejka, 'FontSize', 9, ...
        'BackgroundColor', [0.3 0.7 0.3], 'ForegroundColor', 'white');

    % Clear overlay button
    uicontrol('Style', 'pushbutton', 'String', 'Clear Overlay', ...
        'Position', [rightPanelX, 55, rightWidth, controlHeight], ...
        'Callback', @clearPacejkaOverlay, 'FontSize', 9);
    
    % Create data cursor mode object
    dcm = datacursormode(fig);
    set(dcm, 'UpdateFcn', @dataCursorUpdateFcn);
    
    % Auto-load default dataset
    autoLoadDefaultData();
    
    % Load available Pacejka formulas
    loadPacejkaFormulas();

    % ===== HELPER FUNCTIONS =====
    
    function [validRanges, errorMsg] = parseFilterString(filterStr)
        % Parse filter string and validate
        % Returns cell array of [min, max] pairs or empty if error
        validRanges = {};
        errorMsg = '';
        
        % Empty string = no filter
        if isempty(strtrim(filterStr))
            return;
        end
        
        % Try to parse as numeric array
        try
            values = str2num(filterStr); %#ok<ST2NM>
            
            if isempty(values)
                errorMsg = 'Invalid input: must be numeric values';
                return;
            end
            
            % Check if odd number of values
            if mod(length(values), 2) ~= 0
                errorMsg = 'Invalid input: must have even number of values (pairs of min,max)';
                return;
            end
            
            % Parse into pairs and validate
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
        % Apply filter to data, returns logical mask
        % True = keep data point
        
        [validRanges, errorMsg] = parseFilterString(filterStr);
        
        if ~isempty(errorMsg)
            error(errorMsg);
        end
        
        % No filter = keep all
        if isempty(validRanges)
            mask = true(size(data));
            return;
        end
        
        % Apply OR logic across all ranges
        mask = false(size(data));
        for i = 1:length(validRanges)
            range = validRanges{i};
            mask = mask | (data >= range(1) & data <= range(2));
        end
    end

    function updatePacejkaInputs(~, ~)
        % Get selected formula
        formulas = get(pacejkaDropdown, 'String');
        selectedFormula = formulas{get(pacejkaDropdown, 'Value')};
        
        if strcmp(selectedFormula, 'None') || contains(selectedFormula, 'not found')
            return;
        end
        
        % Clear existing parameter controls
        for i = 1:length(appData.paramControls)
            if isfield(appData.paramControls(i), 'labels') && ishandle(appData.paramControls(i).labels)
                delete(appData.paramControls(i).labels);
            end
            if isfield(appData.paramControls(i), 'edits') && ishandle(appData.paramControls(i).edits)
                delete(appData.paramControls(i).edits);
            end
        end
        appData.paramControls = struct('labels', {}, 'edits', {}, 'name', {});
        
        % Get function signature
        try
            funcPath = fullfile(appData.pacejkaPath, [selectedFormula, '.m']);
            
            % Parse function to get input names
            fid = fopen(funcPath, 'r');
            if fid == -1
                warning('Could not open file: %s', funcPath);
                return;
            end
            firstLine = fgetl(fid);
            fclose(fid);
            
            % Extract parameter names from function signature
            tokens = regexp(firstLine, 'function.*\((.*)\)', 'tokens');
            if ~isempty(tokens)
                paramStr = tokens{1}{1};
                params = strsplit(strtrim(paramStr), ',');
                params = strtrim(params);
                
                % Remove first parameter (assumed to be xRange or similar)
                if length(params) > 1
                    params = params(2:end);
                else
                    params = {};
                end
                
                % Remove 'varargin' if present
                params(strcmp(params, 'varargin')) = [];
                
                % Calculate layout
                numParams = length(params);
                if numParams == 0
                    return;
                end
                
                % Two-column layout settings
                numColumns = 2;
                columnWidth = floor(rightWidth / numColumns) - 5;
                column1X = rightPanelX;
                column2X = rightPanelX + columnWidth + 10;
                
                % Parameters per column
                paramsPerColumn = ceil(numParams / numColumns);
                
                % Available vertical space
                availableSpace = paramPanelStartY - 180;
                spacePerParam = floor(availableSpace / paramsPerColumn);
                
                % Adjust component heights based on available space
                if spacePerParam < 40
                    labelHeight = 12;
                    editHeight = 18;
                    paramGap = max(10, spacePerParam - 35);
                else
                    labelHeight = 15;
                    editHeight = controlHeight;
                    paramGap = max(18, spacePerParam - 45);
                end
                
                % Create controls for each parameter
                for i = 1:length(params)
                    paramName = params{i};
                    
                    % Determine which column and position
                    if i <= paramsPerColumn
                        currentX = column1X;
                        columnIndex = i;
                    else
                        currentX = column2X;
                        columnIndex = i - paramsPerColumn;
                    end
                    
                    % Calculate Y position
                    currentY = paramPanelStartY - ((columnIndex - 1) * spacePerParam);
                    
                    % Get default values
                    [defaultVal, ~, ~] = getParamDefaults(paramName);
                    
                    % Label
                    labelHandle = uicontrol('Style', 'text', 'String', [paramName, ':'], ...
                        'Position', [currentX, currentY, columnWidth, labelHeight], ...
                        'HorizontalAlignment', 'left', 'FontSize', 8);
                    currentY = currentY - labelHeight - 2;
                    
                    % Edit box
                    editHandle = uicontrol('Style', 'edit', 'String', num2str(defaultVal), ...
                        'Position', [currentX, currentY, columnWidth, editHeight], ...
                        'Tag', paramName);
                    
                    % Store handles
                    appData.paramControls(i).labels = labelHandle;
                    appData.paramControls(i).edits = editHandle;
                    appData.paramControls(i).name = paramName;
                end
            end
        catch ME
            warning('Could not parse function signature: %s', ME.message);
        end
    end

    function [defaultVal, minVal, maxVal] = getParamDefaults(paramName)
        % Helper function to get default values based on parameter name
        defaultVal = 1;
        minVal = -10;
        maxVal = 10;
        
        paramLower = lower(paramName);
        
        if strcmpi(paramName, 'B')
            defaultVal = 10;
            minVal = 0.1;
            maxVal = 50;
        elseif strcmpi(paramName, 'C')
            defaultVal = 1.3;
            minVal = 0.5;
            maxVal = 3;
        elseif strcmpi(paramName, 'D')
            defaultVal = 1;
            minVal = 0.1;
            maxVal = 5;
        elseif strcmpi(paramName, 'E')
            defaultVal = 0;
            minVal = -5;
            maxVal = 5;
        elseif contains(paramLower, 'x_m') || contains(paramLower, 'xm') || contains(paramLower, 'shift')
            defaultVal = 0;
            minVal = -10;
            maxVal = 10;
        elseif contains(paramLower, 'stiffness') || contains(paramLower, 'stiff')
            defaultVal = 10;
            minVal = 0.1;
            maxVal = 50;
        elseif contains(paramLower, 'peak') || contains(paramLower, 'max')
            defaultVal = 1;
            minVal = 0.1;
            maxVal = 5;
        elseif contains(paramLower, 'shape') || contains(paramLower, 'curv')
            defaultVal = 1.3;
            minVal = 0.5;
            maxVal = 3;
        end
    end
    
    % Callback functions
    function autoLoadDefaultData()
        defaultPath = 'C:\SimEnv\vehicleModel\components\tyre\calspanData_2017_separated.mat';
        
        if exist(defaultPath, 'file')
            try
                loadedData = load(defaultPath);
                
                if isfield(loadedData, 'tyreData')
                    appData.data = loadedData.tyreData;
                    set(fileLabel, 'String', 'Loaded: calspanData_2017_separated.mat', ...
                        'ForegroundColor', [0 0.6 0]);
                    
                    % Populate test type dropdown
                    testTypes = fieldnames(appData.data);
                    set(testTypeDropdown, 'String', testTypes, 'Value', 1);
                    
                    % Trigger test type selection
                    testTypeChanged();
                end
            catch
                % Silent fail - user can manually load
            end
        end
    end

    function loadPacejkaFormulas()
        if ~exist(appData.pacejkaPath, 'dir')
            set(pacejkaDropdown, 'String', {'None (folder not found)'});
            return;
        end
        
        % Get all .m files in the Pacejka folder
        files = dir(fullfile(appData.pacejkaPath, '*.m'));
        
        if isempty(files)
            set(pacejkaDropdown, 'String', {'None (no formulas found)'});
        else
            formulaNames = {'None'};
            for i = 1:length(files)
                [~, name, ~] = fileparts(files(i).name);
                formulaNames{end+1} = name; %#ok<AGROW>
            end
            set(pacejkaDropdown, 'String', formulaNames);
        end
    end

    function overlayPacejka(~, ~)
        if isempty(appData.data) || isempty(appData.currentTest)
            errordlg('Please load data and select a test first', 'No Data');
            return;
        end
        
        % Get selected formula
        formulas = get(pacejkaDropdown, 'String');
        selectedFormula = formulas{get(pacejkaDropdown, 'Value')};
        
        if strcmp(selectedFormula, 'None') || contains(selectedFormula, 'not found')
            errordlg('Please select a valid Pacejka formula', 'No Formula Selected');
            return;
        end
        
        % Get current data
        currentData = appData.data.(appData.currentTestType).(appData.currentTest);
        
        % Get X variable and create range
        xVars = get(xDropdown, 'String');
        xVar = xVars{get(xDropdown, 'Value')};
        xData = currentData.(xVar);
        
        % Create input range for formula
        xRange = linspace(min(xData), max(xData), 200);
        
        % Collect parameter values from dynamic controls
        paramValues = {};
        gammaParamIdx = [];
        
        for i = 1:length(appData.paramControls)
            editStr = get(appData.paramControls(i).edits, 'String');
            
            % Check if comma-separated list (for gamma/IA)
            if contains(editStr, ',')
                vals = str2num(['[', editStr, ']']); %#ok<ST2NM>
                if isempty(vals)
                    errordlg(sprintf('Invalid array format for parameter: %s', appData.paramControls(i).name), 'Input Error');
                    return;
                end
                paramValues{end+1} = vals; %#ok<AGROW>
                
                if strcmpi(appData.paramControls(i).name, 'gamma') || strcmpi(appData.paramControls(i).name, 'IA')
                    gammaParamIdx = i;
                end
            else
                val = str2double(editStr);
                if isnan(val)
                    errordlg(sprintf('Invalid value for parameter: %s', appData.paramControls(i).name), 'Input Error');
                    return;
                end
                paramValues{end+1} = val; %#ok<AGROW>
            end
        end
        
        % Parse varargin
        vararginStr = get(vararginEdit, 'String');
        if ~isempty(strtrim(vararginStr))
            try
                vararginVals = eval(['{', vararginStr, '}']);
                if ~isempty(vararginVals)
                    paramValues = [paramValues, vararginVals];
                end
            catch
                errordlg('Invalid varargin format. Use MATLAB syntax: ''name'', value, ...', 'Input Error');
                return;
            end
        end
        
        try
            % Call the Pacejka formula function
            yRange = feval(selectedFormula, xRange, paramValues{:});
            if size(yRange, 1) == 1
                yRange = yRange';
            end
            % Clear previous overlay
            if ~isempty(appData.pacejkaOverlay)
                if iscell(appData.pacejkaOverlay)
                    for i = 1:length(appData.pacejkaOverlay)
                        if ishandle(appData.pacejkaOverlay{i})
                            delete(appData.pacejkaOverlay{i});
                        end
                    end
                elseif ishandle(appData.pacejkaOverlay)
                    delete(appData.pacejkaOverlay);
                end
            end
            appData.pacejkaOverlay = {};
            
            hold(ax, 'on');
            
            if size(yRange, 2) > 1
                % Multiple curves
                colors = lines(size(yRange, 2));
                
                if ~isempty(gammaParamIdx)
                    gammaVals = paramValues{gammaParamIdx};
                else
                    gammaVals = 1:size(yRange, 2);
                end
                
                for i = 1:size(yRange, 2)
                    if ~isempty(gammaParamIdx)
                        legendStr = sprintf('%s (γ=%.1f°)', selectedFormula, gammaVals(i));
                    else
                        legendStr = sprintf('%s (curve %d)', selectedFormula, i);
                    end
                    
                    appData.pacejkaOverlay{i} = plot(ax, xRange, yRange(:, i), ...
                        'LineWidth', 2, 'Color', colors(i, :), ...
                        'DisplayName', legendStr);
                end
            else
                % Single curve
                appData.pacejkaOverlay{1} = plot(ax, xRange, yRange, 'r-', 'LineWidth', 2, ...
                    'DisplayName', sprintf('%s Fit', selectedFormula));
            end
            
            legend(ax, 'show', 'Location', 'best');
            hold(ax, 'off');
            
        catch ME
            errordlg(sprintf('Error evaluating formula: %s', ME.message), 'Formula Error');
        end
    end

    function clearPacejkaOverlay(~, ~)
        if ~isempty(appData.pacejkaOverlay)
            if iscell(appData.pacejkaOverlay)
                for i = 1:length(appData.pacejkaOverlay)
                    if ishandle(appData.pacejkaOverlay{i})
                        delete(appData.pacejkaOverlay{i});
                    end
                end
            elseif ishandle(appData.pacejkaOverlay)
                delete(appData.pacejkaOverlay);
            end
        end
        appData.pacejkaOverlay = [];
        legend(ax, 'off');
    end

    function toggleTool(toolName)
        % Turn off all tools first
        pan(fig, 'off');
        zoom(fig, 'off');
        rotate3d(fig, 'off');
        datacursormode(fig, 'off');
        
        % Turn on requested tool
        switch toolName
            case 'pan'
                pan(fig, 'on');
            case 'zoom'
                zoom(fig, 'on');
            case 'rotate'
                rotate3d(fig, 'on');
            case 'datacursor'
                datacursormode(fig, 'on');
        end
    end

    function resetView(~, ~)
        % Turn off all interaction modes
        pan(fig, 'off');
        zoom(fig, 'off');
        rotate3d(fig, 'off');
        datacursormode(fig, 'off');
        
        % Reset axis limits
        axis(ax, 'auto');
        
        % Reset view for 3D plots
        plotTypes = get(plotTypeDropdown, 'String');
        plotType = plotTypes{get(plotTypeDropdown, 'Value')};
        if strcmp(plotType, 'Surface')
            view(ax, 3);
        else
            view(ax, 2);
        end
    end

    function txt = dataCursorUpdateFcn(~, event_obj)
        % Custom data cursor display function
        pos = get(event_obj, 'Position');
        
        % Get variable names
        xVars = get(xDropdown, 'String');
        xVar = xVars{get(xDropdown, 'Value')};
        yVars = get(yDropdown, 'String');
        yVar = yVars{get(yDropdown, 'Value')};
        
        if length(pos) == 3
            % 3D data
            zVars = get(zDropdown, 'String');
            zVar = zVars{get(zDropdown, 'Value')};
            txt = {[xVar, ': ', num2str(pos(1))], ...
                   [yVar, ': ', num2str(pos(2))], ...
                   [zVar, ': ', num2str(pos(3))]};
        else
            % 2D data
            txt = {[xVar, ': ', num2str(pos(1))], ...
                   [yVar, ': ', num2str(pos(2))]};
        end
    end

    function loadDataCallback(~, ~)
        [file, path] = uigetfile('*.mat', 'Select Calspan Data File');
        if file == 0
            return;
        end
        
        try
            loadedData = load(fullfile(path, file));
            
            % Verify structure
            if ~isfield(loadedData, 'tyreData')
                errordlg('File does not contain tyreData field', 'Invalid File');
                return;
            end
            
            appData.data = loadedData.tyreData;
            set(fileLabel, 'String', sprintf('Loaded: %s', file), 'ForegroundColor', [0 0.6 0]);
            
            % Populate test type dropdown
            testTypes = fieldnames(appData.data);
            set(testTypeDropdown, 'String', testTypes, 'Value', 1);
            
            % Trigger test type selection
            testTypeChanged();
            
        catch ME
            errordlg(sprintf('Error loading file: %s', ME.message), 'Load Error');
        end
    end

    function testTypeChanged(~, ~)
        if isempty(appData.data)
            return;
        end
        
        testTypes = get(testTypeDropdown, 'String');
        idx = get(testTypeDropdown, 'Value');
        appData.currentTestType = testTypes{idx};
        
        % Get test names for this test type
        testNames = fieldnames(appData.data.(appData.currentTestType));
        set(testNameDropdown, 'String', testNames, 'Value', 1);
        
        if ~isempty(testNames)
            testNameChanged();
        end
    end

    function testNameChanged(~, ~)
        if isempty(appData.data)
            return;
        end
        
        testNames = get(testNameDropdown, 'String');
        idx = get(testNameDropdown, 'Value');
        appData.currentTest = testNames{idx};
        
        % Get variable names from current test data
        currentData = appData.data.(appData.currentTestType).(appData.currentTest);
        
        if istable(currentData)
            varNames = currentData.Properties.VariableNames;
        else
            errordlg('Selected test data is not a table', 'Data Error');
            return;
        end
        
        % Update variable dropdowns
        set(xDropdown, 'String', varNames, 'Value', 1);
        set(yDropdown, 'String', varNames, 'Value', min(2, length(varNames)));
        set(zDropdown, 'String', ['None', varNames], 'Value', 1);
        
        % Set some defaults if possible
        if any(strcmp(varNames, 'SA'))
            set(xDropdown, 'Value', find(strcmp(varNames, 'SA')));
        end
        
        if any(strcmp(varNames, 'FY'))
            set(yDropdown, 'Value', find(strcmp(varNames, 'FY')));
        end
        
        if any(strcmp(varNames, 'FZ'))
            set(zDropdown, 'Value', find(strcmp(['None', varNames], 'FZ')));
        end
    end

    function plotTypeChanged(~, ~)
        plotTypes = get(plotTypeDropdown, 'String');
        idx = get(plotTypeDropdown, 'Value');
        plotType = plotTypes{idx};
        
        if strcmp(plotType, 'Surface')
            set(zLabel, 'String', 'Z-axis:');
            if get(zDropdown, 'Value') == 1  % 'None' selected
                % Force selection for surface plot
                if length(get(zDropdown, 'String')) > 1
                    set(zDropdown, 'Value', 2);
                end
            end
        else
            set(zLabel, 'String', 'Color/Z-axis:');
        end
    end

    function updatePlot(~, ~)
        if isempty(appData.data) || isempty(appData.currentTest)
            errordlg('Please load data and select a test first', 'No Data');
            return;
        end
        
        % Turn off all interaction modes before updating plot
        pan(fig, 'off');
        zoom(fig, 'off');
        rotate3d(fig, 'off');
        datacursormode(fig, 'off');
        
        % Clear any Pacejka overlay
        clearPacejkaOverlay();
        
        % Get current data
        currentData = appData.data.(appData.currentTestType).(appData.currentTest);
        
        % Get selected variables
        xVars = get(xDropdown, 'String');
        xVar = xVars{get(xDropdown, 'Value')};
        
        yVars = get(yDropdown, 'String');
        yVar = yVars{get(yDropdown, 'Value')};
        
        zVars = get(zDropdown, 'String');
        zVar = zVars{get(zDropdown, 'Value')};
        
        plotTypes = get(plotTypeDropdown, 'String');
        plotType = plotTypes{get(plotTypeDropdown, 'Value')};
        
        % Get filter strings
        xFilterStr = get(xFilterEdit, 'String');
        yFilterStr = get(yFilterEdit, 'String');
        zFilterStr = get(zFilterEdit, 'String');
        
        % Clear previous plot
        cla(ax);
        
        try
            % Extract data
            xData = currentData.(xVar);
            yData = currentData.(yVar);
            
            % Apply filters
            try
                xMask = applyFilter(xData, xFilterStr);1
                yMask = applyFilter(yData, yFilterStr);
                
                % Combined mask
                combinedMask = xMask & yMask;
                
                % Apply Z filter if applicable
                if ~strcmp(zVar, 'None')
                    zData = currentData.(zVar);
                    zMask = applyFilter(zData, zFilterStr);
                    combinedMask = combinedMask & zMask;
                end
                
                % Filter data
                xData = xData(combinedMask);
                yData = yData(combinedMask);
                
                if isempty(xData)
                    errordlg('No data points match the filter criteria', 'Empty Result');
                    return;
                end
                
            catch ME
                errordlg(sprintf('Filter error: %s', ME.message), 'Invalid Filter');
                return;
            end
            
            % Plot based on type
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
                        errordlg('Surface plot requires Z variable', 'Missing Variable');
                        return;
                    end
                    
                    zData = currentData.(zVar);
                    zData = zData(combinedMask);
                    
                    % Create gridded data for surface
                    try
                        [X, Y, Z] = griddata(xData, yData, zData, ...
                            linspace(min(xData), max(xData), 50)', ...
                            linspace(min(yData), max(yData), 50), ...
                            'natural');
                        surf(ax, X, Y, Z, 'EdgeColor', 'none');
                        colorbar(ax);
                        view(ax, 3);
                    catch
                        errordlg('Unable to create surface. Data may not be suitable for gridding.', 'Surface Error');
                        return;
                    end
            end
            
            % Labels and title
            xlabel(ax, xVar);
            ylabel(ax, yVar);
            
            % Add filter info to title
            filterInfo = '';
            if ~isempty(strtrim(xFilterStr))
                filterInfo = sprintf('X:%s ', xFilterStr);
            end
            if ~isempty(strtrim(yFilterStr))
                filterInfo = [filterInfo, sprintf('Y:%s ', yFilterStr)];
            end
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
            errordlg(sprintf('Error plotting: %s', ME.message), 'Plot Error');
        end
    end

    function exportPlotCallback(~, ~)
        [file, path] = uiputfile('*.png', 'Save Plot As');
        if file == 0
            return;
        end
        
        % Export current figure
        print(fig, fullfile(path, file), '-dpng', '-r300');
        msgbox('Plot saved successfully!', 'Success');
    end

    function exportDataCallback(~, ~)
        if isempty(appData.data) || isempty(appData.currentTest)
            errordlg('No data to export', 'No Data');
            return;
        end
        
        [file, path] = uiputfile('*.csv', 'Save Data As');
        if file == 0
            return;
        end
        
        % Get current data
        currentData = appData.data.(appData.currentTestType).(appData.currentTest);
        
        % Write to CSV
        writetable(currentData, fullfile(path, file));
        msgbox('Data saved successfully!', 'Success');
    end
end
