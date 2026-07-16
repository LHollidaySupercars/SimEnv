function visualizeVehicleGeometryApp(vehicle, varargin)
% VISUALIZEVEHICLEGEOMETRYAPP  Interactive app for suspension geometry visualisation
% ==================================================================================
% 18-02 Initial creation of application
% Todo|
%   Validate points to the CAD model - separate excel import selection
%   Add camber visualization to the script
%   Add anti kinematics to the script
%   Add CoG height to the script
%   Add lateral measurement to the tyre width
% Syntax:
%   visualizeVehicleGeometryApp(vehicle)
%
% Inputs:
%   vehicle - Vehicle structure with kinematics data. Must contain at minimum:
%             vehicle.ford.kinematics.front  and  vehicle.ford.kinematics.rear
%             Toyota and Chevrolet entries are optional; their buttons will be
%             greyed out if the data is missing.
%
% Tab 1 – 3D Geometry Viewer
%   • Manufacturer selector  : Ford / Toyota / Chev  (clickable toggle buttons)
%   • Checkbox               : Show Anti Lines (placeholder – not yet implemented)
%   • View buttons           : XY, XZ, YZ  (snap the camera to that plane)
%   • 3D axes with legend    : one entry per component colour group
%
% Tab 2 – Vector Angle Table
%   • Same table as the original visualizeVehicleGeometry script
%     (projection angles + complement angles for every link segment)
%
% Legend groups (one colour per group, left+right shown via solid/dashed):
%   Front Lower A-arm  │  Front Upper A-arm  │  Front Toe Rod
%   Rear  Lower A-arm  │  Rear  Upper A-arm  │  Rear  Toe Rod
%   KPI axis           │  Front Tyre         │  Rear  Tyre
%
% Notes:
%   • All vectors follow the  n×3  row convention  [x, y, z]
%   • Right-side points are mirrored:  point .* [1, -1, 1]
%   • Tyre circles are drawn in the Y-Z plane at each wheel station
%     with a fixed radius of 330 mm
%   • Anti lines show a "not yet implemented" placeholder when enabled
p = inputParser;
addRequired(p, 'vehicle');
addParameter(p, 'tyre', '');
addParameter(p, 'tyreModel', '');

