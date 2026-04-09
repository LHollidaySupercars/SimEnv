manufacturer = 'ford';
axle = 'rear';
%% Compensates for the shim, and clevis
%% while being defined by the UBJ -> LBJ length & Lower A Arm length
%% Change A Arm Length 
radiiOffset = rearAArmCompensation(vehicle, manufacturer, axle, camberShims, 'CAD_ERROR', true); 
% don't think I need reaccess these two functions
% vehicle = threeSphereUpperAArm(vehicle, manufacturer, 'newRadii', radiiOffset, 'plotResults', true); % make adjustment to only reference the cad points and the adjustment is called 'Corrected' or something
vehicle = threeSphereUpperAArm(vehicle, manufacturer, 'axle', 'rear', 'newRadii', radiiOffset, 'plotResults', true, 'geometrySystem', 'extendAArm');
%% Start Vehicle Sweeps
vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle);
vehicle = solveWheelToe(vehicle, 'manufacturer', manufacturer, 'axle', axle);
vehicle = solveDamperTravel(vehicle);
manufacturer = 'ford';
axle = 'rear';
%% UBJ Compensation
%% these two radiiOffsets are meant to be the same?

% radiiOffset = getOffset(vehicle, manufacturer, POS, axle); % dulpicated
%% UBJ Compensation 
%% Duplicate, KPI and Camber are Coupled
%% Static Camber compensation
vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle,'thetaL_range', vehicle.(manufacturer).kinematics.(axle).camberSweep.thetaL);
%% Repeated Toe Sweep
vehicle = solveWheelToe(vehicle, 'manufacturer', manufacturer, 'axle', axle);
%% Tyre | Tyre Centre
vehicle = offsetInPerpendicularPlane(vehicle, manufacturer, axle, 'contactChoice', 'tyreCentre')
%% Inside Edge Tyre
vehicle = offsetInPerpendicularPlane(vehicle, manufacturer, 'rear', 'contactChoice', 'inside');
vehicle = solveDamperTravel(vehicle, 'Plotting', true, 'wheelCentre', 'compensated');
%% Roll Centre | Using Compensated Calculation
vehicle = calculateRollCenter(vehicle, 'manufacturer', manufacturer,'wheelCentre', 'compensated', 'Plotting', true)
%% Roll Centre | Using Simplified Model
vehicle = calculateRollCenter(vehicle, 'manufacturer', manufacturer, 'wheelCentre', 'simplified', 'Plotting', true)
%% Final Rear Kinematics Calculation
vehicle.ford.kinematics.rear.camberSweep.camberCorrected = vehicle.ford.kinematics.rear.camberSweep.camber; 
% vehicle =  calculateKinematicAttributes(vehicle, 'manufacturer', manufacturer, 'Plotting', true)
%% Front Section
axle = 'front';
assumedLinearRackDisplacement = [-pi, pi] * vehicle.ford.steering.ratio; % steering rack travel
%% Initial Camber Solve & Offset
camberShims = [ 1, 1, 0, 0];
vehicle = solveWheelCamber(vehicle, 'manufacturer', manufacturer, 'axle', axle);
vehicle = camberOffset(vehicle, camberShims, manufacturer, axle);
vehicle = solveWheelToe(vehicle, 'manufacturer', manufacturer, 'axle', axle, 'isSteeringAngle', true, 'fidelity', length(vehicle.ford.kinematics.rear.camberSweep.thetaL));
vehicle = calculateRollCenter(vehicle, 'manufacturer', manufacturer)
vehicle = calculateAntiGeometry(vehicle);
%% Contact Patch Definition
frontToeSize = size(vehicle.(manufacturer).kinematics.(axle).toeSweep.toe)
for i = 1 : frontToeSize(2)
    vehicle = offsetInPerpendicularPlane(vehicle, manufacturer, 'front', 'contactChoice', 'inside','toeIndex', i);
end 
%%  start Application
visualizeVehicleGeometryApp(vehicle, 'tyre', 'correctedContactPatch', 'tyreModel', 'CAD_REF')