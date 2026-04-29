function SmpExplorer()
% SMPEXPLORER  SMP Cache Explorer GUI
%
% Loads an existing SMP cache, filters to sessions/teams/laps,
% and plots channels via manual builder or Excel presets.
%
% Usage:  SmpExplorer()
%
% Requires MATLAB R2021a or later (uifigure / App Designer components).

    %% ---- Ensure required paths are on the MATLAB path ----
    thisDir  = fileparts(mfilename('fullpath'));
    motecDir = fullfile(thisDir, '..', 'Motec_MP');
    addpath(thisDir);
    addpath(fullfile(motecDir, 'plot'));
    addpath(fullfile(motecDir, 'motecFiltering'));
    addpath(fullfile(motecDir, 'alias'));

    %% ---- Figure ----
    fig = uifigure( ...
        'Name',     'SMP Cache Explorer', ...
        'Position', [80 60 1380 830]);

    %% ---- App state (stored via guidata) ----
    app                   = struct();
    app.cache             = [];
    app.SMP               = [];
    app.cfg               = [];
    app.alias             = [];
    app.driver_map        = [];
    app.availableChannels = {};
    app.plotQueue         = [];
    app.exprCount         = 0;
    app.excelPlots        = [];
    app.filterModeOn      = false;
    app.fitLines          = [];
    app.drag              = struct('active', false, 'ax', [], ...
                                   'x0', NaN, 'y0', NaN, 'rectH', []);
    guidata(fig, app);

    %% ====================================================================
    %  ROOT GRID  --  3 columns: left | centre | right
    %% ====================================================================
    root = uigridlayout(fig, [1 3]);
    root.ColumnWidth   = {282, '1x', 242};
    root.RowHeight     = {'1x'};
    root.Padding       = [6 6 6 6];
    root.ColumnSpacing = 6;

    %% ====================================================================
    %  LEFT PANEL  --  Cache, Manifest, Filters
    %% ====================================================================
    leftPnl = uipanel(root, 'BorderType', 'line', 'Title', 'Cache & Filters');
    leftPnl.Layout.Column = 1;

    LG = uigridlayout(leftPnl, [17 1]);
    LG.RowHeight  = {22, 22, 22, 22, 22, '1x', 18, 14, 90, 14, 90, 14, 90, 14, 22, 22, 18};
    LG.Padding    = [6 6 6 6];
    LG.RowSpacing = 3;

    lbl = uilabel(LG, 'Text', 'CACHE', 'FontWeight', 'bold', 'FontSize', 10);
    lbl.Layout.Row = 1;

    hPathField = uieditfield(LG, 'text');
    hPathField.Layout.Row = 2;

    hBrowseBtn = uibutton(LG, 'Text', 'Browse Folder...');
    hBrowseBtn.Layout.Row = 3;
    hBrowseBtn.ButtonPushedFcn = @(~,~) onBrowse(fig, hPathField);

    hBrowseFileBtn = uibutton(LG, 'Text', 'Browse .mat File...');
    hBrowseFileBtn.Layout.Row = 4;
    hBrowseFileBtn.ButtonPushedFcn = @(~,~) onBrowseFile(fig, hPathField);

    hLoadBtn = uibutton(LG, 'Text', 'Load Cache', ...
        'BackgroundColor', [0.18 0.44 0.73], 'FontColor', [1 1 1], 'FontWeight', 'bold');
    hLoadBtn.Layout.Row = 5;
    hLoadBtn.ButtonPushedFcn = @(~,~) onLoadCache(fig, hPathField);

    hManifest = uitable(LG, ...
        'ColumnName',  {'Driver', 'Team', 'Session', 'Date'}, ...
        'ColumnWidth', {70, 50, 65, 62}, ...
        'RowName', {});
    hManifest.Layout.Row = 6;

    hStatusLbl = uilabel(LG, 'Text', 'No cache loaded', ...
        'FontColor', [0.5 0.5 0.5], 'HorizontalAlignment', 'center', 'FontSize', 9);
    hStatusLbl.Layout.Row = 7;

    lbl = uilabel(LG, 'Text', 'SESSIONS (ctrl+click)', 'FontWeight', 'bold', 'FontSize', 9);
    lbl.Layout.Row = 8;

    hSessionsList = uilistbox(LG, 'Items', {}, 'Multiselect', 'on');
    hSessionsList.Layout.Row = 9;

    lbl = uilabel(LG, 'Text', 'TEAMS (ctrl+click)', 'FontWeight', 'bold', 'FontSize', 9);
    lbl.Layout.Row = 10;

    hTeamsList = uilistbox(LG, 'Items', {}, 'Multiselect', 'on');
    hTeamsList.Layout.Row = 11;

    lbl = uilabel(LG, 'Text', 'MANUFACTURERS (ctrl+click)', 'FontWeight', 'bold', 'FontSize', 9);
    lbl.Layout.Row = 12;

    hMfrList = uilistbox(LG, 'Items', {}, 'Multiselect', 'on');
    hMfrList.Layout.Row = 13;

    lbl = uilabel(LG, 'Text', 'LAP RANGE  (min / max)', 'FontWeight', 'bold', 'FontSize', 9);
    lbl.Layout.Row = 14;

    lapGrid = uigridlayout(LG, [1 2]);
    lapGrid.Layout.Row  = 15;
    lapGrid.ColumnWidth = {'1x', '1x'};
    lapGrid.Padding     = [0 0 0 0];
    hLapMin = uispinner(lapGrid, 'Value', 1,    'Limits', [1 9999], 'Step', 1);
    hLapMin.Layout.Column = 1;
    hLapMax = uispinner(lapGrid, 'Value', 9999, 'Limits', [1 9999], 'Step', 1);
    hLapMax.Layout.Column = 2;

    hFilterBtn = uibutton(LG, 'Text', 'Apply Filters', ...
        'BackgroundColor', [0.17 0.56 0.30], 'FontColor', [1 1 1], 'FontWeight', 'bold');
    hFilterBtn.Layout.Row = 16;
    hFilterBtn.ButtonPushedFcn = @(~,~) onApplyFilters(fig, ...
        hSessionsList, hTeamsList, hMfrList, hLapMin, hLapMax);

    hFilterStatus = uilabel(LG, 'Text', '', ...
        'FontColor', [0.3 0.7 0.3], 'HorizontalAlignment', 'center', ...
        'FontSize', 9);
    hFilterStatus.Layout.Row = 17;

    %% ====================================================================
    %  CENTRE PANEL  --  TabGroup: Manual Builder | Excel Presets
    %% ====================================================================
    centrePnl = uipanel(root, 'BorderType', 'line', 'Title', 'Plot Configuration');
    centrePnl.Layout.Column = 2;

    centreGrid = uigridlayout(centrePnl, [1 1]);
    centreGrid.Padding = [0 0 0 0];

    tabGrp = uitabgroup(centreGrid);

    %% ---- TAB 1: Manual Builder ----
    tab1 = uitab(tabGrp, 'Title', 'Manual Builder');

    t1Outer = uigridlayout(tab1, [2 2]);
    t1Outer.ColumnWidth   = {340, '1x'};
    t1Outer.RowHeight     = {'1x', 32};
    t1Outer.Padding       = [6 6 6 6];
    t1Outer.ColumnSpacing = 6;

    ctrlPnl = uipanel(t1Outer, 'BorderType', 'line', 'Title', 'Plot Definition');
    ctrlPnl.Layout.Row    = 1;
    ctrlPnl.Layout.Column = 1;

    hPlotPnl = uipanel(t1Outer, 'BorderType', 'line', 'Title', 'Plot');
    hPlotPnl.Layout.Row    = 1;
    hPlotPnl.Layout.Column = 2;

    % ---- Post-Plot Tools bar (row 2, spans both columns) ----
    postPnl = uipanel(t1Outer, 'BorderType', 'none');
    postPnl.Layout.Row    = 2;
    postPnl.Layout.Column = [1 2];

    PPG = uigridlayout(postPnl, [1 5]);
    PPG.ColumnWidth   = {'1x','1x','1x','1x','1x'};
    PPG.RowHeight     = {'1x'};
    PPG.Padding       = [2 2 2 2];
    PPG.ColumnSpacing = 4;

    hFilterModeBtn = uibutton(PPG, 'Text', 'Filter Mode: OFF', ...
        'BackgroundColor', [0.4 0.4 0.4], 'FontColor', [1 1 1]);
    hFilterModeBtn.Layout.Column = 1;
    hFilterModeBtn.ButtonPushedFcn = @(~,~) onToggleFilterMode(fig);

    hClearExcluded = uibutton(PPG, 'Text', 'Clear Excluded');
    hClearExcluded.Layout.Column = 2;
    hClearExcluded.ButtonPushedFcn = @(~,~) onClearExcluded(fig);

    hLinearFitBtn = uibutton(PPG, 'Text', 'Linear Fit', ...
        'BackgroundColor', [0.18 0.53 0.77], 'FontColor', [1 1 1]);
    hLinearFitBtn.Layout.Column = 3;
    hLinearFitBtn.ButtonPushedFcn = @(~,~) onApplyFit(fig, 1);

    hCubicFitBtn = uibutton(PPG, 'Text', 'Cubic Fit', ...
        'BackgroundColor', [0.49 0.18 0.77], 'FontColor', [1 1 1]);
    hCubicFitBtn.Layout.Column = 4;
    hCubicFitBtn.ButtonPushedFcn = @(~,~) onApplyFit(fig, 3);

    hClearFitsBtn = uibutton(PPG, 'Text', 'Clear Fits');
    hClearFitsBtn.Layout.Column = 5;
    hClearFitsBtn.ButtonPushedFcn = @(~,~) onClearFits(fig);

    NCTRL_ROWS = 24;
    CG = uigridlayout(ctrlPnl, [NCTRL_ROWS 2]);
    CG.ColumnWidth = {130, '1x'};
    CG.RowHeight   = repmat({22}, 1, NCTRL_ROWS);
    CG.Padding     = [8 6 8 6];
    CG.RowSpacing  = 3;

    r = 1;

    lbl = uilabel(CG, 'Text', 'Plot Name');
    lbl.Layout.Row = r;
    hPlotName = uieditfield(CG, 'text', 'Value', 'My Plot');
    hPlotName.Layout.Row = r; hPlotName.Layout.Column = 2;
    r = r + 1;

    PLOT_TYPES = {'scatter', 'line', 'timeseries', 'timeseries_align', ...
                  'boxplot', 'violin', 'histogram', 'ranked_box', ...
                  'lapwise_box', 'sessionlapwise', 'psd', 'big_scatter', 'scatter_trace'};
    lbl = uilabel(CG, 'Text', 'Plot Type');
    lbl.Layout.Row = r;
    hPlotType = uidropdown(CG, 'Items', PLOT_TYPES, 'Value', 'scatter');
    hPlotType.Layout.Row = r; hPlotType.Layout.Column = 2;
    hPlotType.ValueChangedFcn = @(src,~) onPlotTypeChanged(fig, src);
    r = r + 1;

    MATH_FNS = {'mean', 'max', 'min', 'median', 'mean non zero', ...
                'min non zero', 'max non zero', 'std', 'range', ...
                'change', 'final', 'initial', 'lap_delta'};
    lbl = uilabel(CG, 'Text', 'Math Function');
    lbl.Layout.Row = r;
    hMathFn = uidropdown(CG, 'Items', MATH_FNS, 'Value', 'mean');
    hMathFn.Layout.Row = r; hMathFn.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'X Axis');
    lbl.Layout.Row = r;
    hXAxis = uidropdown(CG, 'Items', {'(load cache first)'}, 'Value', '(load cache first)');
    hXAxis.Layout.Row = r; hXAxis.Layout.Column = 2;
    r = r + 1;

    axLabels = {'Y Axis 1', 'Y Axis 2', 'Y Axis 3', 'Y Axis 4'};
    hYAxis = gobjects(1, 4);
    for yi = 1:4
        lbl = uilabel(CG, 'Text', axLabels{yi});
        lbl.Layout.Row = r;
        hYAxis(yi) = uidropdown(CG, 'Items', {'(load cache first)'}, ...
            'Value', '(load cache first)');
        hYAxis(yi).Layout.Row = r; hYAxis(yi).Layout.Column = 2;
        r = r + 1;
    end

    lbl = uilabel(CG, 'Text', 'Custom Expression', 'FontColor', [0.85 0.65 0.1]);
    lbl.Layout.Row = r;
    hCustomExpr = uieditfield(CG, 'text', 'Value', '');
    hCustomExpr.Layout.Row = r; hCustomExpr.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Colour Mode');
    lbl.Layout.Row = r;
    hColourMode = uidropdown(CG, 'Items', {'manufacturer', 'driver', 'team', 'car', 'number'}, ...
        'Value', 'manufacturer');
    hColourMode.Layout.Row = r; hColourMode.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Differentiator');
    lbl.Layout.Row = r;
    hDiffer = uidropdown(CG, 'Items', {'manufacturer', 'driver', 'team', 'car', ''}, ...
        'Value', 'manufacturer');
    hDiffer.Layout.Row = r; hDiffer.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Use Secondary Y');
    lbl.Layout.Row = r;
    hSecondary = uicheckbox(CG, 'Text', '', 'Value', false);
    hSecondary.Layout.Row = r; hSecondary.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'X Limits');
    lbl.Layout.Row = r;
    hXLim = uieditfield(CG, 'text', 'Value', '');
    hXLim.Layout.Row = r; hXLim.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Y Limits');
    lbl.Layout.Row = r;
    hYLim = uieditfield(CG, 'text', 'Value', '');
    hYLim.Layout.Row = r; hYLim.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Outliers');
    lbl.Layout.Row = r;
    hOutliers = uicheckbox(CG, 'Text', '', 'Value', false);
    hOutliers.Layout.Row = r; hOutliers.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Outlier Method');
    lbl.Layout.Row = r;
    hOutlierMethod = uidropdown(CG, 'Items', {'mad', 'iqr'}, 'Value', 'mad');
    hOutlierMethod.Layout.Row = r; hOutlierMethod.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Outlier Threshold');
    lbl.Layout.Row = r;
    hOutlierThresh = uispinner(CG, 'Value', 3.0, 'Limits', [0.1 20], 'Step', 0.5);
    hOutlierThresh.Layout.Row = r; hOutlierThresh.Layout.Column = 2;
    r = r + 1;

    hAlignLbl = uilabel(CG, 'Text', '-- Align Options (timeseries_align only) --', ...
        'HorizontalAlignment', 'center', 'FontColor', [0.4 0.55 0.8], 'FontSize', 9);
    hAlignLbl.Layout.Row    = r;
    hAlignLbl.Layout.Column = [1 2];
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Align Channel');
    lbl.Layout.Row = r;
    hAlignCh = uidropdown(CG, 'Items', {'(none)'}, 'Value', '(none)', 'Enable', 'off');
    hAlignCh.Layout.Row = r; hAlignCh.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Align Window');
    lbl.Layout.Row = r;
    hAlignWin = uieditfield(CG, 'text', 'Value', '', 'Enable', 'off');
    hAlignWin.Layout.Row = r; hAlignWin.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Align Method');
    lbl.Layout.Row = r;
    hAlignMethod = uidropdown(CG, 'Items', {'peaks', 'xcorr'}, 'Value', 'peaks', 'Enable', 'off');
    hAlignMethod.Layout.Row = r; hAlignMethod.Layout.Column = 2;
    r = r + 1;

    lbl = uilabel(CG, 'Text', 'Align Max Offset (s)');
    lbl.Layout.Row = r;
    hAlignMax = uispinner(CG, 'Value', 60, 'Limits', [1 600], 'Step', 5, 'Enable', 'off');
    hAlignMax.Layout.Row = r; hAlignMax.Layout.Column = 2;
    r = r + 1;

    hPlotBtn = uibutton(CG, 'Text', 'Plot', ...
        'BackgroundColor', [0.17 0.56 0.30], 'FontColor', [1 1 1], 'FontWeight', 'bold');
    hPlotBtn.Layout.Row    = r;
    hPlotBtn.Layout.Column = [1 2];
    hPlotBtn.ButtonPushedFcn = @(~,~) onPlotDirect(fig);

    %% ---- TAB 2: Excel Presets ----
    tab2 = uitab(tabGrp, 'Title', 'Excel Presets');

    T2G = uigridlayout(tab2, [4 2]);
    T2G.ColumnWidth = {120, '1x'};
    T2G.RowHeight   = {22, 22, '1x', 30};
    T2G.Padding     = [8 8 8 8];
    T2G.RowSpacing  = 4;

    lbl = uilabel(T2G, 'Text', 'Excel File');
    lbl.Layout.Row = 1; lbl.Layout.Column = 1;
    hExcelPath = uieditfield(T2G, 'text', 'Value', '');
    hExcelPath.Layout.Row = 1; hExcelPath.Layout.Column = 2;

    hExcelBrowse = uibutton(T2G, 'Text', 'Browse...');
    hExcelBrowse.Layout.Row = 2; hExcelBrowse.Layout.Column = 1;
    hExcelBrowse.ButtonPushedFcn = @(~,~) onBrowseExcel(fig, hExcelPath);

    hExcelLoad = uibutton(T2G, 'Text', 'Load Excel Config', ...
        'BackgroundColor', [0.18 0.44 0.73], 'FontColor', [1 1 1]);
    hExcelLoad.Layout.Row = 2; hExcelLoad.Layout.Column = 2;
    hExcelLoad.ButtonPushedFcn = @(~,~) onLoadExcel(fig, hExcelPath);

    hExcelTable = uitable(T2G, ...
        'ColumnName',     {'Plot', 'Name', 'Type', 'X', 'Y1', 'Math'}, ...
        'ColumnWidth',    {35, 140, 90, 90, 90, 70}, ...
        'ColumnEditable', [true false false false false false], ...
        'RowName', {});
    hExcelTable.Layout.Row = 3; hExcelTable.Layout.Column = [1 2];

    e2BtnGrid = uigridlayout(T2G, [1 2]);
    e2BtnGrid.Layout.Row = 4; e2BtnGrid.Layout.Column = [1 2];
    e2BtnGrid.ColumnWidth = {'1x', '1x'};
    e2BtnGrid.Padding = [0 0 0 0];

    hExcelPlotSel = uibutton(e2BtnGrid, 'Text', 'Plot Checked', ...
        'BackgroundColor', [0.17 0.56 0.30], 'FontColor', [1 1 1]);
    hExcelPlotSel.Layout.Column = 1;
    hExcelPlotSel.ButtonPushedFcn = @(~,~) onPlotExcel(fig, hExcelTable, 'selected');

    hExcelPlotAll = uibutton(e2BtnGrid, 'Text', 'Plot All', ...
        'BackgroundColor', [0.13 0.42 0.22], 'FontColor', [1 1 1]);
    hExcelPlotAll.Layout.Column = 2;
    hExcelPlotAll.ButtonPushedFcn = @(~,~) onPlotExcel(fig, hExcelTable, 'all');

    %% ====================================================================
    %  RIGHT PANEL  --  Log
    %% ====================================================================
    rightPnl = uipanel(root, 'BorderType', 'line', 'Title', 'Log');
    rightPnl.Layout.Column = 3;

    RG = uigridlayout(rightPnl, [2 1]);
    RG.RowHeight  = {'1x', 26};
    RG.Padding    = [6 6 6 6];
    RG.RowSpacing = 4;

    hLog = uitextarea(RG, ...
        'Value',    {'SMP Cache Explorer ready.'}, ...
        'Editable', 'off', ...
        'FontName', 'Courier New', ...
        'FontSize', 8);
    hLog.Layout.Row = 1;

    hClearLog = uibutton(RG, 'Text', 'Clear Log');
    hClearLog.Layout.Row = 2;
    hClearLog.ButtonPushedFcn = @(~,~) set(hLog, 'Value', {'Log cleared.'});

    %% ---- Store all handles in guidata ----
    app = guidata(fig);
    app.handles.pathField     = hPathField;
    app.handles.manifest      = hManifest;
    app.handles.statusLbl     = hStatusLbl;
    app.handles.sessionsList  = hSessionsList;
    app.handles.teamsList     = hTeamsList;
    app.handles.mfrList       = hMfrList;
    app.handles.lapMin        = hLapMin;
    app.handles.lapMax        = hLapMax;
    app.handles.filterStatus  = hFilterStatus;
    app.handles.plotName      = hPlotName;
    app.handles.plotType      = hPlotType;
    app.handles.mathFn        = hMathFn;
    app.handles.xAxis         = hXAxis;
    app.handles.yAxis         = hYAxis;
    app.handles.customExpr    = hCustomExpr;
    app.handles.colourMode    = hColourMode;
    app.handles.differ        = hDiffer;
    app.handles.secondary     = hSecondary;
    app.handles.xLim          = hXLim;
    app.handles.yLim          = hYLim;
    app.handles.outliers      = hOutliers;
    app.handles.outlierMethod = hOutlierMethod;
    app.handles.outlierThresh = hOutlierThresh;
    app.handles.alignLbl      = hAlignLbl;
    app.handles.alignCh       = hAlignCh;
    app.handles.alignWin      = hAlignWin;
    app.handles.alignMethod   = hAlignMethod;
    app.handles.alignMax      = hAlignMax;
    app.handles.plotPnl       = hPlotPnl;
    app.handles.excelPath     = hExcelPath;
    app.handles.excelTable    = hExcelTable;
    app.handles.log           = hLog;
    app.handles.filterModeBtn = hFilterModeBtn;
    app.handles.clearExcluded = hClearExcluded;
    app.handles.linearFitBtn  = hLinearFitBtn;
    app.handles.cubicFitBtn   = hCubicFitBtn;
    app.handles.clearFitsBtn  = hClearFitsBtn;
    guidata(fig, app);