parse(p, vehicle, varargin{:});
tyre = p.Results.tyre;
tyreModel = p.Results.tyreModel;
    %% ------------------------------------------------------------------ %%
    %  Validate input                                                        %
    %% ------------------------------------------------------------------ %%
    if nargin < 1 || ~isstruct(vehicle)
        error('visualizeVehicleGeometryApp: vehicle struct is required.');
    end

    TYRE_RADIUS  = 330;   % mm  – fixed tyre radius
    MANUFACTURERS = {'ford', 'toyota', 'chev'};
    MFR_LABELS    = {'Ford', 'Toyota', 'Chev'};

    % Check which manufacturers actually have data
    mfrAvailable = false(1, 3);
    for k = 1:3
        mfrAvailable(k) = isfield(vehicle, MANUFACTURERS{k}) && ...
                          isfield(vehicle.(MANUFACTURERS{k}), 'kinematics');
    end

    % Default to first available manufacturer
    activeMfr = find(mfrAvailable, 1, 'first');
    if isempty(activeMfr)
        error('visualizeVehicleGeometryApp: No valid manufacturer data found in vehicle struct.');
    end

    %% ------------------------------------------------------------------ %%
    %  App colours                                                           %
    %% ------------------------------------------------------------------ %%
    CLR = struct( ...
        'frontLower',  [0.00, 0.45, 0.74], ...   % blue
        'frontUpper',  [0.85, 0.33, 0.10], ...   % red-orange
        'frontToe',    [0.47, 0.67, 0.19], ...   % green
        'rearLower',   [0.00, 0.75, 0.75], ...   % cyan
        'rearUpper',   [0.75, 0.00, 0.75], ...   % magenta
        'rearToe',     [0.93, 0.69, 0.13], ...   % amber
        'kpi',         [0.50, 0.50, 0.50], ...   % grey
        'damper',      [0.10, 0.10, 0.10], ...   % near-black
        'tyre',        [0.20, 0.20, 0.20], ...   % dark grey
        'anti',        [1.00, 0.00, 0.00]);       % red (placeholder)

    BG   = [0.15, 0.15, 0.15];   % dark background
    PANELBG = [0.20, 0.20, 0.20];
    TXT  = [0.92, 0.92, 0.92];
    BTN_ON  = [0.30, 0.55, 0.90];
    BTN_OFF = [0.30, 0.30, 0.30];
    BTN_DIS = [0.22, 0.22, 0.22];
        DARK_SCHEME = struct(...
    'bg',       [0.15, 0.15, 0.15], ...
    'panelBg',  [0.20, 0.20, 0.20], ...
    'axBg',     [0.10, 0.10, 0.10], ...
    'txt',      [0.92, 0.92, 0.92], ...
    'grid',     [0.35, 0.35, 0.35], ...
    'btnOff',   [0.30, 0.30, 0.30]);

        LIGHT_SCHEME = struct(...
    'bg',       [0.94, 0.94, 0.94], ...
    'panelBg',  [0.85, 0.85, 0.85], ...
    'axBg',     [1.00, 1.00, 1.00], ...
    'txt',      [0.10, 0.10, 0.10], ...
    'grid',     [0.70, 0.70, 0.70], ...
    'btnOff',   [0.72, 0.72, 0.72]);

        activeScheme = DARK_SCHEME;
    %% ------------------------------------------------------------------ %%
    %  Main figure                                                           %
    %% ------------------------------------------------------------------ %%
    fig = figure( ...
        'Name',            'Vehicle Geometry Viewer', ...
        'NumberTitle',     'off', ...
        'MenuBar',         'none', ...
        'ToolBar',         'figure', ...
        'Color',           BG, ...
        'Position',        [80, 80, 1350, 780], ...
        'Resize',          'on');

    %% ------------------------------------------------------------------ %%
    %  Tab group                                                             %
    %% ------------------------------------------------------------------ %%
    tabGroup = uitabgroup(fig, ...
        'Units',    'normalized', ...
        'Position', [0, 0, 1, 1]);

    tabGeom  = uitab(tabGroup, 'Title', '3D Geometry',    'BackgroundColor', BG);
    tabTable = uitab(tabGroup, 'Title', 'Vector Angles',  'BackgroundColor', BG);

    %% ================================================================== %%
    %  TAB 1 – 3D GEOMETRY                                                  %
    %% ================================================================== %%

    % ---- control panel (left strip) ------------------------------------ %
    ctrlPanel = uipanel( ...
        'Parent',          tabGeom, ...
        'BackgroundColor', PANELBG, ...
        'BorderType',      'none', ...
        'Units',           'normalized', ...
        'Position',        [0, 0, 0.16, 1]);

    % ---- 3D axes -------------------------------------------------------- %
    ax = axes( ...
        'Parent',          tabGeom, ...
        'Color',           [0.10 0.10 0.10], ...
        'XColor',          TXT, 'YColor', TXT, 'ZColor', TXT, ...
        'GridColor',       [0.35 0.35 0.35], ...
        'GridAlpha',       0.5, ...
        'Units',           'normalized', ...
        'Position',        [0.17, 0.02, 0.81, 0.96]);
    rotate3d(ax, 'on'); 
    hold(ax, 'on');
    grid(ax, 'on');
    axis(ax, 'equal');
    xlabel(ax, 'X  [mm]  Longitudinal', 'Color', TXT);
    ylabel(ax, 'Y  [mm]  Lateral',      'Color', TXT);
    zlabel(ax, 'Z  [mm]  Vertical',     'Color', TXT);
    view(ax, 3);
    % ← ADD HERE
    hRotate = rotate3d(ax);
    hRotate.Enable = 'on';
    set(fig, 'WindowKeyPressFcn',   @handleKeyPress);
    set(fig, 'WindowKeyReleaseFcn', @handleKeyRelease);
    % ---- control layout helpers ---------------------------------------- %
    cW  = 0.84;   % control width  (normalised within panel)
    cX  = 0.08;   % control left margin
    cH  = 0.040;  % standard control height
    cY  = 0.96;   % current Y cursor (top→bottom)
    function cY = nextY(cY, gap)
        cY = cY - gap;
    end

    function h = makeLabel(txt, yPos)
        h = uicontrol('Parent', ctrlPanel, ...
            'Style',              'text', ...
            'String',             txt, ...
            'Units',              'normalized', ...
            'Position',           [cX, yPos, cW, cH], ...
            'BackgroundColor',    PANELBG, ...
            'ForegroundColor',    TXT, ...
            'FontWeight',         'bold', ...
            'FontSize',           9, ...
            'HorizontalAlignment','left');
    end

    function h = makeBtn(txt, yPos, clr, cb)
        h = uicontrol('Parent', ctrlPanel, ...
            'Style',           'pushbutton', ...
            'String',          txt, ...
            'Units',           'normalized', ...
            'Position',        [cX, yPos, cW, cH*1.1], ...
            'BackgroundColor', clr, ...
            'ForegroundColor', TXT, ...
            'FontWeight',      'bold', ...
            'FontSize',        9, ...
            'Callback',        cb);
    end

    % ---- MANUFACTURER section ------------------------------------------ %
    cY = nextY(cY, 0.005);
    makeLabel('MANUFACTURER', cY);
    cY = nextY(cY, cH + 0.005);

    mfrBtns = gobjects(1,3);
    for k = 1:3
        if mfrAvailable(k)
            clr = BTN_OFF;
        else
            clr = BTN_DIS;
        end
        mfrBtns(k) = makeBtn(MFR_LABELS{k}, cY, clr, @(s,e) selectManufacturer(k));
        cY = nextY(cY, cH + 0.008);
    end
    % highlight active
    set(mfrBtns(activeMfr), 'BackgroundColor', BTN_ON);

    % ---- VIEW section --------------------------------------------------- %
    cY = nextY(cY, 0.015);
    makeLabel('VIEW', cY);
    cY = nextY(cY, cH + 0.005);

    makeBtn('XY  (Top)',   cY, BTN_OFF, @(s,e) setView([0 90]));
    cY = nextY(cY, cH + 0.008);
    makeBtn('XZ  (Side)',  cY, BTN_OFF, @(s,e) setView([0 0]));
    cY = nextY(cY, cH + 0.008);
    makeBtn('YZ  (Front)', cY, BTN_OFF, @(s,e) setView([90 0]));
    cY = nextY(cY, cH + 0.008);
    makeBtn('3D',          cY, BTN_OFF, @(s,e) setView([]));
    cY = nextY(cY, cH + 0.015);

    % ---- ANTI LINES section -------------------------------------------- %
    makeLabel('ANTI LINES', cY);
    cY = nextY(cY, cH + 0.005);

    antiCheck = uicontrol('Parent', ctrlPanel, ...
        'Style',           'checkbox', ...
        'String',          'Show Anti Lines', ...
        'Value',           0, ...
        'Units',           'normalized', ...
        'Position',        [cX, cY, cW, cH], ...
        'BackgroundColor', PANELBG, ...
        'ForegroundColor', TXT, ...
        'FontSize',        9, ...
        'Callback',        @(s,e) toggleAnti());
