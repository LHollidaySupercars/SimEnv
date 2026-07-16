function SimEnv_Launcher()
%% SIMENV_LAUNCHER  Central launcher GUI for SimEnv execution scripts.
%
%  Provides a tabbed interface to configure and run:
%    Tab 1 — MoTeC Pipeline      (smp_pipeline.m)
%    Tab 2 — Compile Event       (smp_compile_event.m)
%    Tab 3 — Main Report         (execute_main_report.m / execute_reduced_script.m)
%    Tab 4 — Fuel Analysis       (execute_quali_fuel_analysis.m / LiftAndCoast.m)
%    Tab 5 — DB Upload           (smp_push_to_sql.m)
%    Tab 6 — Write VCH           (execute_write_vch.m)
%
%  Usage:  SimEnv_Launcher()
%
%  Requires MATLAB R2020a or later.

    %% ---- Paths ----
    thisDir = fileparts(mfilename('fullpath'));
    addpath(thisDir);
    addpath(fullfile(thisDir, 'helper'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'Motec_MP'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'alias'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'channels'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'channelAdd'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'plot'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'motecFiltering'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'filterRequest'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'plottingRequest'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'parseEventData'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'parseEventData', 'executionScripts'));
    addpath(fullfile(thisDir, 'dataAcquisition', 'serverInteraction'));
    addpath(fullfile(thisDir, 'trackDB'));

    %% ---- Default shared paths ----
    DEF_CHANNELS_FILE    = fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'channels', 'channels.xlsx');
    DEF_EVENT_ALIAS_FILE = fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'alias', 'eventAlias.xlsx');
    DEF_DRIVER_ALIAS_FILE= fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'alias', 'driverAlias.xlsx');
    DEF_SEASON_FILE      = fullfile(thisDir, 'trackDB', 'seasonOverview.xlsx');
    DEF_PPTX_TEMPLATE    = fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'plot', 'templates', 'SuperCars_PPT.pptx');
    DEF_OUTPUT_DIR       = fullfile(thisDir, 'dataAcquisition', 'Motec_MP', 'plot', 'output');

    %% ---- Figure ----
    fig = uifigure( ...
        'Name',     'SimEnv Launcher', ...
        'Position', [60 60 920 760]);

    %% ---- App state ----
    app         = struct();
    app.thisDir = thisDir;
    guidata(fig, app);

    %% ====================================================================
    %  ROOT GRID  —  3 rows: common config | tabs | status bar
    %% ====================================================================
    root = uigridlayout(fig, [3 1]);
    root.RowHeight    = {160, '1x', 34};
    root.Padding      = [8 8 8 8];
    root.RowSpacing   = 6;

    %% ====================================================================
    %  ROW 1 — COMMON CONFIG PANEL
    %% ====================================================================
    cfgPnl = uipanel(root, 'Title', 'Common Config', 'FontWeight', 'bold');
    cfgPnl.Layout.Row = 1;

    cg = uigridlayout(cfgPnl, [4 6]);
    cg.ColumnWidth  = {110, '2x', 80, 110, '1x', 80};
    cg.RowHeight    = {22, 22, 22, 22};
    cg.Padding      = [6 4 6 4];
    cg.RowSpacing   = 4;
    cg.ColumnSpacing= 4;

    % Row 1 — Data root dir
    makeLabel(cg, 'Data Root Dir:', [1 1]);
    hRootDir = uieditfield(cg, 'text', 'Value', '', 'Tooltip', 'Top-level folder containing _TeamData');
    hRootDir.Layout.Row = 1; hRootDir.Layout.Column = 2;
    hBrowseRoot = uibutton(cg, 'Text', 'Browse...', 'ButtonPushedFcn', @(~,~) onBrowseDir(fig, hRootDir));
    hBrowseRoot.Layout.Row = 1; hBrowseRoot.Layout.Column = 3;

    makeLabel(cg, 'Output Dir:', [1 4]);
    hOutputDir = uieditfield(cg, 'text', 'Value', DEF_OUTPUT_DIR);
    hOutputDir.Layout.Row = 1; hOutputDir.Layout.Column = 5;
    hBrowseOut = uibutton(cg, 'Text', 'Browse...', 'ButtonPushedFcn', @(~,~) onBrowseDir(fig, hOutputDir));
    hBrowseOut.Layout.Row = 1; hBrowseOut.Layout.Column = 6;

    % Row 2 — Event / Track / Year
    makeLabel(cg, 'Event:', [2 1]);
    hEvent = uieditfield(cg, 'text', 'Value', 'E05', 'Tooltip', 'Event code, e.g. E05');
    hEvent.Layout.Row = 2; hEvent.Layout.Column = 2;

    makeLabel(cg, 'Track:', [2 4]);
    hTrack = uieditfield(cg, 'text', 'Value', 'TAS', 'Tooltip', 'Track code, e.g. TAS');
    hTrack.Layout.Row = 2; hTrack.Layout.Column = 5;

    makeLabel(cg, 'Year:', [3 1]);
    hYear = uieditfield(cg, 'numeric', 'Value', 2026, 'Limits', [2000 2100], 'RoundFractionalValues', 'on');
    hYear.Layout.Row = 3; hYear.Layout.Column = 2;

    makeLabel(cg, 'PPTX Template:', [3 4]);
    hPptx = uieditfield(cg, 'text', 'Value', DEF_PPTX_TEMPLATE);
    hPptx.Layout.Row = 3; hPptx.Layout.Column = 5;
    hBrowsePptx = uibutton(cg, 'Text', 'Browse...', 'ButtonPushedFcn', @(~,~) onBrowseFile(fig, hPptx, '*.pptx'));
    hBrowsePptx.Layout.Row = 3; hBrowsePptx.Layout.Column = 6;

    % Row 4 — Shared files
    makeLabel(cg, 'Channels File:', [4 1]);
    hChannelsFile = uieditfield(cg, 'text', 'Value', DEF_CHANNELS_FILE);
    hChannelsFile.Layout.Row = 4; hChannelsFile.Layout.Column = 2;

    makeLabel(cg, 'Season File:', [4 4]);
    hSeasonFile = uieditfield(cg, 'text', 'Value', DEF_SEASON_FILE);
    hSeasonFile.Layout.Row = 4; hSeasonFile.Layout.Column = 5;

    %% ====================================================================
    %  ROW 2 — TABS
    %% ====================================================================
    tg = uitabgroup(root);
    tg.Layout.Row = 2;

    %% ----------------------------------------------------------------
    %  TAB 1 — MoTeC Pipeline
    %% ----------------------------------------------------------------
    t1 = uitab(tg, 'Title', 'MoTeC Pipeline');
    [ui1, advPnl1] = buildPipelineTab(t1);

    %% ----------------------------------------------------------------
    %  TAB 2 — Compile Event
    %% ----------------------------------------------------------------
    t2 = uitab(tg, 'Title', 'Compile Event');
    [ui2, advPnl2] = buildCompileTab(t2);

    %% ----------------------------------------------------------------
    %  TAB 3 — Main Report
    %% ----------------------------------------------------------------
    t3 = uitab(tg, 'Title', 'Main Report');
    [ui3, advPnl3] = buildReportTab(t3, DEF_PPTX_TEMPLATE);

    %% ----------------------------------------------------------------
    %  TAB 4 — Fuel Analysis
    %% ----------------------------------------------------------------
    t4 = uitab(tg, 'Title', 'Fuel Analysis');
    [ui4_quali, ui4_lac, advPnl4_quali, advPnl4_lac, fuelSubTg] = buildFuelTab(t4);

    %% ----------------------------------------------------------------
    %  TAB 5 — DB Upload
    %% ----------------------------------------------------------------
    t5 = uitab(tg, 'Title', 'DB Upload');
    ui5 = buildDbUploadTab(t5);

    %% ----------------------------------------------------------------
    %  TAB 6 — Write VCH
    %% ----------------------------------------------------------------
    t6 = uitab(tg, 'Title', 'Write VCH');
    ui6 = buildWriteVchTab(t6);

    %% ====================================================================
    %  ROW 3 — STATUS BAR
    %% ====================================================================
    statusGrid = uigridlayout(root, [1 3]);
    statusGrid.Layout.Row  = 3;
    statusGrid.ColumnWidth = {60, '1x', 120};
    statusGrid.Padding     = [0 0 0 0];

    hStatusLbl = uilabel(statusGrid, 'Text', 'Status:', 'FontWeight', 'bold');
    hStatusLbl.Layout.Row = 1; hStatusLbl.Layout.Column = 1;
    hStatus = uilabel(statusGrid, 'Text', '● Idle', 'FontColor', [0.4 0.4 0.4]);
    hStatus.Layout.Row = 1; hStatus.Layout.Column = 2;

    hRunBtn = uibutton(statusGrid, 'Text', '▶  Run', ...
        'FontWeight', 'bold', ...
        'BackgroundColor', [0.18 0.44 0.73], ...
        'FontColor', [1 1 1]);
    hRunBtn.Layout.Row = 1; hRunBtn.Layout.Column = 3;
    hRunBtn.ButtonPushedFcn = @(~,~) onRun(fig, tg, hRunBtn, hStatus, ...
        hRootDir, hEvent, hTrack, hYear, hChannelsFile, hSeasonFile, hOutputDir, hPptx, ...
        ui1, advPnl1, ui2, advPnl2, ui3, advPnl3, ui4_quali, ui4_lac, ...
        advPnl4_quali, advPnl4_lac, fuelSubTg, ui5, ui6);

end % SimEnv_Launcher


%% ========================================================================
%  TAB BUILDERS
%% ========================================================================

