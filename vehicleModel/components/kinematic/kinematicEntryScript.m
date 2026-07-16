%% ========================================================================
%  kinematicSweep.m
%  Entry script for full vehicle kinematic analysis — GEN3
%
%  DEPENDENCY ORDER (each section requires the one above it):
%
%  0. Initialisation       — load CAD parameters, clear workspace
%  1. Shim / Clevis setup  — apply pickup point offsets from hardware config
%  2. Rear sweep           — camber, UBJ compensation, toe, tyre, RC, damper, pot, LUT
%  3. Front sweep          — camber, camber shims, toe (steering surface), tyre, RC, damper, pot, LUT
%  4. Anti geometry        — requires correctedContactPatch on BOTH axles (done last)
%  5. Debug plots          — plotKinematicsDebug (optional, comment out to skip)
%  6. Export               — exportKinematicsToExcel
%
%  NOTE: Run this script from scratch each time (clear all at top).
%        Do NOT run sections individually — the vehicle struct is built
%        sequentially and each section depends on the one above it.
% ========================================================================

clear all; close all; clc;

%% ========================================================================
%  0. INITIALISATION
% ========================================================================

manufacturer = 'ford';
fprintf('=================================================\n');
fprintf('  GEN3 Kinematic Sweep\n');
fprintf('=================================================\n\n');
fprintf('[0] Loading CAD parameters...\n');

GEN3_KinematicParameters      % populates vehicle struct from CAD

POS = containers.Map();        % pickup position selector map

%% ========================================================================
%  1. SHIM / CLEVIS CONFIGURATION
%     Apply hardware offsets to chassis pickup points before any solving.
%     Shim vectors: [1mm | 1.5mm | 2mm | 5mm] — set 1 to use, 0 to skip.
% ========================================================================

fprintf('[1] Applying shim / clevis offsets...\n');

% ---- FRONT upright POS slot ----
POS('FRONT_UBJ_UPRIGHT_POS') = 3;

% Front lower fore
POS('FLF_POS') = 3;
vehicle = clevisOffset(vehicle, 'ford.kinematics.front.lowerAArm.fore', ...
    [1, 0, 0, 0], 'front');   % [1mm, 1.5mm, 2mm, 5mm]

% Front lower aft
POS('FLA_POS') = 3;
vehicle = clevisOffset(vehicle, 'ford.kinematics.front.lowerAArm.aft', ...
    [1, 0, 0, 0], 'front');

% Front upper fore
POS('FUF_POS') = 3;
vehicle = clevisOffset(vehicle, 'ford.kinematics.front.upperAArm.fore', ...
    [1, 0, 0, 0], 'front');

% Front upper aft
POS('FUA_POS') = 3;
vehicle = clevisOffset(vehicle, 'ford.kinematics.front.upperAArm.aft', ...
    [1, 0, 0, 0], 'front');

% ---- REAR upright POS slot ----
POS('REAR_UBJ_UPRIGHT_POS') = 3;

% Rear lower fore
POS('RLF_POS') = 3;
vehicle = clevisOffset(vehicle, 'ford.kinematics.rear.lowerAArm.fore', ...
    [0, 0, 0, 0], 'rear');

% Rear lower aft
POS('RLA_POS') = 3;
vehicle = clevisOffset(vehicle, 'ford.kinematics.rear.lowerAArm.aft', ...
    [0, 0, 0, 0], 'rear');

% Rear upper fore
POS('RUF_POS') = 3;
vehicle = clevisOffset(vehicle, 'ford.kinematics.rear.upperAArm.fore', ...
    [0, 0, 0, 0], 'rear');

% Rear upper aft
POS('RUA_POS') = 3;
vehicle = clevisOffset(vehicle, 'ford.kinematics.rear.upperAArm.aft', ...
    [0, 0, 0, 0], 'rear');

% Apply POS slot offsets to both axles
vehicle = clevisPOSOffset(vehicle, manufacturer, POS, 'front');
vehicle = clevisPOSOffset(vehicle, manufacturer, POS, 'rear');

fprintf('    Shim / clevis offsets applied.\n\n');

%% ========================================================================
%  2. REAR AXLE SWEEP
% ========================================================================

fprintf('[2] Rear axle sweep...\n');
axle = 'rear';
rearCamberShims = [1, 1, 0];   % shims active for rear upper A-arm compensation

% --- 2a. Initial camber solve (establishes thetaL range for damper sweep) ---
fprintf('    [2a] Initial camber solve...\n');
vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle);

% --- 2b. Initial damper travel (uses thetaL from camber solve to set sweep range) ---
fprintf('    [2b] Damper travel (initial — sets thetaL sweep range)...\n');
vehicle = solveDamperTravel(vehicle, 'manufacturer', manufacturer, 'axle', axle);

% --- 2c. Upper A-arm compensation (corrects arm length for camber shims / CAD error) ---
fprintf('    [2c] Upper A-arm compensation...\n');
radiiOffset = rearAArmCompensation(vehicle, manufacturer, axle, rearCamberShims, 'CAD_ERROR', true);
vehicle = threeSphereUpperAArm(vehicle, manufacturer, 'axle', axle, ...
    'newRadii', radiiOffset, 'geometrySystem', 'extendAArm', 'plotResults', false);

% --- 2d. UBJ length correction (adjusts UBJ-LBJ distance to match upright POS) ---
fprintf('    [2d] UBJ to LBJ length correction...\n');
radiiOffset = getOffset(vehicle, manufacturer, POS, axle);
vehicle = threeSphereUpperAArm(vehicle, manufacturer, 'axle', axle, ...
    'newRadii', radiiOffset, 'geometrySystem', 'extendUBJ', 'plotResults', false);