cY = nextY(cY, cH + 0.015);
makeLabel('DISPLAY', cY);
cY = nextY(cY, cH + 0.005);

themeBtn = makeBtn('Light Mode', cY, BTN_OFF, @(s,e) toggleTheme());
    %% ================================================================== %%
    %  TAB 2 – VECTOR ANGLE TABLE                                           %
    %% ================================================================== %%
    tablePanel = uipanel( ...
        'Parent',          tabTable, ...
        'BackgroundColor', BG, ...
        'BorderType',      'none', ...
        'Units',           'normalized', ...
        'Position',        [0, 0, 1, 1]);

    % uitable will be populated in refreshTable()
    colNames = {'Vector', ...
        'XY Angle (°)', 'XY Complement (°)', ...
        'XZ Angle (°)', 'XZ Complement (°)', ...
        'YZ Angle (°)', 'YZ Complement (°)'};
    colWidths = {220, 100, 130, 100, 130, 100, 130};

    tbl = uitable(tablePanel, ...
        'Units',           'normalized', ...
        'Position',        [0.01, 0.01, 0.98, 0.98], ...
        'ColumnName',      colNames, ...
        'ColumnWidth',     colWidths, ...
        'RowName',         [], ...
        'FontSize',        9);

    %% ================================================================== %%
    %  State & initial render                                               %
    %% ================================================================== %%
    antiLinesOn   = false;
    antiHandles   = [];   % graphics handles for the placeholder anti lines
    antiAnnotation = [];  % annotation handle

    refreshGeometry();
    refreshTable();

    %% ================================================================== %%
    %  CALLBACKS                                                            %
    %% ================================================================== %%

    function selectManufacturer(idx)
        if ~mfrAvailable(idx)
            return;  % greyed-out button — do nothing
        end
        activeMfr = idx;
        % Update button colours
        for j = 1:3
            if mfrAvailable(j)
                set(mfrBtns(j), 'BackgroundColor', BTN_OFF);
            end
        end
        set(mfrBtns(activeMfr), 'BackgroundColor', BTN_ON);
        refreshGeometry();
        refreshTable();
    end

    function setView(azEl)
        if isempty(azEl)
            view(ax, 3);
        else
            view(ax, azEl(1), azEl(2));
        end
    end

    function toggleAnti()
        antiLinesOn = logical(get(antiCheck, 'Value'));
        if antiLinesOn
            drawAntiPlaceholder();
        else
            clearAntiPlaceholder();
        end
    end
    function handleKeyPress(~, evt)
        if strcmp(evt.Key, 'control')
            hRotate.Enable = 'off';
            hPan = pan(fig);
            hPan.Enable = 'on';
        end
    end

    function handleKeyRelease(~, evt)
        if strcmp(evt.Key, 'control')
            pan(fig, 'off');
            hRotate.Enable = 'on';
        end
    end
    function toggleTheme()
        if isequal(activeScheme, DARK_SCHEME)
            activeScheme = LIGHT_SCHEME;
            set(themeBtn, 'String', 'Dark Mode');
        else
            activeScheme = DARK_SCHEME;
            set(themeBtn, 'String', 'Light Mode');
        end

        s = activeScheme;

        % Figure and tabs
        set(fig,       'Color', s.bg);
        set(tabGeom,   'BackgroundColor', s.bg);
        set(tabTable,  'BackgroundColor', s.bg);
        set(ctrlPanel, 'BackgroundColor', s.panelBg);
        set(tablePanel,'BackgroundColor', s.bg);

        % Axes
        set(ax, 'Color',      s.axBg, ...
                'XColor',     s.txt, ...
                'YColor',     s.txt, ...
                'ZColor',     s.txt, ...
                'GridColor',  s.grid);

        % Legend
        leg = ax.Legend;
        if ~isempty(leg)
            set(leg, 'TextColor', s.txt, ...
                     'Color',     s.panelBg, ...
                     'EdgeColor', s.grid);
        end

        % Title
        set(get(ax, 'Title'), 'Color', s.txt);
        set(get(ax, 'XLabel'), 'Color', s.txt);
        set(get(ax, 'YLabel'), 'Color', s.txt);
        set(get(ax, 'ZLabel'), 'Color', s.txt);

        % All uicontrols inside ctrlPanel
        kids = findall(ctrlPanel, 'Type', 'uicontrol');
        for k = 1:numel(kids)
            style = get(kids(k), 'Style');
            if strcmp(style, 'text') || strcmp(style, 'checkbox')
                set(kids(k), 'BackgroundColor', s.panelBg, 'ForegroundColor', s.txt);
            elseif strcmp(style, 'pushbutton')
                % Don't overwrite the active manufacturer button highlight
                if kids(k) == mfrBtns(activeMfr)
                    continue;
                end
                set(kids(k), 'BackgroundColor', s.btnOff, 'ForegroundColor', s.txt);
            end
        end

        % Update BTN_OFF so future buttons render correctly
        BTN_OFF = s.btnOff;
    end
    %% ================================================================== %%
    %  GEOMETRY EXTRACTION                                                  %
    %% ================================================================== %%

    function pts = extractPoints(mfr)
        % Returns a struct of all pickup points for both axles, both sides.
        % All points are  1×3  row vectors.
        kin = vehicle.(mfr).kinematics;

        % ---- FRONT ---- %
        pts.fl.lower.aft  = kin.front.lowerAArm.aft(:)';
        pts.fl.lower.bj   = kin.front.lowerAArm.ballJoint(:)';
        pts.fl.lower.fore = kin.front.lowerAArm.fore(:)';
        pts.fl.upper.aft  = kin.front.upperAArm.aft(:)';
        pts.fl.upper.bj   = kin.front.upperAArm.ballJoint(:)';
        pts.fl.upper.fore = kin.front.upperAArm.fore(:)';
        pts.fl.toe.in     = kin.front.steeringRack.toeRodChassis(:)';
        pts.fl.toe.out    = kin.front.steeringRack.toeRodUpright(:)';
        pts.fl.damper.lo  = kin.front.rocker.damperPickup(:)';
        pts.fl.damper.up  = kin.front.damper.chassisPickup(:)';
        pts.fl.cp         = [0, 0, 0];

        % Mirror for right side (negate Y)
        M = [1, -1, 1];
        pts.fr.lower.aft  = pts.fl.lower.aft  .* M;
        pts.fr.lower.bj   = pts.fl.lower.bj   .* M;
        pts.fr.lower.fore = pts.fl.lower.fore  .* M;
        pts.fr.upper.aft  = pts.fl.upper.aft   .* M;
        pts.fr.upper.bj   = pts.fl.upper.bj    .* M;
        pts.fr.upper.fore = pts.fl.upper.fore  .* M;
        pts.fr.toe.in     = pts.fl.toe.in      .* M;
        pts.fr.toe.out    = pts.fl.toe.out     .* M;
        pts.fr.damper.lo  = pts.fl.damper.lo   .* M;
        pts.fr.damper.up  = pts.fl.damper.up   .* M;
        
        if isfield(kin.front, 'correctedContactPatch') && ...
                ~isempty(kin.front.correctedContactPatch) && strcmp(tyre, 'correctedContactPatch')
            temp = size(kin.front.correctedContactPatch);
            temp = floor(temp/2);
            pts.fl.cp = kin.front.correctedContactPatch(10, (temp - 1: temp + 1));
        else
            pts.fl.cp = [kin.front.lowerAArm.ballJoint(1), ...
                         kin.front.lowerAArm.ballJoint(2), 0];
        end
        pts.fr.cp        = pts.fl.cp          .* M;
        % ---- REAR ---- %
        pts.rl.lower.aft  = kin.rear.lowerAArm.aft(:)';
        pts.rl.lower.bj   = kin.rear.lowerAArm.ballJoint(:)';
        pts.rl.lower.fore = kin.rear.lowerAArm.fore(:)';
        pts.rl.upper.aft  = kin.rear.upperAArm.aft(:)';
        pts.rl.upper.bj   = kin.rear.upperAArm.ballJoint(:)';
        pts.rl.upper.fore = kin.rear.upperAArm.fore(:)';
        pts.rl.toe.in     = kin.rear.lowerAArm.toeRodChassis(:)';
        pts.rl.toe.out    = kin.rear.lowerAArm.toeRodUpright(:)';
        pts.rl.damper.lo  = kin.rear.rocker.damperPickup(:)';
        pts.rl.damper.up  = kin.rear.damper.chassisPickup(:)';

        % rear contact patch – use correctedContactPatch if available
        if isfield(kin.rear, 'correctedContactPatch') && ...
                ~isempty(kin.rear.correctedContactPatch) && strcmp(tyre, 'correctedContactPatch')
            pts.rl.cp = kin.rear.correctedContactPatch(10, :);
        else
            pts.rl.cp = [kin.rear.lowerAArm.ballJoint(1), ...
                         kin.rear.lowerAArm.ballJoint(2), 0];
        end

        pts.rr.lower.aft  = pts.rl.lower.aft  .* M;
        pts.rr.lower.bj   = pts.rl.lower.bj   .* M;
        pts.rr.lower.fore = pts.rl.lower.fore  .* M;
        pts.rr.upper.aft  = pts.rl.upper.aft   .* M;
        pts.rr.upper.bj   = pts.rl.upper.bj    .* M;
        pts.rr.upper.fore = pts.rl.upper.fore  .* M;
        pts.rr.toe.in     = pts.rl.toe.in      .* M;
        pts.rr.toe.out    = pts.rl.toe.out     .* M;
        pts.rr.damper.lo  = pts.rl.damper.lo   .* M;
        pts.rr.damper.up  = pts.rl.damper.up   .* M;
        pts.rr.cp         = pts.rl.cp          .* M;
    end

    %% ================================================================== %%
    %  DRAW GEOMETRY                                                        %
    %% ================================================================== %%

    function refreshGeometry()
        cla(ax);
        mfr = MANUFACTURERS{activeMfr};
        pts = extractPoints(mfr);

        % ---- helper: plot a 3-point A-arm (aft→bj→fore) --------------- %
        function h = plotArm(p1, p2, p3, clr, ls)
            h = plot3(ax, [p1(1),p2(1),p3(1)], ...
                          [p1(2),p2(2),p3(2)], ...
                          [p1(3),p2(3),p3(3)], ...
                ls, 'Color', clr, 'LineWidth', 2, 'HandleVisibility', 'off');
        end

        % ---- helper: plot a 2-point link -------------------------------- %
        function h = plotLink(p1, p2, clr, ls, lw)
            h = plot3(ax, [p1(1),p2(1)], [p1(2),p2(2)], [p1(3),p2(3)], ...
                ls, 'Color', clr, 'LineWidth', lw, 'HandleVisibility', 'off');
        end

        % ---- helper: plot KPI axis (LBJ → UBJ) ------------------------- %
        function plotKPI(lbj, ubj, ls)
            plot3(ax, [lbj(1),ubj(1)], [lbj(2),ubj(2)], [lbj(3),ubj(3)], ...
                ls, 'Color', CLR.kpi, 'LineWidth', 2.5, 'HandleVisibility', 'off');
        end