function [ui, advPnl] = buildPipelineTab(parent)
    ui = struct();
    g = uigridlayout(parent, [4 1]);
    g.RowHeight  = {50, 'fit', 34, 'fit'};
    g.Padding    = [8 8 8 8];
    g.RowSpacing = 6;

    % Blurb
    blurb = uitextarea(g, 'Value', ...
        'Master pipeline — aligns TeamData, ECU, and L180 data for one event across 5 phases. Run phases in order or selectively. Set SESSION and DRIVERS then choose which phases to execute.', ...
        'Editable', 'off', 'FontColor', [0.3 0.3 0.3], 'BackgroundColor', [0.96 0.96 0.96]); %#ok<NASGU>
    blurb.Layout.Row = 1;

    % Basic panel
    basicPnl = uipanel(g, 'Title', 'Parameters', 'BorderType', 'line');
    basicPnl.Layout.Row = 2;
    bg = uigridlayout(basicPnl, [9 6]);
    bg.ColumnWidth  = {150, '1x', 70, 150, '1x', 70};
    bg.RowHeight    = repmat({22}, 1, 9);
    bg.Padding      = [6 6 6 6];
    bg.RowSpacing   = 4;
    bg.ColumnSpacing= 4;

    makeLabel(bg, 'SESSION:', [1 1]);
    ui.session = uieditfield(bg, 'text', 'Value', 'Q14', 'Tooltip', 'Session label, e.g. Q14');
    ui.session.Layout.Row = 1; ui.session.Layout.Column = 2;

    makeLabel(bg, 'DRIVERS (comma-sep):', [2 1]);
    ui.drivers = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Car numbers or TLAs. Leave blank for all drivers.');
    ui.drivers.Layout.Row = 2; ui.drivers.Layout.Column = [2 6];

    makeLabel(bg, 'Root Folder:', [3 1]);
    ui.rootFolder = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Event root folder, e.g. E:\2026\E05_TAS');
    ui.rootFolder.Layout.Row = 3; ui.rootFolder.Layout.Column = 2;
    makeBtn(bg, 'Browse...', 3, 3, @(~,~) onBrowseDir([], ui.rootFolder));

    makeLabel(bg, 'HOL Dir:', [4 1]);
    ui.holDir = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'HOL output folder, e.g. E:\2026\E05_TAS\HOL');
    ui.holDir.Layout.Row = 4; ui.holDir.Layout.Column = 2;
    makeBtn(bg, 'Browse...', 4, 3, @(~,~) onBrowseDir([], ui.holDir));

    makeLabel(bg, 'HOL Venue:', [5 1]);
    ui.holVenue = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Full venue name, e.g. Symmons Plains Raceway');
    ui.holVenue.Layout.Row = 5; ui.holVenue.Layout.Column = 2;

    makeLabel(bg, 'HOL Event:', [5 4]);
    ui.holEvent = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'HOL event code, e.g. E05TAS');
    ui.holEvent.Layout.Row = 5; ui.holEvent.Layout.Column = 5;

    makeLabel(bg, 'Overwrite:', [6 1]);
    ui.overwrite = uicheckbox(bg, 'Text', '', 'Value', true, 'Tooltip', 'Re-process existing output files');
    ui.overwrite.Layout.Row = 6; ui.overwrite.Layout.Column = 2;

    % Phase toggles
    phaseLabel = uilabel(bg, 'Text', 'Phases:', 'FontWeight', 'bold');
    phaseLabel.Layout.Row = 7; phaseLabel.Layout.Column = 1;
    phaseGrid = uigridlayout(bg, [1 5]);
    phaseGrid.Layout.Row = 7; phaseGrid.Layout.Column = [2 6];
    phaseGrid.ColumnWidth = {'1x','1x','1x','1x','1x'};
    phaseGrid.Padding = [0 0 0 0];
    ui.phaseTeamData = uicheckbox(phaseGrid, 'Text', 'TeamData Concat', 'Value', true);
    ui.phaseEcu      = uicheckbox(phaseGrid, 'Text', 'ECU Concat',       'Value', true);
    ui.phaseSplit    = uicheckbox(phaseGrid, 'Text', 'Split',             'Value', true);
    ui.phasePair     = uicheckbox(phaseGrid, 'Text', 'Pair',              'Value', true);
    ui.phaseMerge    = uicheckbox(phaseGrid, 'Text', 'Merge',             'Value', false);

    % ECU subdirs (partial advanced fields in basic for convenience)
    makeLabel(bg, 'ECU Input Dir:', [8 1]);
    ui.ecuInputDir = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Folder containing ECU files');
    ui.ecuInputDir.Layout.Row = 8; ui.ecuInputDir.Layout.Column = 2;
    makeBtn(bg, 'Browse...', 8, 3, @(~,~) onBrowseDir([], ui.ecuInputDir));

    makeLabel(bg, 'ECU Concat Dir:', [8 4]);
    ui.ecuConcatDir = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Output folder for concatenated ECU files');
    ui.ecuConcatDir.Layout.Row = 8; ui.ecuConcatDir.Layout.Column = 5;
    makeBtn(bg, 'Browse...', 8, 6, @(~,~) onBrowseDir([], ui.ecuConcatDir));

    makeLabel(bg, 'L180 Input Dir:', [9 1]);
    ui.l180InputDir = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Folder containing L180 files. Leave blank to skip L180.');
    ui.l180InputDir.Layout.Row = 9; ui.l180InputDir.Layout.Column = 2;
    makeBtn(bg, 'Browse...', 9, 3, @(~,~) onBrowseDir([], ui.l180InputDir));

    % Advanced toggle button
    advBtn = uibutton(g, 'Text', '▼  Advanced', 'HorizontalAlignment', 'left');
    advBtn.Layout.Row = 3;

    % Advanced panel
    advPnl = uipanel(g, 'Title', 'Advanced', 'BorderType', 'line', 'Visible', 'off');
    advPnl.Layout.Row = 4;
    ag = uigridlayout(advPnl, [11 6]);
    ag.ColumnWidth  = {160, '1x', 70, 160, '1x', 70};
    ag.RowHeight    = repmat({22}, 1, 11);
    ag.Padding      = [6 6 6 6];
    ag.RowSpacing   = 4;
    ag.ColumnSpacing= 4;

    makeLabel(ag, 'Event Alias File:', [1 1]);
    ui.eventAliasFile = uieditfield(ag, 'text', 'Value', '');
    ui.eventAliasFile.Layout.Row = 1; ui.eventAliasFile.Layout.Column = 2;
    makeBtn(ag, 'Browse...', 1, 3, @(~,~) onBrowseFile([], ui.eventAliasFile, '*.xlsx'));

    makeLabel(ag, 'Driver Alias File:', [1 4]);
    ui.driverAliasFile = uieditfield(ag, 'text', 'Value', '');
    ui.driverAliasFile.Layout.Row = 1; ui.driverAliasFile.Layout.Column = 5;
    makeBtn(ag, 'Browse...', 1, 6, @(~,~) onBrowseFile([], ui.driverAliasFile, '*.xlsx'));

    makeLabel(ag, 'Session Labels (csv):', [2 1]);
    ui.sessionLabels = uieditfield(ag, 'text', 'Value', 'Q14,Q15', 'Tooltip', 'Comma-separated session labels');
    ui.sessionLabels.Layout.Row = 2; ui.sessionLabels.Layout.Column = [2 3];

    makeLabel(ag, 'Warmup Beacon Chs (csv):', [2 4]);
    ui.warmupBeaconChs = uieditfield(ag, 'text', 'Value', 'Lap Beacon Number,Lap_Beacon_Number,Lap_Number,Lap Number');
    ui.warmupBeaconChs.Layout.Row = 2; ui.warmupBeaconChs.Layout.Column = [5 6];

    makeLabel(ag, 'Ridealong Cars (csv):', [3 1]);
    ui.ridealongCars = uieditfield(ag, 'text', 'Value', '38,99,9,1,96,26,19', 'Tooltip', 'Car numbers to exclude as ridealong');
    ui.ridealongCars.Layout.Row = 3; ui.ridealongCars.Layout.Column = [2 3];

    makeLabel(ag, 'ECU Format (M1):', [3 4]);
    ui.ecuFormat = uicheckbox(ag, 'Text', '', 'Value', true, 'Tooltip', 'true = M1 ECU logger (float32 type-4)');
    ui.ecuFormat.Layout.Row = 3; ui.ecuFormat.Layout.Column = 5;

    makeLabel(ag, 'Max Overlap (s):', [4 1]);
    ui.maxOverlapS = uieditfield(ag, 'numeric', 'Value', -30, 'Tooltip', 'Allow up to this overlap between ECU files');
    ui.maxOverlapS.Layout.Row = 4; ui.maxOverlapS.Layout.Column = 2;

    makeLabel(ag, 'Min Gap (s):', [4 4]);
    ui.minGapS = uieditfield(ag, 'numeric', 'Value', 1000, 'Tooltip', 'Forward ERT jump to count as session boundary');
    ui.minGapS.Layout.Row = 4; ui.minGapS.Layout.Column = 5;

    makeLabel(ag, 'Min Segment (s):', [5 1]);
    ui.minSegS = uieditfield(ag, 'numeric', 'Value', 650, 'Tooltip', 'Minimum segment duration');
    ui.minSegS.Layout.Row = 5; ui.minSegS.Layout.Column = 2;

    makeLabel(ag, 'Split on Reset:', [5 4]);
    ui.splitOnReset = uicheckbox(ag, 'Text', '', 'Value', true);
    ui.splitOnReset.Layout.Row = 5; ui.splitOnReset.Layout.Column = 5;

    makeLabel(ag, 'Unique Fingerprint:', [6 1]);
    ui.uniqueFp = uicheckbox(ag, 'Text', '', 'Value', true, 'Tooltip', 'Skip duplicate files by fingerprint');
    ui.uniqueFp.Layout.Row = 6; ui.uniqueFp.Layout.Column = 2;

    makeLabel(ag, 'Show Report:', [6 4]);
    ui.showReport = uicheckbox(ag, 'Text', '', 'Value', false, 'Tooltip', 'Show blocking concat report pop-up');
    ui.showReport.Layout.Row = 6; ui.showReport.Layout.Column = 5;

    makeLabel(ag, 'Quality Min:', [7 1]);
    ui.qualityMin = uieditfield(ag, 'numeric', 'Value', 0.6, 'Tooltip', 'Normalised xcorr quality threshold (0-1)');
    ui.qualityMin.Layout.Row = 7; ui.qualityMin.Layout.Column = 2;

    makeLabel(ag, 'Resample Hz:', [7 4]);
    ui.resampleHz = uieditfield(ag, 'numeric', 'Value', 100);
    ui.resampleHz.Layout.Row = 7; ui.resampleHz.Layout.Column = 5;

    makeLabel(ag, 'Max Offset (s):', [8 1]);
    ui.maxOffsetS = uieditfield(ag, 'numeric', 'Value', 1300);
    ui.maxOffsetS.Layout.Row = 8; ui.maxOffsetS.Layout.Column = 2;

    makeLabel(ag, 'RPM Min:', [8 4]);
    ui.rpmMin = uieditfield(ag, 'numeric', 'Value', 500, 'Tooltip', 'Minimum RPM to consider for alignment');
    ui.rpmMin.Layout.Row = 8; ui.rpmMin.Layout.Column = 5;

    makeLabel(ag, 'Merge Resample Hz:', [9 1]);
    ui.mergeResampleHz = uieditfield(ag, 'numeric', 'Value', 100);
    ui.mergeResampleHz.Layout.Row = 9; ui.mergeResampleHz.Layout.Column = 2;

    makeLabel(ag, 'Dash RPM Channel:', [10 1]);
    ui.dashRpmCh = uieditfield(ag, 'text', 'Value', 'Engine_Speed');
    ui.dashRpmCh.Layout.Row = 10; ui.dashRpmCh.Layout.Column = 2;

    makeLabel(ag, 'ECU RPM Channel:', [10 4]);
    ui.ecuRpmCh = uieditfield(ag, 'text', 'Value', 'Engine.Speed');
    ui.ecuRpmCh.Layout.Row = 10; ui.ecuRpmCh.Layout.Column = 5;

    makeLabel(ag, 'L180 RPM Channel:', [11 1]);
    ui.l180RpmCh = uieditfield(ag, 'text', 'Value', 'Engine_Speed');
    ui.l180RpmCh.Layout.Row = 11; ui.l180RpmCh.Layout.Column = 2;

    advBtn.ButtonPushedFcn = @(b,~) toggleAdvanced(b, advPnl);