end % SmpExplorer

%% =========================================================================
%  CALLBACK: Browse folder
%% =========================================================================
function onBrowse(fig, pathField) %#ok<INUSL>
    folder = uigetdir('', 'Select folder containing smp_cache*.mat');
    if isequal(folder, 0), return; end
    pathField.Value = folder;
end

%% =========================================================================
%  CALLBACK: Browse .mat file
%% =========================================================================
function onBrowseFile(fig, pathField) %#ok<INUSL>
    [f, d] = uigetfile({'*.mat', 'Cache Files (*.mat)'}, 'Select smp_cache*.mat file');
    if isequal(f, 0), return; end
    pathField.Value = fullfile(d, f);
end

%% =========================================================================
%  CALLBACK: Load Cache
%% =========================================================================
function onLoadCache(fig, pathField)
    app = guidata(fig);
    h   = app.handles;

    pathVal = strtrim(pathField.Value);
    if isempty(pathVal)
        appendLog(h.log, 'ERROR: No path specified.');
        h.statusLbl.Text      = 'No path specified';
        h.statusLbl.FontColor = [0.8 0.2 0.2];
        return;
    end

    appendLog(h.log, sprintf('Loading cache: %s', pathVal));
    h.statusLbl.Text      = 'Loading...';
    h.statusLbl.FontColor = [0.8 0.7 0.1];
    drawnow;

    try
        [~,~,pathExt] = fileparts(pathVal);
        if isfile(pathVal) && strcmpi(pathExt, '.mat')
            loaded = load(pathVal);
            fnames = fieldnames(loaded);
            cache  = loaded.(fnames{1});
        elseif isfolder(pathVal)
            cache = smp_cache_load(pathVal);
        else
            appendLog(h.log, 'ERROR: Path is not a valid folder or .mat file.');
            h.statusLbl.Text      = 'Invalid path';
            h.statusLbl.FontColor = [0.8 0.2 0.2];
            return;
        end
    catch ME
        appendLog(h.log, sprintf('ERROR (smp_cache_load): %s', ME.message));
        h.statusLbl.Text      = 'Load failed';
        h.statusLbl.FontColor = [0.8 0.2 0.2];
        return;
    end
    app.cache = cache;

    try
        app.cfg = smp_colours();
    catch
        app.cfg = struct();
    end

    try
        thisDir   = fileparts(mfilename('fullpath'));
        aliasFile = fullfile(thisDir, '..', 'Motec_MP', 'alias', 'eventAlias.xlsx');
        if isfile(aliasFile)
            app.alias = smp_alias_load(aliasFile);
            appendLog(h.log, '  Alias file loaded.');
        else
            app.alias = smp_alias_load([]);
            appendLog(h.log, '  No eventAlias.xlsx found -- raw matching only.');
        end
    catch
        app.alias = smp_alias_load([]);
    end

    try
        driverAliasFile = fullfile(thisDir, '..', 'Motec_MP', 'alias', 'driverAlias.xlsx');
        if isfile(driverAliasFile)
            app.driver_map = smp_driver_alias_load(driverAliasFile);
            appendLog(h.log, '  Driver alias file loaded.');
        else
            app.driver_map = [];
            appendLog(h.log, '  No driverAlias.xlsx found -- car numbers from MoTeC headers.');
        end
    catch ME2
        app.driver_map = [];
        appendLog(h.log, sprintf('  WARN (driverAlias): %s', ME2.message));
    end

    chans = {};
    if isfield(cache, 'stats')
        skeys = fieldnames(cache.stats);
        if ~isempty(skeys)
            first = cache.stats.(skeys{1});
            if isstruct(first)
                raw_fields = fieldnames(first);
                skip = {'lap_numbers','lap_times','lap_types','units','raw_name','channel_field'};
                chans = raw_fields(~ismember(raw_fields, skip));
            end
        end
    end
    app.availableChannels = chans;

    T = cache.manifest;
    if ~isempty(T) && height(T) > 0
        want_cols = {'Driver', 'TeamAcronym', 'Session', 'LogDate'};
        have_cols = T.Properties.VariableNames;
        disp_data = cell(height(T), numel(want_cols));
        for ci = 1:numel(want_cols)
            if ismember(want_cols{ci}, have_cols)
                col_data = T.(want_cols{ci});
                if ~iscell(col_data)
                    col_data = cellstr(string(col_data));
                end
                disp_data(:, ci) = col_data;
            else
                disp_data(:, ci) = repmat({''}, height(T), 1);
            end
        end
        h.manifest.Data = disp_data;
    end

    if ismember('Session', T.Properties.VariableNames)
        sessions = unique(cellstr(string(T.Session)));
        h.sessionsList.Items = sort(sessions);
    end

    if ismember('TeamAcronym', T.Properties.VariableNames)
        teams = unique(cellstr(string(T.TeamAcronym)));
        h.teamsList.Items = sort(teams);
    end

    if ismember('Manufacturer', T.Properties.VariableNames)
        mfrs = unique(cellstr(string(T.Manufacturer)));
        h.mfrList.Items = sort(mfrs);
    end

    chans_cell = chans(:)';
    if isempty(chans_cell)
        chans_cell = {'(no channels found)'};
    end
    ch_with_none = [{'(none)'}, chans_cell];

    h.xAxis.Items = chans_cell;
    h.xAxis.Value = chans_cell{1};
    for yi = 1:4
        if yi == 1
            h.yAxis(1).Items = chans_cell;
            h.yAxis(1).Value = chans_cell{1};
        else
            h.yAxis(yi).Items = ch_with_none;
            h.yAxis(yi).Value = '(none)';
        end
    end
    h.alignCh.Items = ch_with_none;
    h.alignCh.Value = '(none)';

    all_laps = [];
    if isfield(cache, 'traces')
        tkeys = fieldnames(cache.traces);
        for k = 1:numel(tkeys)
            tr = cache.traces.(tkeys{k});
            if isfield(tr, 'lap_numbers')
                all_laps = [all_laps, tr.lap_numbers(:)']; %#ok<AGROW>
            end
        end
    end
    if ~isempty(all_laps)
        lo = min(all_laps);
        hi = max(all_laps);
        h.lapMin.Limits = [lo hi];
        h.lapMax.Limits = [lo hi];
        h.lapMin.Value  = lo;
        h.lapMax.Value  = hi;
    end

    n_entries = height(T);
    h.statusLbl.Text      = sprintf('%d entries loaded', n_entries);
    h.statusLbl.FontColor = [0.2 0.7 0.3];
    appendLog(h.log, sprintf('  OK: %d manifest entries, %d channels found.', ...
        n_entries, numel(chans)));

    guidata(fig, app);
end

%% =========================================================================
%  CALLBACK: Apply Filters
%% =========================================================================
function onApplyFilters(fig, sessionsList, teamsList, mfrList, lapMin, lapMax) %#ok<INUSL>
    app = guidata(fig);
    h   = app.handles;

    if isempty(app.cache)
        appendLog(h.log, 'ERROR: Load a cache first.');
        return;
    end

    appendLog(h.log, 'Applying filters...');
    drawnow;

    filter_args = {};
    sess_sel = sessionsList.Value;
    if ~isempty(sess_sel)
        filter_args = [filter_args, {'Session', sess_sel}];
    end
    team_sel = teamsList.Value;
    if ~isempty(team_sel)
        filter_args = [filter_args, {'Team', team_sel}];
    end
    mfr_sel = mfrList.Value;
    if ~isempty(mfr_sel)
        filter_args = [filter_args, {'Manufacturer', mfr_sel}];
    end

    try
        SMP = smp_filter_cache(app.cache, app.alias, filter_args{:});
        app.SMP = SMP;
        guidata(fig, app);

        n_laps   = 0;
        sess_set = {};
        team_keys = fieldnames(SMP);
        for t = 1:numel(team_keys)
            node = SMP.(team_keys{t});
            if ~isempty(node.meta) && ismember('Session', node.meta.Properties.VariableNames)
                sess_set = union(sess_set, cellstr(string(node.meta.Session)));
            end
            for rr = 1:numel(node.stats)
                st = node.stats{rr};
                if isempty(st), continue; end
                fn = fieldnames(st);
                if ~isempty(fn) && isfield(st.(fn{1}), 'lap_numbers')
                    n_laps = n_laps + numel(st.(fn{1}).lap_numbers);
                end
            end
        end

        msg = sprintf('%d laps, %d session(s)', n_laps, numel(sess_set));
        h.filterStatus.Text = msg;
        appendLog(h.log, sprintf('  Filtered: %s.', msg));

    catch ME
        appendLog(h.log, sprintf('  Filter error: %s', ME.message));
        h.filterStatus.Text = 'Filter error -- see log';
    end
end

%% =========================================================================
%  CALLBACK: Plot Type changed
%% =========================================================================
function onPlotTypeChanged(fig, src)
    app = guidata(fig);
    h   = app.handles;
    t   = src.Value;

    is_align    = strcmpi(t, 'timeseries_align');
    align_state = onOff(is_align);
    h.alignCh.Enable     = align_state;
    h.alignWin.Enable    = align_state;
    h.alignMethod.Enable = align_state;
    h.alignMax.Enable    = align_state;

    multi_y = {'timeseries', 'timeseries_align', 'line'};
    y_state = onOff(ismember(t, multi_y));
    h.yAxis(2).Enable = y_state;
    h.yAxis(3).Enable = y_state;
    h.yAxis(4).Enable = y_state;
end

%% =========================================================================
%  CALLBACK: Plot Direct (from Manual Builder)
%% =========================================================================
function onPlotDirect(fig)
    app = guidata(fig);
    h   = app.handles;

    if isempty(app.SMP)
        appendLog(h.log, 'ERROR: Apply filters first to build the SMP dataset.');
        return;
    end

    expr = strtrim(h.customExpr.Value);
    if ~isempty(expr)
        app.exprCount = app.exprCount + 1;
        y_channels = {};
    else
        y_channels = {h.yAxis(1).Value};
        for yi = 2:4
            v = h.yAxis(yi).Value;
            if ~strcmpi(v, '(none)') && ~isempty(v)
                y_channels{end+1} = v; %#ok<AGROW>
            end
        end
    end

    p = struct();
    p.name               = h.plotName.Value;
    p.type               = h.plotType.Value;
    p.math_fn            = h.mathFn.Value;
    p.x_axis             = h.xAxis.Value;
    p.y_channels         = y_channels;
    p.z_axis             = '';
    p.colour_mode        = h.colourMode.Value;
    p.differentiator     = h.differ.Value;
    p.use_secondary      = h.secondary.Value;
    p.plot_filter        = '';
    p.x_lim              = parseLim(h.xLim.Value);
    p.y_lim              = parseLim(h.yLim.Value);
    p.highlight_outliers = h.outliers.Value;
    p.outlier_method     = h.outlierMethod.Value;
    p.outlier_threshold  = h.outlierThresh.Value;
    p.outlier_scope      = 'manufacturer';
    p.align_channel      = h.alignCh.Value;
    p.align_window       = parseLim(h.alignWin.Value);
    p.align_method       = h.alignMethod.Value;
    p.align_max_offset   = h.alignMax.Value;
    p.fig_num            = NaN;
    p.fig_layout         = [];
    p.fig_pos            = [];
    p.pptx_title         = '';
    p.custom_expr        = expr;

    [SMP_plot, plots_out] = injectCustomExprs(app.SMP, p, h.log);

    appendLog(h.log, sprintf('Plotting: "%s" (%s)', p.name, p.type));
    drawnow;
    opts = struct('verbose', true);
    try
        figs = smp_plot_from_config(SMP_plot, plots_out, app.cfg, app.driver_map, opts);

        % Find first valid generated figure
        srcFig = [];
        for fi = 1:numel(figs)
            if ~isempty(figs{fi}) && ishandle(figs{fi})
                srcFig = figs{fi};
                break;
            end
        end

        if ~isempty(srcFig)
            % Clear previous content from the embedded panel
            delete(h.plotPnl.Children);
            % Reset filter / fit state for the new plot
            app.filterModeOn                = false;
            app.fitLines                    = [];
            app.drag                        = struct('active', false, 'ax', [], ...
                                                     'x0', NaN, 'y0', NaN, 'rectH', []);
            fig.WindowButtonMotionFcn       = '';
            fig.WindowButtonUpFcn           = '';
            h.filterModeBtn.Text            = 'Filter Mode: OFF';
            h.filterModeBtn.BackgroundColor = [0.4 0.4 0.4];

            % Copy all axes into the embedded panel
            allAx = findobj(srcFig, 'Type', 'axes');
            if ~isempty(allAx)
                newAxes = copyobj(allAx, h.plotPnl);
                % Reposition to fill panel
                for ai = 1:numel(newAxes)
                    set(newAxes(ai), 'Units', 'normalized', 'Position', [0.09 0.08 0.87 0.87]);
                end
            end

            % Close all generated figures
            for fi = 1:numel(figs)
                if ~isempty(figs{fi}) && ishandle(figs{fi})
                    close(figs{fi});
                end
            end
        end
        appendLog(h.log, 'Done.');
    catch ME
        appendLog(h.log, sprintf('Plot error: %s', ME.message));
    end
    guidata(fig, app);
end

%% =========================================================================
%  CALLBACK: Add to Queue
%% =========================================================================
function onAddToQueue(fig)
    app = guidata(fig);
    h   = app.handles;

    expr = strtrim(h.customExpr.Value);
    if ~isempty(expr)
        app.exprCount = app.exprCount + 1;
        y_label    = sprintf('expr_%d', app.exprCount);
        y_channels = {};
    else
        y_label    = h.yAxis(1).Value;
        y_channels = {h.yAxis(1).Value};
    end

    for yi = 2:4
        v = h.yAxis(yi).Value;
        if ~strcmpi(v, '(none)') && ~isempty(v)
            y_channels{end+1} = v; %#ok<AGROW>
        end
    end

    p = struct();
    p.name               = h.plotName.Value;
    p.type               = h.plotType.Value;
    p.math_fn            = h.mathFn.Value;
    p.x_axis             = h.xAxis.Value;
    p.y_channels         = y_channels;
    p.z_axis             = '';
    p.colour_mode        = h.colourMode.Value;
    p.differentiator     = h.differ.Value;
    p.use_secondary      = h.secondary.Value;
    p.plot_filter        = '';
    p.x_lim              = parseLim(h.xLim.Value);
    p.y_lim              = parseLim(h.yLim.Value);
    p.highlight_outliers = h.outliers.Value;
    p.outlier_method     = h.outlierMethod.Value;
    p.outlier_threshold  = h.outlierThresh.Value;
    p.outlier_scope      = 'manufacturer';
    p.align_channel      = h.alignCh.Value;
    p.align_window       = parseLim(h.alignWin.Value);
    p.align_method       = h.alignMethod.Value;
    p.align_max_offset   = h.alignMax.Value;
    p.fig_num            = NaN;
    p.fig_layout         = [];
    p.fig_pos            = [];
    p.pptx_title         = '';
    p.custom_expr        = expr;

    if isempty(app.plotQueue)
        app.plotQueue = p;
    else
        app.plotQueue(end+1) = p;
    end

    new_row = {p.name, p.type, p.x_axis, y_label, p.math_fn};
    d = h.queueTable.Data;
    if isempty(d)
        h.queueTable.Data = new_row;
    else
        h.queueTable.Data = [d; new_row];
    end

    appendLog(h.log, sprintf('Queued: "%s" (%s, x=%s, y=%s, fn=%s)', ...
        p.name, p.type, p.x_axis, y_label, p.math_fn));
    guidata(fig, app);
end

%% =========================================================================
%  CALLBACK: Delete selected queue row
%% =========================================================================
function onDeleteQueueRow(fig, queueTable)
    app = guidata(fig);
    sel = queueTable.Selection;
    if isempty(sel), return; end
    rows = unique(sel(:,1));
    app.plotQueue(rows) = [];
    d = queueTable.Data;
    d(rows, :) = [];
    queueTable.Data = d;
    guidata(fig, app);
    appendLog(app.handles.log, sprintf('Removed %d item(s) from queue.', numel(rows)));
end

%% =========================================================================
%  CALLBACK: Plot from queue
%% =========================================================================
function onPlotQueue(fig, queueTable, mode)
    app = guidata(fig);
    h   = app.handles;

    if isempty(app.SMP)
        appendLog(h.log, 'ERROR: Apply filters first to build the SMP dataset.');
        return;
    end
    if isempty(app.plotQueue)
        appendLog(h.log, 'Queue is empty -- add plots first.');
        return;
    end

    if strcmpi(mode, 'selected')
        sel = queueTable.Selection;
        if isempty(sel)
            appendLog(h.log, 'No rows selected in queue.');
            return;
        end
        rows  = unique(sel(:,1));
        plots = app.plotQueue(rows);
    else
        plots = app.plotQueue;
    end

    appendLog(h.log, sprintf('Plotting %d item(s)...', numel(plots)));
    drawnow;

    [SMP_plot, plots_out] = injectCustomExprs(app.SMP, plots, h.log);

    opts = struct('verbose', true);
    try
        smp_plot_from_config(SMP_plot, plots_out, app.cfg, [], opts);
        appendLog(h.log, 'Done.');
    catch ME
        appendLog(h.log, sprintf('Plot error: %s', ME.message));
    end
end

%% =========================================================================
%  CALLBACK: Browse Excel
%% =========================================================================
function onBrowseExcel(fig, excelPath) %#ok<INUSL>
    [f, d] = uigetfile({'*.xlsx;*.xls', 'Excel Files (*.xlsx, *.xls)'}, ...
        'Select plottingRequest file');
    if isequal(f, 0), return; end
    excelPath.Value = fullfile(d, f);
end

%% =========================================================================
%  CALLBACK: Load Excel presets
%% =========================================================================
function onLoadExcel(fig, excelPath)
    app = guidata(fig);
    h   = app.handles;
    fp  = strtrim(excelPath.Value);

    if ~isfile(fp)
        appendLog(h.log, 'ERROR: File not found.');
        return;
    end

    appendLog(h.log, sprintf('Loading Excel config: %s', fp));
    drawnow;

    try
        plots = smp_plot_config_load(fp);
        app.excelPlots = plots;
        guidata(fig, app);

        data = cell(numel(plots), 6);
        for i = 1:numel(plots)
            y1 = '';
            if ~isempty(plots(i).y_channels)
                y1 = plots(i).y_channels{1};
            end
            data(i, :) = {true, plots(i).name, plots(i).type, ...
                          plots(i).x_axis, y1, plots(i).math_fn};
        end
        h.excelTable.Data = data;
        appendLog(h.log, sprintf('  Loaded %d plot definition(s).', numel(plots)));

    catch ME
        appendLog(h.log, sprintf('ERROR (smp_plot_config_load): %s', ME.message));
    end
end

%% =========================================================================
%  CALLBACK: Plot from Excel table
%% =========================================================================
function onPlotExcel(fig, excelTable, mode)
    app = guidata(fig);
    h   = app.handles;

    if isempty(app.SMP)
        appendLog(h.log, 'ERROR: Apply filters first to build the SMP dataset.');
        return;
    end
    if isempty(app.excelPlots)
        appendLog(h.log, 'ERROR: Load an Excel config file first.');
        return;
    end

    if strcmpi(mode, 'selected')
        d    = excelTable.Data;
        mask = cellfun(@(x) isequal(x, true), d(:, 1));
        plots = app.excelPlots(mask);
    else
        plots = app.excelPlots;
    end

    if isempty(plots)
        appendLog(h.log, 'No plots selected (tick checkboxes in the Plot column).');
        return;
    end

    appendLog(h.log, sprintf('Plotting %d item(s)...', numel(plots)));
    drawnow;

    opts = struct('verbose', true);
    try
        smp_plot_from_config(app.SMP, plots, app.cfg, app.driver_map, opts);
        appendLog(h.log, 'Done.');
    catch ME
        appendLog(h.log, sprintf('Plot error: %s', ME.message));
    end
end

%% =========================================================================
%  HELPER: Inject custom expressions as synthetic stat channels
%% =========================================================================
function [SMP_out, plots_out] = injectCustomExprs(SMP_in, plots, logArea)
    SMP_out   = SMP_in;
    plots_out = plots;

    for pi = 1:numel(plots)
        expr = plots(pi).custom_expr;
        if isempty(expr), continue; end

        chan_name = sprintf('custom_expr_%d', pi);
        team_keys = fieldnames(SMP_out);

        for t = 1:numel(team_keys)
            tk   = team_keys{t};
            node = SMP_out.(tk);

            for rr = 1:numel(node.stats)
                st = node.stats{rr};
                if isempty(st) || ~isstruct(st), continue; end

                try
                    result = evalCustomExpr(expr, st, plots(pi).math_fn);

                    ref_field = fieldnames(st);
                    ref       = st.(ref_field{1});

                    s_new.lap_numbers   = ref.lap_numbers;
                    s_new.lap_times     = ref.lap_times;
                    s_new.lap_types     = ref.lap_types;
                    s_new.mean          = result;
                    s_new.max           = result;
                    s_new.min           = result;
                    s_new.median        = result;
                    s_new.std           = zeros(size(result));
                    s_new.units         = 'expr';
                    s_new.raw_name      = chan_name;
                    s_new.channel_field = chan_name;

                    SMP_out.(tk).stats{rr}.(chan_name) = s_new;

                catch ME
                    appendLog(logArea, sprintf('Expr eval error (run %d): %s', rr, ME.message));
                end
            end
        end

        plots_out(pi).y_channels = {chan_name};
    end
end

%% =========================================================================
%  HELPER: Evaluate expression string against a stats struct
%% =========================================================================
function result = evalCustomExpr(expr, stats_struct, math_fn)
    fields = fieldnames(stats_struct);

    fn = lower(strtrim(math_fn));
    fn = strrep(fn, ' ', '_');
    if ~isfield(stats_struct.(fields{1}), fn)
        fn = 'mean';
    end

    e = expr;
    [~, idx] = sort(cellfun(@numel, fields), 'descend');
    for fi = idx(:)'
        ch = fields{fi};
        if ~isfield(stats_struct.(ch), fn), continue; end
        vec = stats_struct.(ch).(fn);
        e = strrep(e, ch, ['[', num2str(vec(:)'), ']']);
    end

    result = eval(e); %#ok<EVLEQ>
end

%% =========================================================================
%  HELPER: Parse '[lo hi]' text to 1x2 double or []
%% =========================================================================
function lim = parseLim(str)
    str = strtrim(str);
    if isempty(str)
        lim = [];
        return;
    end
    try
        lim = eval(str); %#ok<EVLEQ>
        if numel(lim) ~= 2, lim = []; end
    catch
        lim = [];
    end
end

%% =========================================================================
%  HELPER: Append a timestamped line to the log text area
%% =========================================================================
function appendLog(logArea, msg)
    ts       = datestr(now, 'HH:MM:SS'); %#ok<TNOW1,DATST>
    existing = logArea.Value;
    if ischar(existing), existing = {existing}; end
    logArea.Value = [existing; {sprintf('[%s] %s', ts, msg)}];
end

%% =========================================================================
%  HELPER: Convert logical to 'on'/'off' string
%% =========================================================================
function s = onOff(flag)
    if flag, s = 'on'; else, s = 'off'; end
end

%% =========================================================================
%  HELPER: Return all plottable data objects (line + scatter), no overlays
%% =========================================================================
function objs = getDataObjects(ax)
    SKIP = {'exclusion_overlay', 'fit_line'};
    all_line = findobj(ax, 'Type', 'line');
    all_scat = findobj(ax, 'Type', 'scatter');
    keep = @(arr) arr(~arrayfun(@(o) ismember(o.Tag, SKIP), arr));
    objs = [keep(all_line); keep(all_scat)];
end

%% =========================================================================
%  HELPER: Ensure UserData has orig_x/orig_y/excluded for an object
%% =========================================================================
function ud = ensureUserData(obj)
    ud = obj.UserData;
    if ~isstruct(ud), ud = struct(); end
    if ~isfield(ud, 'orig_x') || isempty(ud.orig_x)
        ud.orig_x   = double(obj.XData(:)');
        ud.orig_y   = double(obj.YData(:)');
        ud.excluded = false(1, numel(ud.orig_x));
        % For scatter objects, also save per-point colour and size
        if isa(obj, 'matlab.graphics.chart.primitive.Scatter')
            ud.orig_c = obj.CData;
            ud.orig_s = obj.SizeData;
        end
    end
    if numel(ud.excluded) ~= numel(ud.orig_x)
        ud.excluded = false(1, numel(ud.orig_x));
    end
end

%% =========================================================================
%  HELPER: Get excluded boolean mask (relative to original full dataset)
%% =========================================================================
function mask = getExcluded(obj)
    ud = obj.UserData;
    if isstruct(ud) && isfield(ud, 'excluded') && isfield(ud, 'orig_x')
        mask = ud.excluded(:)';
        if numel(mask) ~= numel(ud.orig_x)
            mask = false(1, numel(ud.orig_x));
        end
    else
        mask = false(1, numel(obj.XData));
    end
end

%% =========================================================================
%  HELPER: Refresh display -- hide excluded pts & draw red-X overlay
%% =========================================================================
function refreshExclusionDisplay(ax)
    delete(findobj(ax, 'Tag', 'exclusion_overlay'));
    objs   = getDataObjects(ax);
    excl_x = [];
    excl_y = [];

    for oi = 1:numel(objs)
        obj = objs(oi);
        ud  = obj.UserData;
        if ~isstruct(ud) || ~isfield(ud, 'orig_x'), continue; end

        keep = ~ud.excluded;
        excl_x = [excl_x, ud.orig_x(ud.excluded)]; %#ok<AGROW>
        excl_y = [excl_y, ud.orig_y(ud.excluded)]; %#ok<AGROW>

        % Update displayed data to non-excluded only
        obj.XData = ud.orig_x(keep);
        obj.YData = ud.orig_y(keep);

        % For scatter: keep per-point colour / size arrays in sync
        if isa(obj, 'matlab.graphics.chart.primitive.Scatter') && isfield(ud, 'orig_c')
            c = ud.orig_c;
            if size(c, 1) == numel(ud.orig_x)
                obj.CData = c(keep, :);
            elseif numel(c) == numel(ud.orig_x)
                obj.CData = c(keep);
            end
        end
        if isa(obj, 'matlab.graphics.chart.primitive.Scatter') && isfield(ud, 'orig_s')
            s = ud.orig_s;
            if numel(s) == numel(ud.orig_x)
                obj.SizeData = s(keep);
            end
        end
    end

    % Draw red X at excluded positions
    if ~isempty(excl_x)
        hold(ax, 'on');
        line(ax, excl_x, excl_y, ...
            'LineStyle',     'none', ...
            'Marker',        'x', ...
            'MarkerSize',    12, ...
            'LineWidth',     2.0, ...
            'Color',         [0.85 0.1 0.1], ...
            'Tag',           'exclusion_overlay', ...
            'HitTest',       'off', ...
            'PickableParts', 'none');
    end
end

%% =========================================================================
%  CALLBACK: Toggle filter mode
%% =========================================================================
function onToggleFilterMode(fig)
    app = guidata(fig);
    h   = app.handles;

    ax = findobj(h.plotPnl, 'Type', 'axes');
    if isempty(ax)
        appendLog(h.log, 'No axes in plot panel -- plot something first.');
        return;
    end

    app.filterModeOn = ~app.filterModeOn;

    if app.filterModeOn
        h.filterModeBtn.Text            = 'Filter Mode: ON';
        h.filterModeBtn.BackgroundColor = [0.82 0.25 0.08];
        appendLog(h.log, 'Filter mode ON -- click a point to exclude/include it, or drag a box to exclude a region.');
        for ai = 1:numel(ax)
            ax(ai).ButtonDownFcn = @(src,~) onAxesButtonDown(fig, src);
            ax(ai).HitTest       = 'on';
            ax(ai).PickableParts = 'all';
            objs = getDataObjects(ax(ai));
            for oi = 1:numel(objs)
                objs(oi).HitTest       = 'on';
                objs(oi).PickableParts = 'all';
                objs(oi).ButtonDownFcn = @(~,~) onAxesButtonDown(fig, ax(ai));
            end
        end
    else
        h.filterModeBtn.Text            = 'Filter Mode: OFF';
        h.filterModeBtn.BackgroundColor = [0.4 0.4 0.4];
        appendLog(h.log, 'Filter mode OFF.');
        fig.WindowButtonMotionFcn = '';
        fig.WindowButtonUpFcn     = '';
        for ai = 1:numel(ax)
            ax(ai).ButtonDownFcn = '';
            objs = getDataObjects(ax(ai));
            for oi = 1:numel(objs)
                objs(oi).ButtonDownFcn = '';
            end
        end
    end

    guidata(fig, app);
end

%% =========================================================================
%  CALLBACK: Axes button-down -- initiates either click or drag
%% =========================================================================
function onAxesButtonDown(fig, ax)
    app = guidata(fig);
    if ~app.filterModeOn, return; end

    cp = ax.CurrentPoint;
    app.drag.active = true;
    app.drag.ax     = ax;
    app.drag.x0     = cp(1,1);
    app.drag.y0     = cp(1,2);
    app.drag.rectH  = [];
    guidata(fig, app);

    fig.WindowButtonMotionFcn = @(~,~) onFigureMotion(fig);
    fig.WindowButtonUpFcn     = @(~,~) onFigureButtonUp(fig);
end

%% =========================================================================
%  CALLBACK: Figure mouse motion -- update drag rectangle
%% =========================================================================
function onFigureMotion(fig)
    app = guidata(fig);
    if ~app.drag.active, return; end

    ax = app.drag.ax;
    cp = ax.CurrentPoint;
    cx = cp(1,1);
    cy = cp(1,2);
    x0 = app.drag.x0;
    y0 = app.drag.y0;

    xl = ax.XLim;  xR = xl(2) - xl(1);
    yl = ax.YLim;  yR = yl(2) - yl(1);
    if xR == 0 || yR == 0, return; end

    % Only draw box once drag exceeds 0.5% of axis range
    if abs((cx-x0)/xR) < 0.005 && abs((cy-y0)/yR) < 0.005, return; end

    xlo = min(x0, cx);  xhi = max(x0, cx);
    ylo = min(y0, cy);  yhi = max(y0, cy);
    xs = [xlo xhi xhi xlo xlo];
    ys = [ylo ylo yhi yhi ylo];

    if isempty(app.drag.rectH) || ~ishandle(app.drag.rectH)
        hold(ax, 'on');
        app.drag.rectH = patch(ax, xs, ys, [0.2 0.5 0.9], ...
            'FaceAlpha',     0.15, ...
            'EdgeColor',     [0.1 0.4 0.85], ...
            'LineStyle',     '--', ...
            'LineWidth',     1.5, ...
            'Tag',           'drag_rect', ...
            'HitTest',       'off', ...
            'PickableParts', 'none');
    else
        app.drag.rectH.XData = xs;
        app.drag.rectH.YData = ys;
    end

    guidata(fig, app);
end

%% =========================================================================
%  CALLBACK: Figure button-up -- finalise click or box exclusion
%% =========================================================================
function onFigureButtonUp(fig)
    app = guidata(fig);
    if ~app.drag.active
        fig.WindowButtonMotionFcn = '';
        fig.WindowButtonUpFcn     = '';
        return;
    end

    fig.WindowButtonMotionFcn = '';
    fig.WindowButtonUpFcn     = '';
    app.drag.active = false;

    ax = app.drag.ax;
    x0 = app.drag.x0;
    y0 = app.drag.y0;
    wasDrag = ~isempty(app.drag.rectH) && ishandle(app.drag.rectH);

    % Remove the rubber-band rectangle
    delete(findobj(ax, 'Tag', 'drag_rect'));
    app.drag.rectH = [];
    guidata(fig, app);

    objs = getDataObjects(ax);

    if wasDrag
        %% ---- Box exclusion ----
        cp  = ax.CurrentPoint;
        cx  = cp(1,1);
        cy  = cp(1,2);
        xlo = min(x0, cx);  xhi = max(x0, cx);
        ylo = min(y0, cy);  yhi = max(y0, cy);

        n_toggled = 0;
        for oi = 1:numel(objs)
            ud = ensureUserData(objs(oi));
            xd = ud.orig_x;
            yd = ud.orig_y;
            in_box = xd >= xlo & xd <= xhi & yd >= ylo & yd <= yhi;
            if ~any(in_box), continue; end
            % Exclude any un-excluded point in box; re-include if already excluded
            % (holding shift re-includes; plain drag always excludes)
            ud.excluded(in_box) = true;
            n_toggled = n_toggled + sum(in_box);
            objs(oi).UserData = ud;
        end

        refreshExclusionDisplay(ax);
        n_excl = sum(arrayfun(@(o) nnz(getExcluded(o)), objs));
        appendLog(app.handles.log, sprintf('  Box excluded %d point(s); %d total excluded.', ...
            n_toggled, n_excl));
    else
        %% ---- Single-point click ----
        xl = ax.XLim;  xR = xl(2) - xl(1);
        yl = ax.YLim;  yR = yl(2) - yl(1);
        if xR == 0 || yR == 0
            guidata(fig, app);
            return;
        end

        best_dist = Inf;
        best_obj  = [];
        best_idx  = NaN;

        for oi = 1:numel(objs)
            ud = ensureUserData(objs(oi));
            xd = ud.orig_x;
            yd = ud.orig_y;
            if isempty(xd) || isempty(yd), continue; end
            dx    = (xd - x0) / xR;
            dy    = (yd - y0) / yR;
            dists = sqrt(dx.^2 + dy.^2);
            [d, idx] = min(dists);
            if d < best_dist
                best_dist = d;
                best_obj  = objs(oi);
                best_idx  = idx;
            end
        end

        THRESHOLD = 0.05;
        if ~isempty(best_obj) && best_dist <= THRESHOLD
            ud = ensureUserData(best_obj);
            ud.excluded(best_idx) = ~ud.excluded(best_idx);
            best_obj.UserData = ud;
            refreshExclusionDisplay(ax);
            n_excl = sum(arrayfun(@(o) nnz(getExcluded(o)), objs));
            appendLog(app.handles.log, sprintf('  %d point(s) currently excluded.', n_excl));
        end
    end

    guidata(fig, app);
end

%% =========================================================================
%  CALLBACK: Clear all excluded points
%% =========================================================================
function onClearExcluded(fig)
    app = guidata(fig);
    h   = app.handles;

    ax_list = findobj(h.plotPnl, 'Type', 'axes');
    for ai = 1:numel(ax_list)
        objs = getDataObjects(ax_list(ai));
        for oi = 1:numel(objs)
            ud = objs(oi).UserData;
            if isstruct(ud) && isfield(ud, 'orig_x')
                % Restore original data
                objs(oi).XData = ud.orig_x;
                objs(oi).YData = ud.orig_y;
                if isa(objs(oi), 'matlab.graphics.chart.primitive.Scatter')
                    if isfield(ud, 'orig_c'), objs(oi).CData    = ud.orig_c; end
                    if isfield(ud, 'orig_s'), objs(oi).SizeData = ud.orig_s; end
                end
                ud.excluded(:) = false;
                objs(oi).UserData = ud;
            end
        end
        delete(findobj(ax_list(ai), 'Tag', 'exclusion_overlay'));
    end
    appendLog(h.log, 'Exclusions cleared.');
end

%% =========================================================================
%  CALLBACK: Apply polynomial fit (degree 1 = linear, 3 = cubic)
%%   Uses only non-excluded points AND only points within the axis limits.
%% =========================================================================
function onApplyFit(fig, degree)
    app = guidata(fig);
    h   = app.handles;

    ax_list = findobj(h.plotPnl, 'Type', 'axes');
    if isempty(ax_list)
        appendLog(h.log, 'No axes in plot panel -- plot something first.');
        return;
    end

    if degree == 1
        fit_label = 'Linear';
        fc        = [0.05 0.75 0.95];
    else
        fit_label = 'Cubic';
        fc        = [0.95 0.55 0.05];
    end

    for ai = 1:numel(ax_list)
        ax   = ax_list(ai);
        xl   = ax.XLim;
        yl   = ax.YLim;
        objs = getDataObjects(ax);

        if isempty(objs), continue; end

        all_x = [];
        all_y = [];

        for oi = 1:numel(objs)
            obj = objs(oi);
            ud  = obj.UserData;
            if isstruct(ud) && isfield(ud, 'orig_x')
                xd = ud.orig_x;
                yd = ud.orig_y;
                ex = ud.excluded;
                if numel(ex) ~= numel(xd), ex = false(size(xd)); end
            else
                xd = double(obj.XData(:)');
                yd = double(obj.YData(:)');
                ex = false(size(xd));
            end
            % Remove manually excluded points
            xd = xd(~ex);
            yd = yd(~ex);
            % Keep only points within current axis limits
            in_view = xd >= xl(1) & xd <= xl(2) & yd >= yl(1) & yd <= yl(2);
            all_x = [all_x, xd(in_view)]; %#ok<AGROW>
            all_y = [all_y, yd(in_view)]; %#ok<AGROW>
        end

        valid = isfinite(all_x) & isfinite(all_y);
        all_x = all_x(valid);
        all_y = all_y(valid);

        if numel(all_x) < degree + 1
            appendLog(h.log, sprintf('  Not enough data for %s fit (need >= %d pts, have %d).', ...
                fit_label, degree+1, numel(all_x)));
            continue;
        end

        p     = polyfit(all_x, all_y, degree);
        x_fit = linspace(min(all_x), max(all_x), 300);
        y_fit = polyval(p, x_fit);

        hold(ax, 'on');
        fit_h = line(ax, x_fit, y_fit, ...
            'LineStyle',     '-', ...
            'LineWidth',     2, ...
            'Color',         fc, ...
            'Tag',           'fit_line', ...
            'HitTest',       'off', ...
            'PickableParts', 'none', ...
            'DisplayName',   sprintf('%s fit', fit_label));

        if degree == 1
            appendLog(h.log, sprintf('  %s fit (%d pts): y = %.6g*x + %.6g', ...
                fit_label, numel(all_x), p(1), p(2)));
        else
            terms = '';
            for k = 1:numel(p)
                pw = numel(p) - k;
                if pw == 0
                    terms = [terms, sprintf('%+.4g', p(k))]; %#ok<AGROW>
                elseif pw == 1
                    terms = [terms, sprintf('%+.4g*x', p(k))]; %#ok<AGROW>
                else
                    terms = [terms, sprintf('%+.4g*x^%d', p(k), pw)]; %#ok<AGROW>
                end
            end
            appendLog(h.log, sprintf('  %s fit (%d pts): y = %s', ...
                fit_label, numel(all_x), strtrim(terms)));
        end

        if isempty(app.fitLines)
            app.fitLines = fit_h;
        else
            app.fitLines(end+1) = fit_h;
        end
    end

    guidata(fig, app);
end

%% =========================================================================
%  CALLBACK: Clear all fit lines
%% =========================================================================
function onClearFits(fig)
    app = guidata(fig);
    h   = app.handles;

    ax_list = findobj(h.plotPnl, 'Type', 'axes');
    for ai = 1:numel(ax_list)
        delete(findobj(ax_list(ai), 'Tag', 'fit_line'));
    end
    app.fitLines = [];
    guidata(fig, app);
    appendLog(h.log, 'Fits cleared.');
end