% --- 2e. Final camber solve (on corrected geometry, same thetaL range) ---
fprintf('    [2e] Final camber solve (corrected geometry)...\n');
camberPreCorrection = vehicle.(manufacturer).kinematics.(axle).camberSweep.camber;
% vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
%     'thetaL_range', vehicle.(manufacturer).kinematics.(axle).camberSweep.thetaL);

vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
    'thetaL_range', vehicle.(manufacturer).kinematics.(axle).damper.thetaL);% Store pre-correction camber as 'corrected' reference
vehicle.(manufacturer).kinematics.(axle).camberSweep.camberCorrected = camberPreCorrection;

% --- 2f. Toe sweep ---
fprintf('    [2f] Toe sweep...\n');
vehicle = solveWheelToe(vehicle, 'manufacturer', manufacturer, 'axle', axle);

% --- 2g. Contact patch (rigid tyre centre, from KPI axis) ---
fprintf('    [2g] Contact patch (tyre centre)...\n');
vehicle = offsetInPerpendicularPlane(vehicle, manufacturer, axle, 'contactChoice', 'tyreCentre');

% --- 2h. Roll centre ---
fprintf('    [2h] Roll centre sweep...\n');
vehicle = calculateRollCenter(vehicle, 'manufacturer', manufacturer, 'axle', axle);

% --- 2i. Final damper travel (on compensated wheel centre) ---
fprintf('    [2i] Damper travel (compensated geometry)...\n');
vehicle = solveDamperTravel(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
    'wheelCentre', 'compensated');

% --- 2j. Rotary pot travel ---
fprintf('    [2j] Rotary pot travel...\n');
vehicle = solveRotaryPotTravel(vehicle, 'manufacturer', manufacturer, 'axle', axle);

% --- 2k. Pot to damper LUT ---
fprintf('    [2k] Pot to damper LUT...\n');
vehicle = buildPotToDamperLUT(vehicle, 'manufacturer', manufacturer, 'axle', axle);

fprintf('    Rear axle sweep complete.\n\n');

%% ========================================================================
%  3. FRONT AXLE SWEEP
% ========================================================================

fprintf('[3] Front axle sweep...\n');
axle = 'front';

% Front camber shim stack: [5219=1.016mm | 5220=1.600mm | 5221=2.540mm | 5222=5.000mm]
frontCamberShimStack = [1, 1, 1, 0];

% --- 3a. Initial camber solve ---
fprintf('    [3a] Camber solve...\n');
vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle);

% --- 3b. Camber shim offset (shifts UBJ lateral position) ---
fprintf('    [3b] Camber shim offset...\n');
vehicle = camberOffset(vehicle, frontCamberShimStack, manufacturer, axle);

% --- 3c. Toe sweep (includes full steering surface — rows: wheel travel, cols: steering) ---
fprintf('    [3c] Toe sweep (steering surface)...\n');
toeFidelity = length(vehicle.(manufacturer).kinematics.rear.camberSweep.thetaL);
vehicle = solveWheelToe(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
    'isSteeringAngle', true, 'fidelity', toeFidelity);

% --- 3d. Contact patch — iterate over all steering positions ---
fprintf('    [3d] Contact patch (tyre centre, all steering positions)...\n');
frontToeSize = size(vehicle.(manufacturer).kinematics.(axle).toeSweep.toe);
nSteerSteps  = frontToeSize(2);
for i = 1:nSteerSteps
    vehicle = offsetInPerpendicularPlane(vehicle, manufacturer, axle, ...
        'contactChoice', 'tyreCentre', 'toeIndex', i);
end

% --- 3e. Roll centre (zero-steer / toeIndex = 1) ---
fprintf('    [3e] Roll centre sweep...\n');
vehicle = calculateRollCenter(vehicle, 'manufacturer', manufacturer, 'axle', axle);

% --- 3f. Damper travel ---
fprintf('    [3f] Damper travel...\n');
vehicle = solveDamperTravel(vehicle, 'manufacturer', manufacturer, 'axle', axle, ...
    'wheelCentre', 'compensated');

% --- 3g. Rotary pot travel ---
fprintf('    [3g] Rotary pot travel...\n');
vehicle = solveRotaryPotTravel(vehicle, 'manufacturer', manufacturer, 'axle', axle);

% --- 3h. Pot to damper LUT ---
fprintf('    [3h] Pot to damper LUT...\n');
vehicle = buildPotToDamperLUT(vehicle, 'manufacturer', manufacturer, 'axle', axle);

fprintf('    Front axle sweep complete.\n\n');

%% ========================================================================
%  4. ANTI GEOMETRY
%     Must run AFTER offsetInPerpendicularPlane on BOTH axles,
%     since it needs correctedContactPatch for the side-view IC calculation.
% ========================================================================

fprintf('[4] Anti geometry sweep (front + rear)...\n');

vehicle = calculateAntiGeometry(vehicle, ...
    'manufacturer', manufacturer, ...
    'axle',         'both', ...
    'CoGHeight',    300);
fprintf('    Anti geometry complete.\n\n');

%% ========================================================================
%  5. DEBUG PLOTS
%     Comment out to skip. Run before export to catch any issues.
% ========================================================================

fprintf('[5] Generating debug plots...\n');
plotKinematicsDebug(vehicle, 'manufacturer', manufacturer);
fprintf('    Debug plots complete.\n\n');

%% ========================================================================
%  6. EXPORT TO EXCEL
% ========================================================================

fprintf('[6] Exporting to Excel...\n');
exportKinematicsToExcel(vehicle, ...
    'manufacturer', manufacturer, ...
    'OutputFile',   'GEN3_Kinematics.xlsx');

fprintf('\n=================================================\n');
fprintf('  Kinematic sweep complete.\n');
fprintf('=================================================\n');