end


function [ui, advPnl] = buildCompileTab(parent)
    ui = struct();
    g = uigridlayout(parent, [4 1]);
    g.RowHeight  = {50, 'fit', 34, 'fit'};
    g.Padding    = [8 8 8 8];
    g.RowSpacing = 6;

    blurb = uitextarea(g, 'Value', ...
        'Scans a folder of .ld files, extracts lap stats and channel traces, and saves a .mat cache for downstream analysis. ''stream'' mode is low-RAM; ''bulk'' is legacy high-RAM. Use Date From to skip older files.', ...
        'Editable', 'off', 'FontColor', [0.3 0.3 0.3], 'BackgroundColor', [0.96 0.96 0.96]); %#ok<NASGU>
    blurb.Layout.Row = 1;

    basicPnl = uipanel(g, 'Title', 'Parameters', 'BorderType', 'line');
    basicPnl.Layout.Row = 2;
    bg = uigridlayout(basicPnl, [6 4]);
    bg.ColumnWidth  = {150, '1x', 150, '1x'};
    bg.RowHeight    = repmat({22}, 1, 6);
    bg.Padding      = [6 6 6 6];
    bg.RowSpacing   = 4;
    bg.ColumnSpacing= 4;

    makeLabel(bg, 'Mode:', [1 1]);
    ui.mode = uidropdown(bg, 'Items', {'stream','bulk'}, 'Value', 'stream', ...
        'Tooltip', 'stream = low RAM (recommended); bulk = legacy high RAM');
    ui.mode.Layout.Row = 1; ui.mode.Layout.Column = 2;

    makeLabel(bg, 'Track:', [1 3]);
    ui.track = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Track code for lap time limits (from season file). Leave blank to skip.');
    ui.track.Layout.Row = 1; ui.track.Layout.Column = 4;

    makeLabel(bg, 'Session Filter (csv):', [2 1]);
    ui.sessionFilter = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Comma-separated sessions to include. Leave blank for all.');
    ui.sessionFilter.Layout.Row = 2; ui.sessionFilter.Layout.Column = [2 4];

    makeLabel(bg, 'Date From (yyyy-mm-dd):', [3 1]);
    ui.dateFrom = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Skip files older than this date. Leave blank to process all.');
    ui.dateFrom.Layout.Row = 3; ui.dateFrom.Layout.Column = 2;

    makeLabel(bg, 'Max Traces:', [3 3]);
    ui.maxTraces = uieditfield(bg, 'numeric', 'Value', 5, 'Tooltip', 'Maximum channel traces to load per file');
    ui.maxTraces.Layout.Row = 3; ui.maxTraces.Layout.Column = 4;

    makeLabel(bg, 'Save Cache:', [4 1]);
    ui.saveCache = uicheckbox(bg, 'Text', '', 'Value', true, 'Tooltip', 'Save compiled stats to .mat file');
    ui.saveCache.Layout.Row = 4; ui.saveCache.Layout.Column = 2;

    makeLabel(bg, 'Verbose:', [4 3]);
    ui.verbose = uicheckbox(bg, 'Text', '', 'Value', true, 'Tooltip', 'Print progress to Command Window');
    ui.verbose.Layout.Row = 4; ui.verbose.Layout.Column = 4;

    advBtn = uibutton(g, 'Text', '▼  Advanced', 'HorizontalAlignment', 'left');
    advBtn.Layout.Row = 3;

    advPnl = uipanel(g, 'Title', 'Advanced', 'BorderType', 'line', 'Visible', 'off');
    advPnl.Layout.Row = 4;
    ag = uigridlayout(advPnl, [5 4]);
    ag.ColumnWidth  = {160, '1x', 160, '1x'};
    ag.RowHeight    = repmat({22}, 1, 5);
    ag.Padding      = [6 6 6 6];
    ag.RowSpacing   = 4;
    ag.ColumnSpacing= 4;

    makeLabel(ag, 'Dist N Points:', [1 1]);
    ui.distNPoints = uieditfield(ag, 'numeric', 'Value', 1000, 'Tooltip', 'Number of points for distance interpolation');
    ui.distNPoints.Layout.Row = 1; ui.distNPoints.Layout.Column = 2;

    makeLabel(ag, 'Dist Channel:', [1 3]);
    ui.distChannel = uieditfield(ag, 'text', 'Value', 'Odometer', 'Tooltip', 'Channel name to use as distance axis');
    ui.distChannel.Layout.Row = 1; ui.distChannel.Layout.Column = 4;

    makeLabel(ag, 'Save Mode:', [2 1]);
    ui.saveMode = uidropdown(ag, 'Items', {'session','event'}, 'Value', 'session', ...
        'Tooltip', 'session = one .mat per session; event = single combined .mat');
    ui.saveMode.Layout.Row = 2; ui.saveMode.Layout.Column = 2;

    makeLabel(ag, 'Load All Channels:', [2 3]);
    ui.loadAllChannels = uicheckbox(ag, 'Text', '', 'Value', true, 'Tooltip', 'Load all channels (not just those in channels file)');
    ui.loadAllChannels.Layout.Row = 2; ui.loadAllChannels.Layout.Column = 4;

    makeLabel(ag, 'Concat CSV Dir:', [3 1]);
    ui.concatCsvDir = uieditfield(ag, 'text', 'Value', '');
    ui.concatCsvDir.Layout.Row = 3; ui.concatCsvDir.Layout.Column = 2;
    makeBtn(ag, 'Browse...', 3, 3, @(~,~) onBrowseDir([], ui.concatCsvDir));

    makeLabel(ag, 'Show Concat Report:', [4 1]);
    ui.showConcatReport = uicheckbox(ag, 'Text', '', 'Value', true);
    ui.showConcatReport.Layout.Row = 4; ui.showConcatReport.Layout.Column = 2;

    makeLabel(ag, 'BR2 Channel:', [5 1]);
    ui.br2Channel = uieditfield(ag, 'text', 'Value', 'BR2_Beacon_Number');
    ui.br2Channel.Layout.Row = 5; ui.br2Channel.Layout.Column = 2;

    makeLabel(ag, 'BR2 Protocol:', [5 3]);
    ui.br2Protocol = uieditfield(ag, 'text', 'Value', 'Standard', 'Tooltip', 'BR2 protocol name, e.g. Standard or TAS2025');
    ui.br2Protocol.Layout.Row = 5; ui.br2Protocol.Layout.Column = 4;

    advBtn.ButtonPushedFcn = @(b,~) toggleAdvanced(b, advPnl);
end