function plotTyre(cp, r, clr, side, axle)
    % Wheel centre is directly above contact patch
    if strcmp(tyre, 'correctedContactPatch')
        wc = cp + [0, 0, 0];
    else
        wc = cp + [0, 0, r];
    end
    
    % Get camber and toe angles for this axle (index 10)
    mfr = MANUFACTURERS{activeMfr};
    camberDeg = vehicle.(mfr).kinematics.(axle).camberSweep.camberCorrected(10);
    toeDeg    = vehicle.(mfr).kinematics.(axle).toeSweep.toe(10);
    
    % Convert to radians
    camberRad = deg2rad(camberDeg);
    toeRad    = deg2rad(toeDeg);
    
    % Tyre width (inner to outer edge)
    if strcmp(side, 'right')
        if strcmp(tyreModel, 'CAD_REF')
            tyreWidthInside = vehicle.ford.kinematics.rear.tyreGeometryInside(2);
            tyreWidthOutside = vehicle.ford.kinematics.rear.tyreGeometryOutside(2);
        else 
            tyreWidthInside = -300;
            tyreWidthOutside = -300;
        end
    else 
        if strcmp(tyreModel, 'CAD_REF')
            tyreWidthInside = vehicle.ford.kinematics.rear.tyreGeometryInside(2) * -1;
            tyreWidthOutside = vehicle.ford.kinematics.rear.tyreGeometryOutside(2) * -1;
        else 
            tyreWidthInside = 300;
            tyreWidthOutside = 300;
        end
        camberRad = camberRad * -1;
        toeRad = toeRad * -1; 
    end
    
    % Generate circle in local XZ plane (wheel rotates in this plane)
    theta = linspace(0, 2*pi, 72);
    x_local = r * cos(theta);
    z_local = r * sin(theta);
    y_local = zeros(size(theta));
    
    % Stack into 3×72 matrix for rotation
    pts_local = [x_local; y_local; z_local];
    
    % Rotation matrix for camber (about X-axis)
    R_camber = [1,  0,              0;
                0,  cos(camberRad), -sin(camberRad);
                0,  sin(camberRad),  cos(camberRad)];
    
    % Rotation matrix for toe (about Z-axis)
    R_toe = [cos(toeRad), -sin(toeRad), 0;
             sin(toeRad),  cos(toeRad), 0;
             0,            0,           1];
    
    % Combined rotation
    R_total = R_toe * R_camber;
    
    % Apply rotations: first camber, then toe
    pts_rotated = R_total * pts_local;
    
    % Translate to wheel centre position (OUTER circle at contact patch)
    xx_outer = wc(1) + pts_rotated(1, :);
    yy_outer = wc(2) + pts_rotated(2, :);
    zz_outer = wc(3) + pts_rotated(3, :);
    
    % Calculate lateral offset vector in rotated wheel coordinate system
    % The wheel's lateral axis is the Y-axis after rotation
    lateral_axis = R_total * [0; 1; 0];  % rotated Y direction
    offset_vec = -(tyreWidthOutside+tyreWidthInside) * lateral_axis;
    
    % INNER circle: offset along the rotated lateral axis
    xx_inner = xx_outer + offset_vec(1);
    yy_inner = yy_outer + offset_vec(2);
    zz_inner = zz_outer + offset_vec(3);
    
    % Plot outer circle (at contact patch)
    plot3(ax, xx_outer, yy_outer, zz_outer, '-', 'Color', [1,0,0], 'LineWidth', 1.5, 'HandleVisibility', 'off');
    
    % Plot inner circle (offset by tyre width along rotated lateral axis)
    plot3(ax, xx_inner, yy_inner, zz_inner, '-', 'Color', clr, 'LineWidth', 1.5, 'HandleVisibility', 'off');
    
    % Connect corresponding points with straight lines (tyre sidewall)
    % Use every 2nd point to avoid visual clutter (36 lines from 72 points)
    for k = 1:2:length(theta)
        plot3(ax, [xx_outer(k), xx_inner(k)], ...
                  [yy_outer(k), yy_inner(k)], ...
                  [zz_outer(k), zz_inner(k)], ...
            '-', 'Color', clr, 'LineWidth', 0.5, 'HandleVisibility', 'off');
    end