function [ui, advPnl] = buildReportTab(parent, defPptx) %#ok<INUSD>
    ui = struct();
    g = uigridlayout(parent, [4 1]);
    g.RowHeight  = {50, 'fit', 34, 'fit'};
    g.Padding    = [8 8 8 8];
    g.RowSpacing = 6;

    blurb = uitextarea(g, 'Value', ...
        'Single entry point: compile .ld files, recompute virtual channels, generate plots and upload to SQL/PocketBase. Choose Full for PPTX reports with upload, or Reduced for dev/workshop use (no PPTX, writes VCH .ld sidecars instead).', ...
        'Editable', 'off', 'FontColor', [0.3 0.3 0.3], 'BackgroundColor', [0.96 0.96 0.96]); %#ok<NASGU>
    blurb.Layout.Row = 1;

    basicPnl = uipanel(g, 'Title', 'Parameters', 'BorderType', 'line');
    basicPnl.Layout.Row = 2;
    bg = uigridlayout(basicPnl, [8 4]);
    bg.ColumnWidth  = {160, '1x', 160, '1x'};
    bg.RowHeight    = repmat({22}, 1, 8);
    bg.Padding      = [6 6 6 6];
    bg.RowSpacing   = 4;
    bg.ColumnSpacing= 4;

    makeLabel(bg, 'Script Variant:', [1 1]);
    ui.variant = uidropdown(bg, 'Items', {'Full','Reduced'}, 'Value', 'Full', ...
        'Tooltip', 'Full = PPTX + upload. Reduced = dev mode, writes _VCH.ld files.');
    ui.variant.Layout.Row = 1; ui.variant.Layout.Column = 2;

    makeLabel(bg, 'Compile Mode:', [1 3]);
    ui.mode = uidropdown(bg, 'Items', {'serial','parallel'}, 'Value', 'serial', ...
        'Tooltip', 'serial = single thread; parallel = multi-worker');
    ui.mode.Layout.Row = 1; ui.mode.Layout.Column = 4;

    makeLabel(bg, 'Session Filter (csv):', [2 1]);
    ui.sessionFilter = uieditfield(bg, 'text', 'Value', 'Q15', 'Tooltip', 'Comma-separated sessions. e.g. Q14,Q15');
    ui.sessionFilter.Layout.Row = 2; ui.sessionFilter.Layout.Column = 2;

    makeLabel(bg, 'Team Filter (csv):', [2 3]);
    ui.teamFilter = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Comma-separated team acronyms. Leave blank for all.');
    ui.teamFilter.Layout.Row = 2; ui.teamFilter.Layout.Column = 4;

    makeLabel(bg, 'Run Recompute VCH:', [3 1]);
    ui.runRecomputeVch = uicheckbox(bg, 'Text', '', 'Value', true, 'Tooltip', 'Recompute virtual channels from smp_custom_channels.m');
    ui.runRecomputeVch.Layout.Row = 3; ui.runRecomputeVch.Layout.Column = 2;

    makeLabel(bg, 'Run Upload:', [3 3]);
    ui.runUpload = uicheckbox(bg, 'Text', '', 'Value', false, 'Tooltip', 'Upload compiled stats to SQL/PocketBase (Full only)');
    ui.runUpload.Layout.Row = 3; ui.runUpload.Layout.Column = 4;

    makeLabel(bg, 'Upload Target:', [4 1]);
    ui.target = uidropdown(bg, 'Items', {'azure_online','azure_local','pocketbase'}, 'Value', 'azure_online', ...
        'Tooltip', 'Destination for smp_push_to_sql / PocketBase upload');
    ui.target.Layout.Row = 4; ui.target.Layout.Column = 2;

    makeLabel(bg, 'Plotting:', [4 3]);
    ui.plotting = uicheckbox(bg, 'Text', '', 'Value', true, 'Tooltip', 'Generate PPTX plots');
    ui.plotting.Layout.Row = 4; ui.plotting.Layout.Column = 4;

    makeLabel(bg, 'Save Cache:', [5 1]);
    ui.saveCache = uicheckbox(bg, 'Text', '', 'Value', true);
    ui.saveCache.Layout.Row = 5; ui.saveCache.Layout.Column = 2;

    makeLabel(bg, 'Workshop Mode:', [5 3]);
    ui.workshop = uicheckbox(bg, 'Text', '', 'Value', false, 'Tooltip', 'Workshop mode — all sessions, no session filter');
    ui.workshop.Layout.Row = 5; ui.workshop.Layout.Column = 4;

    makeLabel(bg, 'Create Pitstop Report:', [6 1]);
    ui.createPitstop = uicheckbox(bg, 'Text', '', 'Value', false);
    ui.createPitstop.Layout.Row = 6; ui.createPitstop.Layout.Column = 2;

    makeLabel(bg, 'Overwrite:', [6 3]);
    ui.overwrite = uicheckbox(bg, 'Text', '', 'Value', false, 'Tooltip', 'Overwrite existing cache entries');
    ui.overwrite.Layout.Row = 6; ui.overwrite.Layout.Column = 4;

    makeLabel(bg, 'Batch Size:', [7 1]);
    ui.batchSize = uieditfield(bg, 'numeric', 'Value', 200, 'Tooltip', 'Upload batch size (rows per JDBC call)');
    ui.batchSize.Layout.Row = 7; ui.batchSize.Layout.Column = 2;

    makeLabel(bg, 'N Workers:', [7 3]);
    ui.nWorkers = uieditfield(bg, 'numeric', 'Value', 4, 'Tooltip', 'Parallel worker count (parallel mode only)');
    ui.nWorkers.Layout.Row = 7; ui.nWorkers.Layout.Column = 4;

    makeLabel(bg, 'Plot Config Files (csv paths):', [8 1]);
    ui.plotConfigFiles = uieditfield(bg, 'text', 'Value', '', 'Tooltip', 'Comma-separated paths to plottingRequest .xlsx files');
    ui.plotConfigFiles.Layout.Row = 8; ui.plotConfigFiles.Layout.Column = [2 4];

    advBtn = uibutton(g, 'Text', '▼  Advanced', 'HorizontalAlignment', 'left');
    advBtn.Layout.Row = 3;

    advPnl = uipanel(g, 'Title', 'Advanced', 'BorderType', 'line', 'Visible', 'off');
    advPnl.Layout.Row = 4;
    ag = uigridlayout(advPnl, [12 4]);
    ag.ColumnWidth  = {180, '1x', 180, '1x'};
    ag.RowHeight    = repmat({22}, 1, 12);
    ag.Padding      = [6 6 6 6];
    ag.RowSpacing   = 4;
    ag.ColumnSpacing= 4;

    makeSectionLabel(ag, '— compile_opts —', 1, [1 4]);

    makeLabel(ag, 'Compile Sub-mode:', [2 1]);
    ui.compileModeAdv = uidropdown(ag, 'Items', {'stream','bulk'}, 'Value', 'stream');
    ui.compileModeAdv.Layout.Row = 2; ui.compileModeAdv.Layout.Column = 2;

    makeLabel(ag, 'Max Traces:', [2 3]);
    ui.compileMaxTraces = uieditfield(ag, 'numeric', 'Value', 4);
    ui.compileMaxTraces.Layout.Row = 2; ui.compileMaxTraces.Layout.Column = 4;

    makeLabel(ag, 'Dist N Points:', [3 1]);
    ui.distNPoints = uieditfield(ag, 'numeric', 'Value', 1000);
    ui.distNPoints.Layout.Row = 3; ui.distNPoints.Layout.Column = 2;

    makeLabel(ag, 'Dist Channel:', [3 3]);
    ui.distChannel = uieditfield(ag, 'text', 'Value', 'Odometer');
    ui.distChannel.Layout.Row = 3; ui.distChannel.Layout.Column = 4;

    makeLabel(ag, 'BR2 Channel:', [4 1]);
    ui.br2Channel = uieditfield(ag, 'text', 'Value', 'BR2_Beacon_Number');
    ui.br2Channel.Layout.Row = 4; ui.br2Channel.Layout.Column = 2;

    makeLabel(ag, 'BR2 Protocol:', [4 3]);
    ui.br2Protocol = uieditfield(ag, 'text', 'Value', 'Standard');
    ui.br2Protocol.Layout.Row = 4; ui.br2Protocol.Layout.Column = 4;

    makeLabel(ag, 'Date From (yyyy-mm-dd):', [5 1]);
    ui.dateFrom = uieditfield(ag, 'text', 'Value', '', 'Tooltip', 'Skip files older than this date');
    ui.dateFrom.Layout.Row = 5; ui.dateFrom.Layout.Column = 2;

    makeSectionLabel(ag, '— processing —', 6, [1 4]);

    makeLabel(ag, 'Recompute Mode:', [7 1]);
    ui.recomputeMode = uidropdown(ag, 'Items', {'serial','parallel'}, 'Value', 'serial');
    ui.recomputeMode.Layout.Row = 7; ui.recomputeMode.Layout.Column = 2;

    makeLabel(ag, 'Timeout (s):', [7 3]);
    ui.timeoutS = uieditfield(ag, 'numeric', 'Value', 3600);
    ui.timeoutS.Layout.Row = 7; ui.timeoutS.Layout.Column = 4;

    makeLabel(ag, 'Keep Workers Open:', [8 1]);
    ui.keepWorkersOpen = uicheckbox(ag, 'Text', '', 'Value', false);
    ui.keepWorkersOpen.Layout.Row = 8; ui.keepWorkersOpen.Layout.Column = 2;

    makeLabel(ag, 'VCH Debug Plot:', [8 3]);
    ui.vchDebugPlot = uicheckbox(ag, 'Text', '', 'Value', true, 'Tooltip', 'Generate VCH debug figure');
    ui.vchDebugPlot.Layout.Row = 8; ui.vchDebugPlot.Layout.Column = 4;

    makeLabel(ag, 'VCH Debug Team:', [9 1]);
    ui.vchDebugTeam = uieditfield(ag, 'text', 'Value', '', 'Tooltip', 'Team acronym for VCH debug. Blank = first available.');
    ui.vchDebugTeam.Layout.Row = 9; ui.vchDebugTeam.Layout.Column = 2;

    makeLabel(ag, 'VCH Debug X:', [9 3]);
    ui.vchDebugX = uieditfield(ag, 'text', 'Value', 'time');
    ui.vchDebugX.Layout.Row = 9; ui.vchDebugX.Layout.Column = 4;

    makeLabel(ag, 'VCH Debug Y (csv chs):', [10 1]);
    ui.vchDebugY = uieditfield(ag, 'text', 'Value', 'brakeBiasVCH,RL_SlipVCH', 'Tooltip', 'Comma-separated channel names to plot in VCH debug');
    ui.vchDebugY.Layout.Row = 10; ui.vchDebugY.Layout.Column = [2 4];

    makeLabel(ag, 'Write VCH LD (Reduced):', [11 1]);
    ui.writeVchLd = uicheckbox(ag, 'Text', '', 'Value', true, 'Tooltip', 'Write _VCH.ld sidecar files (Reduced variant only)');
    ui.writeVchLd.Layout.Row = 11; ui.writeVchLd.Layout.Column = 2;

    makeLabel(ag, 'VCH LD Suffix (Reduced):', [11 3]);
    ui.vchLdSuffix = uieditfield(ag, 'text', 'Value', '_VCH');
    ui.vchLdSuffix.Layout.Row = 11; ui.vchLdSuffix.Layout.Column = 4;

    makeSectionLabel(ag, '— plot_opts —', 12, [1 4]);

    % plot_opts row — add additional row
    ag.RowHeight{end+1} = 22;
    makeLabel(ag, 'Fig Width:', [13 1]);
    ui.figWidth = uieditfield(ag, 'numeric', 'Value', 1200);
    ui.figWidth.Layout.Row = 13; ui.figWidth.Layout.Column = 2;

    makeLabel(ag, 'Fig Height:', [13 3]);
    ui.figHeight = uieditfield(ag, 'numeric', 'Value', 650);
    ui.figHeight.Layout.Row = 13; ui.figHeight.Layout.Column = 4;

    ag.RowHeight{end+1} = 22;
    makeLabel(ag, 'Font Size:', [14 1]);
    ui.fontSize = uieditfield(ag, 'numeric', 'Value', 11);
    ui.fontSize.Layout.Row = 14; ui.fontSize.Layout.Column = 2;

    makeLabel(ag, 'N Laps Avg:', [14 3]);
    ui.nLapsAvg = uieditfield(ag, 'numeric', 'Value', 3, 'Tooltip', 'Number of laps to average for rolling metrics');
    ui.nLapsAvg.Layout.Row = 14; ui.nLapsAvg.Layout.Column = 4;

    advBtn.ButtonPushedFcn = @(b,~) toggleAdvanced(b, advPnl);
end


function [ui_quali, ui_lac, advPnl_quali, advPnl_lac, subTg] = buildFuelTab(parent)
    subTg = uitabgroup(parent);

    %% --- Sub-tab A: Quali Fuel ---
    tA = uitab(subTg, 'Title', 'Quali Fuel');
    ui_quali = struct();
    gA = uigridlayout(tA, [4 1]);
    gA.RowHeight  = {50, 'fit', 34, 'fit'};
    gA.Padding    = [8 8 8 8];
    gA.RowSpacing = 6;

    blurbA = uitextarea(gA, 'Value', ...
        'Runs fuel-effect regression across qualifying runs. Loads the compiled cache, fits a linear fuel-load vs lap-time model per car, and generates tyre pressure and fuel-effect plots.', ...
        'Editable', 'off', 'FontColor', [0.3 0.3 0.3], 'BackgroundColor', [0.96 0.96 0.96]); %#ok<NASGU>
    blurbA.Layout.Row = 1;

    basicA = uipanel(gA, 'Title', 'Parameters', 'BorderType', 'line');
    basicA.Layout.Row = 2;
    bgA = uigridlayout(basicA, [5 4]);
    bgA.ColumnWidth  = {160, '1x', 160, '1x'};
    bgA.RowHeight    = repmat({22}, 1, 5);
    bgA.Padding      = [6 6 6 6];
    bgA.RowSpacing   = 4;
    bgA.ColumnSpacing= 4;

    makeLabel(bgA, 'Track:', [1 1]);
    ui_quali.track = uieditfield(bgA, 'text', 'Value', '', 'Tooltip', 'Track code, e.g. TAS');
    ui_quali.track.Layout.Row = 1; ui_quali.track.Layout.Column = 2;

    makeLabel(bgA, 'Event Code:', [1 3]);
    ui_quali.eventCode = uieditfield(bgA, 'text', 'Value', '', 'Tooltip', 'Event code, e.g. 04_TAS');
    ui_quali.eventCode.Layout.Row = 1; ui_quali.eventCode.Layout.Column = 4;

    makeLabel(bgA, 'Year:', [2 1]);
    ui_quali.year = uieditfield(bgA, 'numeric', 'Value', 2026, 'Limits', [2000 2100], 'RoundFractionalValues', 'on');
    ui_quali.year.Layout.Row = 2; ui_quali.year.Layout.Column = 2;

    makeLabel(bgA, 'Session Filter (csv):', [3 1]);
    ui_quali.sessionFilter = uieditfield(bgA, 'text', 'Value', 'Q13', 'Tooltip', 'Comma-separated session labels');
    ui_quali.sessionFilter.Layout.Row = 3; ui_quali.sessionFilter.Layout.Column = 2;

    makeLabel(bgA, 'Team Filter (csv):', [3 3]);
    ui_quali.teamFilter = uieditfield(bgA, 'text', 'Value', '', 'Tooltip', 'Leave blank for all teams');
    ui_quali.teamFilter.Layout.Row = 3; ui_quali.teamFilter.Layout.Column = 4;

    makeLabel(bgA, 'BR2 Protocol:', [4 1]);
    ui_quali.br2Protocol = uieditfield(bgA, 'text', 'Value', 'Standard', 'Tooltip', 'e.g. Standard or TAS2025');
    ui_quali.br2Protocol.Layout.Row = 4; ui_quali.br2Protocol.Layout.Column = 2;

    makeLabel(bgA, 'Show Report:', [4 3]);
    ui_quali.showReport = uicheckbox(bgA, 'Text', '', 'Value', true, 'Tooltip', 'Show fuel analysis report figure');
    ui_quali.showReport.Layout.Row = 4; ui_quali.showReport.Layout.Column = 4;

    advBtnA = uibutton(gA, 'Text', '▼  Advanced', 'HorizontalAlignment', 'left');
    advBtnA.Layout.Row = 3;

    advPnl_quali = uipanel(gA, 'Title', 'Advanced (compile_opts)', 'BorderType', 'line', 'Visible', 'off');
    advPnl_quali.Layout.Row = 4;
    agA = uigridlayout(advPnl_quali, [5 4]);
    agA.ColumnWidth  = {160, '1x', 160, '1x'};
    agA.RowHeight    = repmat({22}, 1, 5);
    agA.Padding      = [6 6 6 6];
    agA.RowSpacing   = 4;
    agA.ColumnSpacing= 4;

    makeLabel(agA, 'Mode:', [1 1]);
    ui_quali.compileMode = uidropdown(agA, 'Items', {'stream','bulk'}, 'Value', 'stream');
    ui_quali.compileMode.Layout.Row = 1; ui_quali.compileMode.Layout.Column = 2;

    makeLabel(agA, 'Dist N Points:', [1 3]);
    ui_quali.distNPoints = uieditfield(agA, 'numeric', 'Value', 1000);
    ui_quali.distNPoints.Layout.Row = 1; ui_quali.distNPoints.Layout.Column = 4;

    makeLabel(agA, 'Dist Channel:', [2 1]);
    ui_quali.distChannel = uieditfield(agA, 'text', 'Value', 'Odometer');
    ui_quali.distChannel.Layout.Row = 2; ui_quali.distChannel.Layout.Column = 2;

    makeLabel(agA, 'Verbose:', [2 3]);
    ui_quali.verbose = uicheckbox(agA, 'Text', '', 'Value', true);
    ui_quali.verbose.Layout.Row = 2; ui_quali.verbose.Layout.Column = 4;

    makeLabel(agA, 'Save Cache:', [3 1]);
    ui_quali.saveCache = uicheckbox(agA, 'Text', '', 'Value', true);
    ui_quali.saveCache.Layout.Row = 3; ui_quali.saveCache.Layout.Column = 2;

    makeLabel(agA, 'Save Mode:', [3 3]);
    ui_quali.saveMode = uidropdown(agA, 'Items', {'session','event'}, 'Value', 'session');
    ui_quali.saveMode.Layout.Row = 3; ui_quali.saveMode.Layout.Column = 4;

    makeLabel(agA, 'BR2 Channel:', [4 1]);
    ui_quali.br2Channel = uieditfield(agA, 'text', 'Value', 'BR2_Beacon_Number');
    ui_quali.br2Channel.Layout.Row = 4; ui_quali.br2Channel.Layout.Column = 2;

    advBtnA.ButtonPushedFcn = @(b,~) toggleAdvanced(b, advPnl_quali);

    %% --- Sub-tab B: Lift & Coast ---
    tB = uitab(subTg, 'Title', 'Lift & Coast');
    ui_lac = struct();
    gB = uigridlayout(tB, [4 1]);
    gB.RowHeight  = {50, 'fit', 34, 'fit'};
    gB.Padding    = [8 8 8 8];
    gB.RowSpacing = 6;

    blurbB = uitextarea(gB, 'Value', ...
        'Lift-and-coast strategy optimiser. Detects (or manually specifies) coasting zones, estimates fuel and time tradeoffs, and outputs optimal segment candidates. Requires the event cache to be compiled first (Compile Event tab).', ...
        'Editable', 'off', 'FontColor', [0.3 0.3 0.3], 'BackgroundColor', [0.96 0.96 0.96]); %#ok<NASGU>
    blurbB.Layout.Row = 1;

    basicB = uipanel(gB, 'Title', 'Parameters', 'BorderType', 'line');
    basicB.Layout.Row = 2;
    bgB = uigridlayout(basicB, [7 4]);
    bgB.ColumnWidth  = {160, '1x', 160, '1x'};
    bgB.RowHeight    = repmat({22}, 1, 7);
    bgB.Padding      = [6 6 6 6];
    bgB.RowSpacing   = 4;
    bgB.ColumnSpacing= 4;

    makeLabel(bgB, 'Event (required):', [1 1]);
    ui_lac.event = uieditfield(bgB, 'text', 'Value', '', 'Tooltip', 'Event code, e.g. 04_RUA');
    ui_lac.event.Layout.Row = 1; ui_lac.event.Layout.Column = 2;

    makeLabel(bgB, 'Year:', [1 3]);
    ui_lac.year = uieditfield(bgB, 'numeric', 'Value', 2026, 'Limits', [2000 2100], 'RoundFractionalValues', 'on');
    ui_lac.year.Layout.Row = 1; ui_lac.year.Layout.Column = 4;

    makeLabel(bgB, 'Session ID:', [2 1]);
    ui_lac.sessionId = uieditfield(bgB, 'text', 'Value', 'Q13', 'Tooltip', 'Session label, e.g. Q13');
    ui_lac.sessionId.Layout.Row = 2; ui_lac.sessionId.Layout.Column = 2;

    makeLabel(bgB, 'Driver TLA:', [2 3]);
    ui_lac.driverTla = uieditfield(bgB, 'text', 'Value', '', 'Tooltip', '3-letter driver code. Leave blank for all drivers.');
    ui_lac.driverTla.Layout.Row = 2; ui_lac.driverTla.Layout.Column = 4;

    makeLabel(bgB, 'Fuel Rate (kg/m):', [3 1]);
    ui_lac.fuelRate = uieditfield(bgB, 'numeric', 'Value', 0.0025, 'Tooltip', 'Fuel consumption rate in kg/m');
    ui_lac.fuelRate.Layout.Row = 3; ui_lac.fuelRate.Layout.Column = 2;

    makeLabel(bgB, 'Deceleration (m/s²):', [3 3]);
    ui_lac.accel = uieditfield(bgB, 'numeric', 'Value', -11.5/3.6, 'Tooltip', 'Coasting deceleration in m/s². Typically negative.');
    ui_lac.accel.Layout.Row = 3; ui_lac.accel.Layout.Column = 4;

    makeLabel(bgB, 'Time Budget (s):', [4 1]);
    ui_lac.timeBudget = uieditfield(bgB, 'text', 'Value', 'NaN', 'Tooltip', 'Maximum time loss budget in seconds. NaN = no constraint.');
    ui_lac.timeBudget.Layout.Row = 4; ui_lac.timeBudget.Layout.Column = 2;

    makeLabel(bgB, 'Fuel Targets (space-sep):', [4 3]);
    ui_lac.fuelTargets = uieditfield(bgB, 'text', 'Value', '', 'Tooltip', 'Space-separated fuel saving targets in kg. Leave blank for default sweep.');
    ui_lac.fuelTargets.Layout.Row = 4; ui_lac.fuelTargets.Layout.Column = 4;

    makeLabel(bgB, 'Auto Detect:', [5 1]);
    ui_lac.autoDetect = uicheckbox(bgB, 'Text', '', 'Value', true, 'Tooltip', 'Auto-detect lift-and-coast segments from telemetry');
    ui_lac.autoDetect.Layout.Row = 5; ui_lac.autoDetect.Layout.Column = 2;

    makeLabel(bgB, 'Compile:', [5 3]);
    ui_lac.compile = uicheckbox(bgB, 'Text', '', 'Value', false, 'Tooltip', 'Re-compile event cache before running');
    ui_lac.compile.Layout.Row = 5; ui_lac.compile.Layout.Column = 4;

    advBtnB = uibutton(gB, 'Text', '▼  Advanced', 'HorizontalAlignment', 'left');
    advBtnB.Layout.Row = 3;

    advPnl_lac = uipanel(gB, 'Title', 'Advanced', 'BorderType', 'line', 'Visible', 'off');
    advPnl_lac.Layout.Row = 4;
    agB = uigridlayout(advPnl_lac, [5 4]);
    agB.ColumnWidth  = {160, '1x', 160, '1x'};
    agB.RowHeight    = repmat({22}, 1, 5);
    agB.Padding      = [6 6 6 6];
    agB.RowSpacing   = 4;
    agB.ColumnSpacing= 4;

    makeLabel(agB, 'Config File:', [1 1]);
    ui_lac.configFile = uieditfield(agB, 'text', 'Value', '', 'Tooltip', 'Path to optional LiftAndCoast config .xlsx');
    ui_lac.configFile.Layout.Row = 1; ui_lac.configFile.Layout.Column = 2;
    makeBtn(agB, 'Browse...', 1, 3, @(~,~) onBrowseFile([], ui_lac.configFile, '*.xlsx'));

    makeLabel(agB, 'Concat CSV Dir:', [2 1]);
    ui_lac.concatCsvDir = uieditfield(agB, 'text', 'Value', '');
    ui_lac.concatCsvDir.Layout.Row = 2; ui_lac.concatCsvDir.Layout.Column = 2;
    makeBtn(agB, 'Browse...', 2, 3, @(~,~) onBrowseDir([], ui_lac.concatCsvDir));

    makeLabel(agB, 'BR2 Protocol:', [3 1]);
    ui_lac.br2Protocol = uieditfield(agB, 'text', 'Value', 'standard');
    ui_lac.br2Protocol.Layout.Row = 3; ui_lac.br2Protocol.Layout.Column = 2;

    makeLabel(agB, 'Rerun:', [3 3]);
    ui_lac.rerun = uicheckbox(agB, 'Text', '', 'Value', false, 'Tooltip', 'Force re-run even if cached results exist');
    ui_lac.rerun.Layout.Row = 3; ui_lac.rerun.Layout.Column = 4;

    makeLabel(agB, 'Run Diagnostic:', [4 1]);
    ui_lac.runDiagnostic = uicheckbox(agB, 'Text', '', 'Value', false, 'Tooltip', 'Run segment detection diagnostics');
    ui_lac.runDiagnostic.Layout.Row = 4; ui_lac.runDiagnostic.Layout.Column = 2;

    makeLabel(agB, 'Visible:', [4 3]);
    ui_lac.visible = uicheckbox(agB, 'Text', '', 'Value', true, 'Tooltip', 'Show output figures');
    ui_lac.visible.Layout.Row = 4; ui_lac.visible.Layout.Column = 4;

    makeLabel(agB, 'Debug:', [5 1]);
    ui_lac.debug = uicheckbox(agB, 'Text', '', 'Value', false, 'Tooltip', 'Enable verbose debug output');
    ui_lac.debug.Layout.Row = 5; ui_lac.debug.Layout.Column = 2;

    advBtnB.ButtonPushedFcn = @(b,~) toggleAdvanced(b, advPnl_lac);