end
        % ================================================================ %
        %  FRONT LEFT                                                       %
        % ================================================================ %
        plotArm(pts.fl.lower.aft, pts.fl.lower.bj, pts.fl.lower.fore, CLR.frontLower, '-');
        plotArm(pts.fl.upper.aft, pts.fl.upper.bj, pts.fl.upper.fore, CLR.frontUpper, '-');
        plotLink(pts.fl.toe.in,    pts.fl.toe.out,  CLR.frontToe,   '-', 2);
        plotLink(pts.fl.damper.lo, pts.fl.damper.up, CLR.damper,    '-', 2.5);
        plotKPI(pts.fl.lower.bj,  pts.fl.upper.bj, '-');
        plotTyre(pts.fl.cp, TYRE_RADIUS, CLR.tyre, 'left', 'front');

        % ================================================================ %
        %  FRONT RIGHT                                                      %
        % ================================================================ %
        plotArm(pts.fr.lower.aft, pts.fr.lower.bj, pts.fr.lower.fore, CLR.frontLower, '--');
        plotArm(pts.fr.upper.aft, pts.fr.upper.bj, pts.fr.upper.fore, CLR.frontUpper, '--');
        plotLink(pts.fr.toe.in,    pts.fr.toe.out,  CLR.frontToe,   '--', 2);
        plotLink(pts.fr.damper.lo, pts.fr.damper.up, CLR.damper,    '--', 2.5);
        plotKPI(pts.fr.lower.bj,  pts.fr.upper.bj, '--');
        plotTyre(pts.fr.cp, TYRE_RADIUS, CLR.tyre, 'right', 'front');

        % ================================================================ %
        %  REAR LEFT                                                        %
        % ================================================================ %
        plotArm(pts.rl.lower.aft, pts.rl.lower.bj, pts.rl.lower.fore, CLR.rearLower, '-');
        plotArm(pts.rl.upper.aft, pts.rl.upper.bj, pts.rl.upper.fore, CLR.rearUpper, '-');
        plotLink(pts.rl.toe.in,    pts.rl.toe.out,  CLR.rearToe,    '-', 2);
        plotLink(pts.rl.damper.lo, pts.rl.damper.up, CLR.damper,    '-', 2.5);
        plotKPI(pts.rl.lower.bj,  pts.rl.upper.bj, '-');
        plotTyre(pts.rl.cp, TYRE_RADIUS, CLR.tyre, 'left', 'rear');

        % ================================================================ %
        %  REAR RIGHT                                                       %
        % ================================================================ %
        plotArm(pts.rr.lower.aft, pts.rr.lower.bj, pts.rr.lower.fore, CLR.rearLower, '--');
        plotArm(pts.rr.upper.aft, pts.rr.upper.bj, pts.rr.upper.fore, CLR.rearUpper, '--');
        plotLink(pts.rr.toe.in,    pts.rr.toe.out,  CLR.rearToe,    '--', 2);
        plotLink(pts.rr.damper.lo, pts.rr.damper.up, CLR.damper,    '--', 2.5);
        plotKPI(pts.rr.lower.bj,  pts.rr.upper.bj, '--');
        plotTyre(pts.rr.cp, TYRE_RADIUS, CLR.tyre, 'right', 'rear');

        % ================================================================ %
        %  LEGEND  (one proxy per colour group, solid line)                 %
        % ================================================================ %
        legendEntries = [ ...
            line(ax, nan, nan, nan, 'Color', CLR.frontLower, 'LineWidth', 2,   'DisplayName', 'Front Lower A-arm'), ...
            line(ax, nan, nan, nan, 'Color', CLR.frontUpper, 'LineWidth', 2,   'DisplayName', 'Front Upper A-arm'), ...
            line(ax, nan, nan, nan, 'Color', CLR.frontToe,   'LineWidth', 2,   'DisplayName', 'Front Toe Rod'), ...
            line(ax, nan, nan, nan, 'Color', CLR.rearLower,  'LineWidth', 2,   'DisplayName', 'Rear Lower A-arm'), ...
            line(ax, nan, nan, nan, 'Color', CLR.rearUpper,  'LineWidth', 2,   'DisplayName', 'Rear Upper A-arm'), ...
            line(ax, nan, nan, nan, 'Color', CLR.rearToe,    'LineWidth', 2,   'DisplayName', 'Rear Toe Rod'), ...
            line(ax, nan, nan, nan, 'Color', CLR.kpi,        'LineWidth', 2.5, 'DisplayName', 'KPI Axis'), ...
            line(ax, nan, nan, nan, 'Color', CLR.damper,     'LineWidth', 2.5, 'DisplayName', 'Damper'), ...
            line(ax, nan, nan, nan, 'Color', CLR.tyre,       'LineWidth', 1.5, 'DisplayName', 'Tyre') ...
        ];

        leg = legend(ax, legendEntries, 'Location', 'best', ...
            'TextColor', TXT, 'Color', PANELBG, 'EdgeColor', [0.4 0.4 0.4]);

        title(ax, sprintf('%s Suspension Geometry', upper(MANUFACTURERS{activeMfr})), ...
            'Color', TXT, 'FontSize', 11);

        % Redraw anti placeholder if it was on
        if antiLinesOn
            drawAntiPlaceholder();
        end
    end

    %% ================================================================== %%
    %  ANTI LINES PLACEHOLDER                                               %
    %% ================================================================== %%

    function drawAntiPlaceholder()
        clearAntiPlaceholder();
        mfr = MANUFACTURERS{activeMfr};
        pts = extractPoints(mfr);

        % Dummy IC point  (roughly where anti-dive IC might be, for illustration)
        % Front: project from contact patch ~2000 mm forward and 200 mm up
        % Rear:  project from contact patch ~2000 mm rearward and 200 mm up
        frontIC_L = pts.fl.cp + [-2000, 0, 200];
        frontIC_R = pts.fr.cp + [-2000, 0, 200];
        rearIC_L  = pts.rl.cp + [ 2000, 0, 200];
        rearIC_R  = pts.rr.cp + [ 2000, 0, 200];

        antiHandles(1) = plot3(ax, ...
            [pts.fl.cp(1), frontIC_L(1)], ...
            [pts.fl.cp(2), frontIC_L(2)], ...
            [pts.fl.cp(3), frontIC_L(3)], ...
            '--', 'Color', CLR.anti, 'LineWidth', 1.5, 'HandleVisibility', 'off');

        antiHandles(2) = plot3(ax, ...
            [pts.fr.cp(1), frontIC_R(1)], ...
            [pts.fr.cp(2), frontIC_R(2)], ...
            [pts.fr.cp(3), frontIC_R(3)], ...
            '--', 'Color', CLR.anti, 'LineWidth', 1.5, 'HandleVisibility', 'off');

        antiHandles(3) = plot3(ax, ...
            [pts.rl.cp(1), rearIC_L(1)], ...
            [pts.rl.cp(2), rearIC_L(2)], ...
            [pts.rl.cp(3), rearIC_L(3)], ...
            '--', 'Color', CLR.anti, 'LineWidth', 1.5, 'HandleVisibility', 'off');

        antiHandles(4) = plot3(ax, ...
            [pts.rr.cp(1), rearIC_R(1)], ...
            [pts.rr.cp(2), rearIC_R(2)], ...
            [pts.rr.cp(3), rearIC_R(3)], ...
            '--', 'Color', CLR.anti, 'LineWidth', 1.5, 'HandleVisibility', 'off');

        % IC marker dots
        allIC = [frontIC_L; frontIC_R; rearIC_L; rearIC_R];
        antiHandles(5) = plot3(ax, allIC(:,1), allIC(:,2), allIC(:,3), ...
            'o', 'Color', CLR.anti, 'MarkerFaceColor', CLR.anti, ...
            'MarkerSize', 6, 'HandleVisibility', 'off');

        % Proxy for legend
        antiHandles(6) = line(ax, nan, nan, nan, ...
            'Color', CLR.anti, 'LineStyle', '--', 'LineWidth', 1.5, ...
            'DisplayName', 'Anti Lines  ⚠ NOT IMPLEMENTED');

        % Add a text annotation on the axes
        antiAnnotation = text(ax, ...
            mean(ax.XLim), mean(ax.YLim), max(ax.ZLim) * 0.85, ...
            '⚠  Anti Lines: Not Yet Implemented', ...
            'Color',              CLR.anti, ...
            'FontSize',           10, ...
            'FontWeight',         'bold', ...
            'HorizontalAlignment','center', ...
            'HandleVisibility',   'off');

        legend(ax, 'Location', 'best');
    end

    function clearAntiPlaceholder()
        for k = 1:numel(antiHandles)
            if ishandle(antiHandles(k))
                delete(antiHandles(k));
            end
        end
        antiHandles = [];
        if ~isempty(antiAnnotation) && ishandle(antiAnnotation)
            delete(antiAnnotation);
            antiAnnotation = [];
        end
    end

    %% ================================================================== %%
    %%                          ANGLE TABLE                               %%
    %% ================================================================== %%

    function refreshTable()
        mfr = MANUFACTURERS{activeMfr};
        pts = extractPoints(mfr);

        function angles = calcAngles(inboard, outboard)
            vec = outboard - inboard;
            X = vec(1); Y = vec(2); Z = vec(3);
            angles = [atan2d(X, Y), atan2d(X, Z), atan2d(Y, Z)];
        end

        REF = 90;
        names = {};
        aData = [];
        cData = [];

        function addRow(name, p1, p2)
            a = calcAngles(p1, p2);
            names{end+1, 1} = name;
            aData(end+1, :) = a;
            cData(end+1, :) = REF - abs(a);
        end

        % Front Lower
        addRow('Front Lower Aft→Ball  Left',  pts.fl.lower.aft,  pts.fl.lower.bj);
        addRow('Front Lower Fore→Ball Left',  pts.fl.lower.fore, pts.fl.lower.bj);
        addRow('Front Lower Aft→Ball  Right', pts.fr.lower.aft,  pts.fr.lower.bj);
        addRow('Front Lower Fore→Ball Right', pts.fr.lower.fore, pts.fr.lower.bj);

        % Front Upper
        addRow('Front Upper Aft→Ball  Left',  pts.fl.upper.aft,  pts.fl.upper.bj);
        addRow('Front Upper Fore→Ball Left',  pts.fl.upper.fore, pts.fl.upper.bj);
        addRow('Front Upper Aft→Ball  Right', pts.fr.upper.aft,  pts.fr.upper.bj);
        addRow('Front Upper Fore→Ball Right', pts.fr.upper.fore, pts.fr.upper.bj);

        % Front Tie Rod
        addRow('Front Tie Rod Left',  pts.fl.toe.in, pts.fl.toe.out);
        addRow('Front Tie Rod Right', pts.fr.toe.in, pts.fr.toe.out);

        % Front Damper
        addRow('Front Damper Left',  pts.fl.damper.lo, pts.fl.damper.up);
        addRow('Front Damper Right', pts.fr.damper.lo, pts.fr.damper.up);

        % Rear Lower
        addRow('Rear Lower Aft→Ball  Left',  pts.rl.lower.aft,  pts.rl.lower.bj);
        addRow('Rear Lower Fore→Ball Left',  pts.rl.lower.fore, pts.rl.lower.bj);
        addRow('Rear Lower Aft→Ball  Right', pts.rr.lower.aft,  pts.rr.lower.bj);
        addRow('Rear Lower Fore→Ball Right', pts.rr.lower.fore, pts.rr.lower.bj);

        % Rear Upper
        addRow('Rear Upper Aft→Ball  Left',  pts.rl.upper.aft,  pts.rl.upper.bj);
        addRow('Rear Upper Fore→Ball Left',  pts.rl.upper.fore, pts.rl.upper.bj);
        addRow('Rear Upper Aft→Ball  Right', pts.rr.upper.aft,  pts.rr.upper.bj);
        addRow('Rear Upper Fore→Ball Right', pts.rr.upper.fore, pts.rr.upper.bj);

        % Rear Toe Rod
        addRow('Rear Toe Rod Left',  pts.rl.toe.in, pts.rl.toe.out);
        addRow('Rear Toe Rod Right', pts.rr.toe.in, pts.rr.toe.out);

        % Rear Damper
        addRow('Rear Damper Left',  pts.rl.damper.lo, pts.rl.damper.up);
        addRow('Rear Damper Right', pts.rr.damper.lo, pts.rr.damper.up);

        % Build cell array for uitable
        tableData = [names, ...
            num2cell(round(aData(:,1),2)), num2cell(round(cData(:,1),2)), ...
            num2cell(round(aData(:,2),2)), num2cell(round(cData(:,2),2)), ...
            num2cell(round(aData(:,3),2)), num2cell(round(cData(:,3),2))];

        set(tbl, 'Data', tableData);
    end

end