end


function ui = buildDbUploadTab(parent)
    ui = struct();
    g = uigridlayout(parent, [3 1]);
    g.RowHeight  = {50, 'fit', 'fit'};
    g.Padding    = [8 8 8 8];
    g.RowSpacing = 6;

    blurb = uitextarea(g, 'Value', ...
        'Uploads a flattened lap-stats table to SQL Server via JDBC. Reads the compiled .mat cache, flattens it to a table, then batch-inserts into the target schema. Use Dry Run to preview row counts without writing to the database.', ...
        'Editable', 'off', 'FontColor', [0.3 0.3 0.3], 'BackgroundColor', [0.96 0.96 0.96]); %#ok<NASGU>
    blurb.Layout.Row = 1;

    basicPnl = uipanel(g, 'Title', 'Parameters', 'BorderType', 'line');
    basicPnl.Layout.Row = 2;
    bg = uigridlayout(basicPnl, [4 4]);
    bg.ColumnWidth  = {150, '1x', 150, '1x'};
    bg.RowHeight    = repmat({22}, 1, 4);
    bg.Padding      = [6 6 6 6];
    bg.RowSpacing   = 4;
    bg.ColumnSpacing= 4;

    makeLabel(bg, 'Table Name:', [1 1]);
    ui.tableName = uieditfield(bg, 'text', 'Value', 'lap_stats', 'Tooltip', 'SQL table name to write to');
    ui.tableName.Layout.Row = 1; ui.tableName.Layout.Column = 2;

    makeLabel(bg, 'Schema:', [1 3]);
    ui.schema = uieditfield(bg, 'text', 'Value', 'dbo', 'Tooltip', 'SQL schema, e.g. dbo or analytics');
    ui.schema.Layout.Row = 1; ui.schema.Layout.Column = 4;

    makeLabel(bg, 'Batch Size:', [2 1]);
    ui.batchSize = uieditfield(bg, 'numeric', 'Value', 100, 'Tooltip', 'Number of rows per JDBC insert batch');
    ui.batchSize.Layout.Row = 2; ui.batchSize.Layout.Column = 2;

    makeLabel(bg, 'Overwrite:', [2 3]);
    ui.overwrite = uicheckbox(bg, 'Text', '', 'Value', true, 'Tooltip', 'Delete existing rows before inserting');
    ui.overwrite.Layout.Row = 2; ui.overwrite.Layout.Column = 4;

    makeLabel(bg, 'Dry Run:', [3 1]);
    ui.dryRun = uicheckbox(bg, 'Text', '', 'Value', false, 'Tooltip', 'Preview row counts without writing to DB');
    ui.dryRun.Layout.Row = 3; ui.dryRun.Layout.Column = 2;

    hCacheNote = uilabel(bg, 'Text', 'Cache file must be loaded via V8PRV_Pitwall or passed directly.', ...
        'FontColor', [0.5 0.5 0.5], 'FontSize', 9);
    hCacheNote.Layout.Row = 4; hCacheNote.Layout.Column = [1 4];
end


function ui = buildWriteVchTab(parent)
    ui = struct();
    g = uigridlayout(parent, [3 1]);
    g.RowHeight  = {50, 'fit', 'fit'};
    g.Padding    = [8 8 8 8];
    g.RowSpacing = 6;

    blurb = uitextarea(g, 'Value', ...
        'Writes computed virtual channels (marked with write_to_ld = true in smp_custom_channels.m) back into .ld files as _vch.ld sidecars. Paste one source .ld path per line, or use Browse to add files.', ...
        'Editable', 'off', 'FontColor', [0.3 0.3 0.3], 'BackgroundColor', [0.96 0.96 0.96]); %#ok<NASGU>
    blurb.Layout.Row = 1;

    basicPnl = uipanel(g, 'Title', 'Parameters', 'BorderType', 'line');
    basicPnl.Layout.Row = 2;
    bg = uigridlayout(basicPnl, [5 3]);
    bg.ColumnWidth  = {160, '1x', 90};
    bg.RowHeight    = {22, 22, '1x', 22, 22};
    bg.Padding      = [6 6 6 6];
    bg.RowSpacing   = 4;
    bg.ColumnSpacing= 4;

    makeLabel(bg, 'Source .ld Files:', [1 1]);
    hPathNote = uilabel(bg, 'Text', '(one path per line)', 'FontColor', [0.5 0.5 0.5], 'FontSize', 9);
    hPathNote.Layout.Row = 2; hPathNote.Layout.Column = 1;

    ui.sourceFiles = uitextarea(bg, 'Value', '', 'Tooltip', 'Paste full paths to source .ld files, one per line');
    ui.sourceFiles.Layout.Row = [1 4]; ui.sourceFiles.Layout.Column = 2;

    makeBtn(bg, 'Add Files...', 1, 3, @(~,~) onAddFiles(ui.sourceFiles));

    makeLabel(bg, 'Output Suffix:', [5 1]);
    ui.outputSuffix = uieditfield(bg, 'text', 'Value', '_vch', 'Tooltip', 'Appended before .ld extension, e.g. _vch → filename_vch.ld');
    ui.outputSuffix.Layout.Row = 5; ui.outputSuffix.Layout.Column = 2;

    % Overwrite separate row below panel
    optPnl = uipanel(g, 'Title', 'Options', 'BorderType', 'line');
    optPnl.Layout.Row = 3;
    og = uigridlayout(optPnl, [1 4]);
    og.ColumnWidth = {160, 22, '1x', '1x'};
    og.RowHeight   = {22};
    og.Padding     = [6 6 6 6];

    makeLabel(og, 'Overwrite:', [1 1]);
    ui.overwrite = uicheckbox(og, 'Text', '', 'Value', true, 'Tooltip', 'Overwrite existing _vch.ld files');
    ui.overwrite.Layout.Row = 1; ui.overwrite.Layout.Column = 2;
end


%% ========================================================================
%  RUN CALLBACK
%% ========================================================================

function onRun(fig, tg, hRunBtn, hStatus, ...
        hRootDir, hEvent, hTrack, hYear, hChannelsFile, hSeasonFile, hOutputDir, hPptx, ...
        ui1, advPnl1, ui2, advPnl2, ui3, advPnl3, ui4_quali, ui4_lac, ...
        advPnl4_quali, advPnl4_lac, fuelSubTg, ui5, ui6) %#ok<INUSL>

    tabTitle = tg.SelectedTab.Title;

    % Collect common config
    common.rootDir      = strtrim(hRootDir.Value);
    common.event        = strtrim(hEvent.Value);
    common.track        = strtrim(hTrack.Value);
    common.year         = hYear.Value;
    common.channelsFile = strtrim(hChannelsFile.Value);
    common.seasonFile   = strtrim(hSeasonFile.Value);
    common.outputDir    = strtrim(hOutputDir.Value);
    common.pptxTemplate = strtrim(hPptx.Value);

    hRunBtn.Enable = 'off';
    hStatus.Text   = '⟳  Running...';
    hStatus.FontColor = [0.6 0.4 0.0];
    drawnow;

    try
        switch tabTitle
            case 'MoTeC Pipeline'
                run_launcher_pipeline(common, ui1);
            case 'Compile Event'
                run_launcher_compile(common, ui2);
            case 'Main Report'
                run_launcher_report(common, ui3);
            case 'Fuel Analysis'
                subTitle = fuelSubTg.SelectedTab.Title;
                if strcmp(subTitle, 'Quali Fuel')
                    run_launcher_quali_fuel(common, ui4_quali);
                else
                    run_launcher_lift_coast(ui4_lac);
                end
            case 'DB Upload'
                run_launcher_db_upload(common, ui5);
            case 'Write VCH'
                run_launcher_write_vch(ui6);
        end
        hStatus.Text      = '✓  Done';
        hStatus.FontColor = [0.1 0.55 0.1];
    catch ME
        hStatus.Text      = ['✗  Error: ' ME.message];
        hStatus.FontColor = [0.8 0.1 0.1];
    end

    hRunBtn.Enable = 'on';
end


%% ========================================================================
%  SCRIPT RUNNERS  (called from onRun)
%% ========================================================================

function run_launcher_pipeline(common, ui)
    SESSION   = strtrim(ui.session.Value);
    drv_str   = strtrim(ui.drivers.Value);
    if isempty(drv_str)
        DRIVERS = {};
    else
        DRIVERS = strtrim(strsplit(drv_str, ','));
    end
    OVERWRITE           = ui.overwrite.Value;
    RUN_TEAMDATA_CONCAT = ui.phaseTeamData.Value;
    RUN_ECU_CONCAT      = ui.phaseEcu.Value;
    RUN_SPLIT           = ui.phaseSplit.Value;
    RUN_PAIR            = ui.phasePair.Value;
    RUN_MERGE           = ui.phaseMerge.Value;

    cfg.root_folder       = valOrCommon(ui.rootFolder.Value, common.rootDir);
    cfg.hol_dir           = strtrim(ui.holDir.Value);
    cfg.hol_venue         = strtrim(ui.holVenue.Value);
    cfg.hol_event         = strtrim(ui.holEvent.Value);
    cfg.event_alias_file  = strtrim(ui.eventAliasFile.Value);
    cfg.driver_alias_file = strtrim(ui.driverAliasFile.Value);

    sl = strtrim(strsplit(strtrim(ui.sessionLabels.Value), ','));
    cfg.session_labels    = sl(~cellfun(@isempty, sl));

    cfg.warmup_beacon_chs  = parseCommaSep(ui.warmupBeaconChs.Value);
    cfg.ridealong_car_nums = parseCommaSep(ui.ridealongCars.Value);

    cfg.ecu_input_dir  = strtrim(ui.ecuInputDir.Value);
    cfg.ecu_concat_dir = strtrim(ui.ecuConcatDir.Value);
    cfg.ecu_format     = ui.ecuFormat.Value;
    cfg.max_overlap_s  = ui.maxOverlapS.Value;

    cfg.l180_input_dir = strtrim(ui.l180InputDir.Value);

    cfg.min_gap_s      = ui.minGapS.Value;
    cfg.min_seg_s      = ui.minSegS.Value;
    cfg.split_on_reset = ui.splitOnReset.Value;
    cfg.unique_fp      = ui.uniqueFp.Value;
    cfg.show_report    = ui.showReport.Value;

    cfg.quality_min    = ui.qualityMin.Value;
    cfg.resample_hz    = ui.resampleHz.Value;
    cfg.max_offset_s   = ui.maxOffsetS.Value;
    cfg.rpm_min        = ui.rpmMin.Value;
    cfg.dash_rpm_ch    = strtrim(ui.dashRpmCh.Value);
    cfg.ecu_rpm_ch     = strtrim(ui.ecuRpmCh.Value);
    cfg.l180_rpm_ch    = strtrim(ui.l180RpmCh.Value);
    cfg.merge_resample_hz  = ui.mergeResampleHz.Value;
    cfg.merge_max_offset_s = ui.maxOffsetS.Value;
    cfg.merge_rpm_min      = ui.rpmMin.Value;

    % Derived fields (smp_pipeline also sets these, but set here for runner)
    cfg.overwrite        = OVERWRITE;
    cfg.session          = SESSION;
    cfg.session_filter   = {SESSION};
    cfg.fix_filter       = DRIVERS;
    cfg.driver_filter    = {};
    cfg.team_filter      = {};
    cfg.split_car_filter = {};
    cfg.td_input_dir      = fullfile(cfg.root_folder, '_TeamData');
    cfg.td_hol_output_dir = fullfile(cfg.hol_dir, '_TeamData');
    % ecu_ert / l180_ert / td_ert names — defaults
    cfg.ecu_ert_names  = {'ECU_Uptime'};
    cfg.l180_ert_names = {'ECU_Uptime'};
    cfg.td_ert_names   = {'ECU_Uptime'};
    cfg.l180_ecu_format = false;
    cfg.rename_output   = true;

    run_motec_pipeline(cfg, SESSION, DRIVERS, OVERWRITE, ...
        RUN_TEAMDATA_CONCAT, RUN_ECU_CONCAT, RUN_SPLIT, RUN_PAIR, RUN_MERGE);
end


function run_launcher_compile(common, ui)
    TOP_LEVEL_DIR = valOrCommon([], common.rootDir);
    TEAM_FILTER   = {};

    opts.mode          = ui.mode.Value;
    opts.track         = valOrCommon(ui.track.Value, common.track);
    opts.session_filter= parseCommaSep(ui.sessionFilter.Value);
    opts.max_traces    = ui.maxTraces.Value;
    opts.saveCache     = ui.saveCache.Value;
    opts.verbose       = ui.verbose.Value;
    opts.dist_n_points = ui.distNPoints.Value;
    opts.dist_channel  = strtrim(ui.distChannel.Value);
    opts.save_mode     = ui.saveMode.Value;
    opts.load_all_channels = ui.loadAllChannels.Value;
    opts.concat_csv_dir    = strtrim(ui.concatCsvDir.Value);
    opts.showConcatReport  = ui.showConcatReport.Value;
    opts.br2_channel   = strtrim(ui.br2Channel.Value);
    opts.br2_protocol  = strtrim(ui.br2Protocol.Value);

    df = strtrim(ui.dateFrom.Value);
    if ~isempty(df)
        opts.date_from = datetime(df, 'InputFormat', 'yyyy-MM-dd');
    end

    season     = [];
    driver_map = [];
    alias      = [];
    channels   = [];
    if isfile(common.seasonFile)
        try
            season = smp_season_load(common.seasonFile);
        catch, end
    end

    smp_compile_event(TOP_LEVEL_DIR, TEAM_FILTER, channels, season, driver_map, alias, opts);
end


function run_launcher_report(common, ui)
    isReduced   = strcmp(ui.variant.Value, 'Reduced');
    TOP_LEVEL_DIR       = valOrCommon([], common.rootDir);
    CHANNELS_FILE       = common.channelsFile;
    EVENT_ALIAS_FILE    = fullfile(fileparts(CHANNELS_FILE), '..', 'alias', 'eventAlias.xlsx');
    DRIVER_ALIAS_FILE   = fullfile(fileparts(CHANNELS_FILE), '..', 'alias', 'driverAlias.xlsx');
    SEASON_FILE         = common.seasonFile;
    OUTPUT_DIR          = common.outputDir;
    PPTX_TEMPLATE       = common.pptxTemplate;

    pFiles = strtrim(ui.plotConfigFiles.Value);
    if isempty(pFiles)
        PLOT_CONFIG_FILES = {};
    else
        PLOT_CONFIG_FILES = strtrim(strsplit(pFiles, ','));
    end

    EVENT                = strtrim(common.event);
    TRACK                = strtrim(common.track);
    EVENT_NAME           = TRACK;
    SESSION_FILTER       = parseCommaSep(ui.sessionFilter.Value);
    TEAM_FILTER          = parseCommaSep(ui.teamFilter.Value);
    MODE                 = ui.mode.Value;
    N_WORKERS            = ui.nWorkers.Value;
    TMP_DIR              = fullfile(tempdir, 'smp_parallel');
    POLL_INTERVAL_S      = 3;
    TIMEOUT_S            = ui.timeoutS.Value;
    KEEP_WORKERS_OPEN    = ui.keepWorkersOpen.Value;
    RUN_RECOMPUTE_VCH    = ui.runRecomputeVch.Value;
    RECOMPUTE_MODE       = ui.recomputeMode.Value;
    VCH_DEBUG_PLOT       = ui.vchDebugPlot.Value;
    VCH_DEBUG_TEAM       = strtrim(ui.vchDebugTeam.Value);
    VCH_DEBUG_X          = strtrim(ui.vchDebugX.Value);
    VCH_DEBUG_Y          = parseCommaSep(ui.vchDebugY.Value);
    TARGET               = ui.target.Value;
    RUN_UPLOAD           = ui.runUpload.Value;
    BATCH_SIZE           = ui.batchSize.Value;
    OVERWRITE            = ui.overwrite.Value;
    PLOTTING             = ui.plotting.Value;
    SAVE_CACHE           = ui.saveCache.Value;
    workshop             = ui.workshop.Value;
    CREATE_PITSTOP_REPORT= ui.createPitstop.Value;

    compile_opts.mode         = ui.compileModeAdv.Value;
    compile_opts.track        = TRACK;
    compile_opts.max_traces   = ui.compileMaxTraces.Value;
    compile_opts.dist_n_points= ui.distNPoints.Value;
    compile_opts.dist_channel = strtrim(ui.distChannel.Value);
    compile_opts.verbose      = true;
    compile_opts.saveCache    = SAVE_CACHE;
    compile_opts.save_mode    = 'session';
    compile_opts.session_filter = SESSION_FILTER;
    compile_opts.load_all_channels = true;
    compile_opts.concat_csv_dir    = OUTPUT_DIR;
    compile_opts.showConcatReport  = true;
    compile_opts.br2_channel  = strtrim(ui.br2Channel.Value);
    compile_opts.br2_protocol = strtrim(ui.br2Protocol.Value);
    compile_opts.detect_pitlane = true;
    compile_opts.fcy_channel    = 'Sw_State_SC';
    df = strtrim(ui.dateFrom.Value);
    if ~isempty(df)
        compile_opts.date_from = datetime(df, 'InputFormat', 'yyyy-MM-dd');
    else
        compile_opts.date_from = datetime(1969, 4, 10);
    end

    plot_opts.fig_width  = ui.figWidth.Value;
    plot_opts.fig_height = ui.figHeight.Value;
    plot_opts.font_size  = ui.fontSize.Value;
    plot_opts.n_laps_avg = ui.nLapsAvg.Value;
    plot_opts.verbose    = true;
    plot_opts.venue      = TRACK;

    WRITE_VCH_LD = ui.writeVchLd.Value;
    VCH_LD_SUFFIX= strtrim(ui.vchLdSuffix.Value);

    run_main_report(isReduced, TOP_LEVEL_DIR, CHANNELS_FILE, EVENT_ALIAS_FILE, ...
        DRIVER_ALIAS_FILE, PLOT_CONFIG_FILES, SEASON_FILE, PPTX_TEMPLATE, OUTPUT_DIR, ...
        EVENT, TRACK, EVENT_NAME, TEAM_FILTER, SESSION_FILTER, ...
        CREATE_PITSTOP_REPORT, workshop, SAVE_CACHE, PLOTTING, ...
        MODE, N_WORKERS, TMP_DIR, POLL_INTERVAL_S, TIMEOUT_S, KEEP_WORKERS_OPEN, ...
        RUN_RECOMPUTE_VCH, RECOMPUTE_MODE, VCH_DEBUG_PLOT, VCH_DEBUG_TEAM, ...
        VCH_DEBUG_X, VCH_DEBUG_Y, TARGET, RUN_UPLOAD, BATCH_SIZE, OVERWRITE, ...
        compile_opts, plot_opts, WRITE_VCH_LD, VCH_LD_SUFFIX);
end


function run_launcher_quali_fuel(common, ui)
    TOP_LEVEL_DIR     = valOrCommon([], common.rootDir);
    CHANNELS_FILE     = common.channelsFile;
    EVENT_ALIAS_FILE  = fullfile(fileparts(CHANNELS_FILE), '..', 'alias', 'eventAlias.xlsx');
    DRIVER_ALIAS_FILE = fullfile(fileparts(CHANNELS_FILE), '..', 'alias', 'driverAlias.xlsx');
    SEASON_FILE       = common.seasonFile;

    TRACK             = valOrCommon(ui.track.Value, common.track);
    EVENT_CODE        = strtrim(ui.eventCode.Value);
    YEAR              = ui.year.Value;
    TEAM_FILTER       = parseCommaSep(ui.teamFilter.Value);
    SESSION_FILTER    = parseCommaSep(ui.sessionFilter.Value);
    BR2_PROTOCOL      = strtrim(ui.br2Protocol.Value);
    SHOW_REPORT       = ui.showReport.Value;

    compile_opts.mode          = ui.compileMode.Value;
    compile_opts.track         = TRACK;
    compile_opts.dist_n_points = ui.distNPoints.Value;
    compile_opts.dist_channel  = strtrim(ui.distChannel.Value);
    compile_opts.verbose       = ui.verbose.Value;
    compile_opts.saveCache     = ui.saveCache.Value;
    compile_opts.save_mode     = ui.saveMode.Value;
    compile_opts.session_filter= SESSION_FILTER;

    lap_slicer_opts.br2_channel  = strtrim(ui.br2Channel.Value);
    lap_slicer_opts.br2_protocol = BR2_PROTOCOL;

    run_quali_fuel(TOP_LEVEL_DIR, CHANNELS_FILE, EVENT_ALIAS_FILE, ...
        DRIVER_ALIAS_FILE, SEASON_FILE, TRACK, EVENT_CODE, YEAR, ...
        TEAM_FILTER, SESSION_FILTER, BR2_PROTOCOL, SHOW_REPORT, ...
        compile_opts, lap_slicer_opts);
end


function run_launcher_lift_coast(ui)
    event       = strtrim(ui.event.Value);
    if isempty(event)
        error('Event is required for Lift & Coast analysis.');
    end
    year        = ui.year.Value;
    session_id  = strtrim(ui.sessionId.Value);
    driver_tla  = strtrim(ui.driverTla.Value);
    fuel_rate   = ui.fuelRate.Value;
    accel       = ui.accel.Value;
    time_budget = str2double(strtrim(ui.timeBudget.Value));  % NaN if blank or 'NaN'
    ft_str      = strtrim(ui.fuelTargets.Value);
    if isempty(ft_str)
        fuel_targets = [];
    else
        fuel_targets = str2num(ft_str); %#ok<ST2NM>
    end
    auto_detect    = ui.autoDetect.Value;
    compile        = ui.compile.Value;
    config_file    = strtrim(ui.configFile.Value);
    concat_csv_dir = strtrim(ui.concatCsvDir.Value);
    br2_protocol   = strtrim(ui.br2Protocol.Value);
    rerun          = ui.rerun.Value;
    run_diagnostic = ui.runDiagnostic.Value;
    visible        = ui.visible.Value;
    debug          = ui.debug.Value;

    LiftAndCoast(event, ...
        'year',           year, ...
        'session_id',     session_id, ...
        'driver_tla',     driver_tla, ...
        'accel',          accel, ...
        'fuel_rate',      fuel_rate, ...
        'auto_detect',    auto_detect, ...
        'config_file',    config_file, ...
        'rerun',          rerun, ...
        'run_diagnostic', run_diagnostic, ...
        'time_budget',    time_budget, ...
        'fuel_targets',   fuel_targets, ...
        'visible',        visible, ...
        'debug',          debug, ...
        'compile',        compile, ...
        'concat_csv_dir', concat_csv_dir, ...
        'br2_protocol',   br2_protocol);
end


function run_launcher_db_upload(common, ui) %#ok<INUSL>
    % smp_push_to_sql expects (T, opts) where T is a flat table
    % The caller needs a cache loaded — emit a useful error if not found
    opts.table    = strtrim(ui.tableName.Value);
    opts.schema   = strtrim(ui.schema.Value);
    opts.batch    = ui.batchSize.Value;
    opts.overwrite= ui.overwrite.Value;
    opts.dry_run  = ui.dryRun.Value;

    % Attempt to load cache from rootDir
    rootDir = common.rootDir;
    if isempty(rootDir) || ~isfolder(rootDir)
        error('Set Data Root Dir in Common Config to the folder containing the compiled .mat cache.');
    end
    cache = smp_cache_load(rootDir, {});
    T = smp_flatten_stats(cache);
    smp_push_to_sql(T, opts);
end


function run_launcher_write_vch(ui)
    raw = ui.sourceFiles.Value;
    if ischar(raw), raw = {raw}; end
    % Split each element by newlines and flatten
    lines = {};
    for k = 1:numel(raw)
        parts = strsplit(raw{k}, newline);
        lines = [lines, parts(:)']; %#ok<AGROW>
    end
    SOURCE_FILES = {};
    for k = 1:numel(lines)
        p = strtrim(lines{k});
        if ~isempty(p)
            SOURCE_FILES{end+1} = p; %#ok<AGROW>
        end
    end
    if isempty(SOURCE_FILES)
        error('No source .ld files specified.');
    end
    OUTPUT_SUFFIX = strtrim(ui.outputSuffix.Value);
    OVERWRITE     = ui.overwrite.Value;
    run_write_vch(SOURCE_FILES, OUTPUT_SUFFIX, OVERWRITE);
end


%% ========================================================================
%  BROWSE HELPERS
%% ========================================================================

function onBrowseDir(~, hField)
    d = uigetdir(hField.Value, 'Select Folder');
    if ischar(d) && ~isequal(d, 0)
        hField.Value = d;
    end
end

function onBrowseFile(~, hField, filterSpec)
    if nargin < 3, filterSpec = '*.*'; end
    [f, p] = uigetfile(filterSpec, 'Select File', hField.Value);
    if ischar(f) && ~isequal(f, 0)
        hField.Value = fullfile(p, f);
    end
end

function onAddFiles(hTextArea)
    [f, p] = uigetfile('*.ld', 'Select .ld Files', 'MultiSelect', 'on');
    if isequal(f, 0), return; end
    if ischar(f), f = {f}; end
    existing = strtrim(hTextArea.Value);
    if ischar(existing), existing = {existing}; end
    newPaths = cellfun(@(x) fullfile(p, x), f, 'UniformOutput', false);
    combined = [existing; newPaths(:)];
    combined = combined(~cellfun(@isempty, combined));
    hTextArea.Value = combined;
end


%% ========================================================================
%  ADVANCED TOGGLE
%% ========================================================================

function toggleAdvanced(btn, pnl)
    if strcmp(pnl.Visible, 'off')
        pnl.Visible = 'on';
        btn.Text    = '▲  Advanced';
    else
        pnl.Visible = 'off';
        btn.Text    = '▼  Advanced';
    end
end


%% ========================================================================
%  UTILITIES
%% ========================================================================

function lbl = makeLabel(parent, txt, rowcol)
    lbl = uilabel(parent, 'Text', txt, 'HorizontalAlignment', 'right', ...
        'FontSize', 11);
    if nargin >= 3
        lbl.Layout.Row    = rowcol(1);
        lbl.Layout.Column = rowcol(2);
    end
end

function btn = makeBtn(parent, txt, row, col, callback)
    % Create button and set Layout post-construction (R2020a compatible)
    btn = uibutton(parent, 'Text', txt, 'ButtonPushedFcn', callback);
    btn.Layout.Row    = row;
    btn.Layout.Column = col;
end

function lbl = makeSectionLabel(parent, txt, row, col)
    % Section divider label — set Layout post-construction (R2020a compatible)
    lbl = uilabel(parent, 'Text', txt, 'FontWeight', 'bold');
    lbl.Layout.Row    = row;
    lbl.Layout.Column = col;
end

function c = parseCommaSep(str)
    str = strtrim(str);
    if isempty(str)
        c = {};
    else
        parts = strsplit(str, ',');
        c = strtrim(parts);
        c = c(~cellfun(@isempty, c));
    end
end

function val = valOrCommon(uiVal, commonVal)
    if ischar(uiVal)
        uiVal = strtrim(uiVal);
    end
    if isempty(uiVal)
        val = commonVal;
    else
        val = uiVal;
    end
end
