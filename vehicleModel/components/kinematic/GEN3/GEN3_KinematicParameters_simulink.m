%% Front / Rear Tyre Info
% Centre point found from cad, upright rotation plane to tyre midplane
% point
mm2m = 1/1000;
vehicle.ford.kinematics.body.CoG = [-29, 10.49, 284] .* mm2m; % Centre of Gravity

vehicle.ford.kinematics.rear.tyreCorneringStiffness = 3000; % N/degree
vehicle.ford.kinematics.front.tyreCorneringStiffness = 3000; % N/degree

vehicle.ford.kinematics.rear.tyrecenterPoint = [0, 63.7124, 327.9533] .* mm2m;  %mm
vehicle.ford.kinematics.front.tyrecenterPoint = [0, 63.7124, 327.9533] .* mm2m;  %mm
% have to remeasure
vehicle.ford.kinematics.rear.tyrecenterPoint = [0, 23.3483, 327.9533] .* mm2m;  %mm
vehicle.ford.kinematics.front.tyrecenterPoint = [0, 23.3483, 327.9533] .* mm2m;  %mm

vehicle.ford.kinematics.rear.tyreGeometryInside = [0, 174, 327.9533] .* mm2m;  %mm
vehicle.ford.kinematics.front.tyreGeometryInside = [0, 174, 327.9533] .* mm2m;  %mm

vehicle.ford.kinematics.rear.tyreGeometryOutside = [0, 126, 327.9533] .* mm2m;  %mm
vehicle.ford.kinematics.front.tyreGeometryOutside = [0, 126, 327.9533] .* mm2m;  %mm

vehicle.ford.kinematics.rear.tyreRadius = norm(vehicle.ford.kinematics.rear.tyrecenterPoint) .* mm2m;  %mm
vehicle.ford.kinematics.front.tyreRadius = norm(vehicle.ford.kinematics.front.tyrecenterPoint) .* mm2m;  %mm
vehicle.ford.kinematics.rear.tyreWidth =  [0, 302, 0] .* mm2m; 
vehicle.ford.kinematics.front.tyreWidth = [0, 302, 0] .* mm2m; 
vehicle.ford.kinematics.body.trackWidth = 2760 .* mm2m; 

vehicle.ford.kinematics.front.CentreLineLaser = [-2114.0444, 0, -4.9] .* mm2m; 
vehicle.ford.kinematics.rear.CentreLineLaser = [901.5, 0, 11.6] .* mm2m; 

vehicle.ford.kinematics.front.RideHeightReferenceLocationLeft = [-2148, -427.74, 26] .* mm2m;  
vehicle.ford.kinematics.front.RideHeightReferenceLocationRight = [-2148, 427.74, 26] .* mm2m;  

vehicle.ford.kinematics.rear.RideHeightReferenceLocationLeft = [925.5, -236.9, 31] .* mm2m;  
vehicle.ford.kinematics.rear.RideHeightReferenceLocationRight = [925.5, 236.9, 31] .* mm2m;  


%% Front / Rear Shims
% Camber Shims
vehicle.kinematics.front.camberShims_5219 = [0, 1.016, 0] .* mm2m;  % CAD reference
vehicle.kinematics.front.camberShims_5220 = [0, 1.600, 0] .* mm2m;  % CAD reference
vehicle.kinematics.front.camberShims_5221 = [0, 2.540, 0] .* mm2m;  % CAD reference
vehicle.kinematics.front.camberShims_5222 = [0, 5.000, 0] .* mm2m;  % CAD reference

vehicle.kinematics.rear.camberShims_3127 = [0, 1.016, 0] .* mm2m;  % CAD reference
vehicle.kinematics.rear.camberShims_3140 = [0, 2.500, 0] .* mm2m;  % CAD reference
vehicle.kinematics.rear.camberShims_3141 = [0, 5.000, 0] .* mm2m;     % CAD reference
vehicle.kinematics.rear.camberShims_CAD_ERROR = [0, 1.6, 0] .* mm2m;  % CAD reference

% Clevis Shims
vehicle.kinematics.rear.clevisShims_5116 = [0, 1.0, 0] .* mm2m;  % CAD reference
vehicle.kinematics.rear.clevisShims_5117 = [0, 2.0, 0] .* mm2m;  % CAD reference
vehicle.kinematics.rear.clevisShims_5118 = [0, 5.0, 0] .* mm2m;  % CAD reference
vehicle.kinematics.rear.clevisShims_5129 = [0, 1.5, 0] .* mm2m;  % CAD reference

vehicle.kinematics.front.clevisShims_5116 = [0, 1.0, 0] .* mm2m;  % CAD reference
vehicle.kinematics.front.clevisShims_5129 = [0, 1.5, 0] .* mm2m;  % CAD reference
vehicle.kinematics.front.clevisShims_5117 = [0, 2.0, 0] .* mm2m;  % CAD reference
vehicle.kinematics.front.clevisShims_5118 = [0, 5.0, 0] .* mm2m;  % CAD reference

vehicle.ford.kinematics.front.clevis.POS1 = [0, 0 , 25.0] .* mm2m; 
vehicle.ford.kinematics.front.clevis.POS2 = [0, 0 , 12.5] .* mm2m; 
vehicle.ford.kinematics.front.clevis.POS3 = [0, 0 , 0.00] .* mm2m; 
vehicle.ford.kinematics.front.clevis.POS4 = [0, 0 , -12.5] .* mm2m; 
vehicle.ford.kinematics.front.clevis.POS5 = [0, 0 , -25.0] .* mm2m; 


vehicle.ford.kinematics.rear.clevis.POS1 = [0, 0 , 25.0] .* mm2m; 
vehicle.ford.kinematics.rear.clevis.POS2 = [0, 0 , 12.5] .* mm2m; 
vehicle.ford.kinematics.rear.clevis.POS3 = [0, 0 , 0.00] .* mm2m; 
vehicle.ford.kinematics.rear.clevis.POS4 = [0, 0 , -12.5] .* mm2m; 
vehicle.ford.kinematics.rear.clevis.POS5 = [0, 0 , -25.0] .* mm2m; 
vehicle.ford.kinematics.rear.clevis.yOffset = [0, 28, 0] .* mm2m; 

vehicle.ford.kinematics.rear.upperAArm.UBJ_UPRIGHT_POS_1 = [0, 0, 15.0] .* mm2m;  
vehicle.ford.kinematics.rear.upperAArm.UBJ_UPRIGHT_POS_2 = [0, 0, 7.50] .* mm2m;  
vehicle.ford.kinematics.rear.upperAArm.UBJ_UPRIGHT_POS_3 = [0, 0, 0.00] .* mm2m;  
vehicle.ford.kinematics.rear.upperAArm.UBJ_UPRIGHT_POS_4 = [0, 0, -7.5] .* mm2m;  
vehicle.ford.kinematics.rear.upperAArm.UBJ_UPRIGHT_POS_5 = [0, 0, -15.] .* mm2m; 

vehicle.ford.kinematics.rear.damper.fittedLength = 500 .* mm2m; 
vehicle.ford.kinematics.rear.damper.maxCompression = 40 .* mm2m; 
vehicle.ford.kinematics.rear.damper.maxDroop = 20 .* mm2m; 

%% Rear Geometry

clevisShimOffsetUFA = [0, 9, 0] .* mm2m; 
clevisShimOffsetUAA = [0, 9, 0] .* mm2m; 
clevisShimOffsetLFA = [0, 9, 0] .* mm2m; 
clevisShimOffsetLAA = [0, 9, 0] .* mm2m; 

vehicle.ford.kinematics.rear.upperAArm.uprightConnector = [0, 82.5, 0] .* mm2m; 
vehicle.ford.kinematics.rear.upperAArm.uprightBalljointAdjust = [0, 0, 15] .* mm2m;  % measurement is in the uprights reference plane
% 3 discrete points would be enough of a change

vehicle.ford.kinematics.rear.Pot.pivotPoint = [605.5225, 462.4329, 380.644] .* mm2m; 
vehicle.ford.kinematics.rear.Pot.armPickup  = [670.0128, 473.7571, 342.7843] .* mm2m; 
v = vehicle.ford.kinematics.rear.Pot.pivotPoint - [605.3531, 420.7730, 363.6311] .* mm2m; 
vehicle.ford.kinematics.rear.Pot.shaftAxis  = v ./ norm(v) .* mm2m; 
clear v

vehicle.ford.kinematics.rear.damper.chassisPickup = [680.5, 478.9772 , 588.8103] .* mm2m; 
vehicle.ford.kinematics.rear.rocker.ARBPickup =     [680.4979, 689.9381 , 18.1861] .* mm2m; 
vehicle.ford.kinematics.rear.rocker.damperPickup =  [680.3829, 693.2589 , 79.3026] .* mm2m; 
vehicle.ford.kinematics.rear.rocker.uprightPickup = [680.4974, 801.4376 , 41.009] .* mm2m; 
vehicle.ford.kinematics.rear.lowerAArm.potPickupPoint = [648.6657, 640.6254, 50.9849] .* mm2m; 
vehicle.ford.kinematics.rear.chassis.potPickupPoint = [671.5284, 463.1357, 342.5956] .* mm2m; 

vehicle.ford.kinematics.rear.upperAArm.fore = [530.5, 422, 296] + vehicle.ford.kinematics.rear.clevis.yOffset .* mm2m;  % Face Reference parallel with x-z face
vehicle.ford.kinematics.rear.upperAArm.aft = [830.5, 422, 296] + vehicle.ford.kinematics.rear.clevis.yOffset .* mm2m; 
vehicle.ford.kinematics.rear.upperAArm.ballJoint = [680.5, 682.3263 , 322.7942] .* mm2m;  % experimentally found to have 0 camber shims
% found by using the rear camber correction, but using -6.6 which is the
% negation of the nominal length from the cad 

vehicle.ford.kinematics.rear.upperAArm.ballJointCAD = [680.5, 688.7929 , 324.3043] .* mm2m; 
% Connector piece and camber shim compensation are completed through the

vehicle.ford.kinematics.rear.lowerAArm.fore = [470.5, 244 , 71] + vehicle.ford.kinematics.rear.clevis.yOffset .* mm2m; 
vehicle.ford.kinematics.rear.lowerAArm.aft = [925.5, 244, 71] + vehicle.ford.kinematics.rear.clevis.yOffset .* mm2m; 
vehicle.ford.kinematics.rear.lowerAArm.ballJoint = [680.4974, 801.4376, 42.009] .* mm2m; 

vehicle.ford.kinematics.rear.lowerAArm.toeRodUpright = [810.9965, 801.9947 , 42.1483] .* mm2m; 
vehicle.ford.kinematics.rear.lowerAArm.toeRodChassis = [911.6355, 384.1572, 65.5999] .* mm2m; 

vehicle.ford.kinematics.rear.upright.rotationAxis = [740.5586, 773.1527, 190.6875] .* mm2m; 
% distance from the KPI axis, mesurements are taken from cad in a plane
% perpendicular to the KPI axis
vehicle.ford.kinematics.rear.upright.wheelCenterPlaneAlongUBJ2LBJAxis = [0, 0, 149.0105] .* mm2m; 
vehicle.ford.kinematics.rear.upright.wheelCenterDelta2KPI = [-59.76, -33, 0] .* mm2m;
% vehicle.ford.kinematics.rear.upright.wheelCenterDelta2KPI = [59.7621, 63.981, 5.2712];
vehicle.ford.kinematics.rear.upright.wheelAxleOffsetToUpright = [0, 29.9, 0] .* mm2m;  % value in the upright's reference plane
vehicle.ford.kinematics.rear.upright.wheelMatingFace2RotatationalAxis = [0, 80.25, 0] .* mm2m;  %upright reference plane
    
vehicle.ford.steering.ratio = 58 / (2 * pi); % reference from tickford

vehicle.Chevrolet = vehicle.ford .* mm2m; 
vehicle.toyota = vehicle.ford .* mm2m; 

%% Front Geometry 
% Nominal position is 3
% From plane to wheel face is 6 degrees 

% measurement is in the uprights reference plane
% 3 discrete points would be enough of a change

vehicle.ford.kinematics.front.damper.chassisPickup = [-1948.9736, 420.5562, 562.2953] .* mm2m; 
vehicle.ford.kinematics.front.rocker.damperPickup =  [-2008.8413, 718.7937 , 72.1863] .* mm2m; 
vehicle.ford.kinematics.front.upright.wheelCenterDelta2KPI = [59.76, -64.2, 0] .* mm2m;  
vehicle.ford.kinematics.front.lowerAArm.potPickupPoint = [-1961.3725, 669.709, 74.9577] .* mm2m; 
vehicle.ford.kinematics.front.chassis.potPickupPoint = [-1919.4866, 427.4791, 421.2424] .* mm2m; 

vehicle.ford.kinematics.front.Pot.pivotPoint = [-1994.9996, 432.1091, 439.4587] .* mm2m; 
vehicle.ford.kinematics.front.Pot.armPickup  = [-1921, 435.9703, 426.6687] .* mm2m; 
v = vehicle.ford.kinematics.front.Pot.pivotPoint - [-1995, 394.2666, 415.1082] .* mm2m; 
vehicle.ford.kinematics.front.Pot.shaftAxis  = v ./ norm(v) .* mm2m; 
vehicle.ford.kinematics.front.clevis.yOffset = [0, 28, 0] .* mm2m; 

vehicle.ford.kinematics.front.damper.fittedLength = 500 .* mm2m; 
vehicle.ford.kinematics.front.damper.maxCompression = 40 .* mm2m; 
vehicle.ford.kinematics.front.damper.maxDroop = 20 .* mm2m; 

vehicle.ford.kinematics.front.upperAArm.UBJ_UPRIGHT_POS_1 = [0, 0, 15.0] .* mm2m;  
vehicle.ford.kinematics.front.upperAArm.UBJ_UPRIGHT_POS_2 = [0, 0, 7.50] .* mm2m;  
vehicle.ford.kinematics.front.upperAArm.UBJ_UPRIGHT_POS_3 = [0, 0, 0.00] .* mm2m;  
vehicle.ford.kinematics.front.upperAArm.UBJ_UPRIGHT_POS_4 = [0, 0, -7.5] .* mm2m;  
vehicle.ford.kinematics.front.upperAArm.UBJ_UPRIGHT_POS_5 = [0, 0, -15.] .* mm2m;  

vehicle.ford.kinematics.front.upperAArm.fore =       [-2175,      466.5289 , 294.92476] + vehicle.ford.kinematics.front.clevis.yOffset .* mm2m;  % done
vehicle.ford.kinematics.front.upperAArm.ballJoint =  [-1949.2757, 702.919,   331.0431 ] .* mm2m;   % done
vehicle.ford.kinematics.front.upperAArm.aft =        [-1885,      466.5289,  294.92476] + vehicle.ford.kinematics.front.clevis.yOffset .* mm2m;  % done

vehicle.ford.kinematics.front.lowerAArm.fore =       [-2148,      472, 66] + vehicle.ford.kinematics.front.clevis.yOffset .* mm2m;  % done
vehicle.ford.kinematics.front.lowerAArm.ballJoint =  [-2012.3338, 781.9798, 60.1016] .* mm2m;  % done
vehicle.ford.kinematics.front.lowerAArm.aft =        [-1835,      472, 66] + vehicle.ford.kinematics.front.clevis.yOffset .* mm2m;            % done
%% Static Camber Contributions

vehicle.ford.kinematics.front.upperAArm.pivotPart = [0, 20, 0] .* mm2m;  % CAD reference Part 5146
vehicle.ford.kinematics.front.steeringRack.toeRodUpright = [-2144.1745, 765.550,  58.9963] .* mm2m;  % done
vehicle.ford.kinematics.front.steeringRack.toeRodChassis = [-2225,      420,      66] .* mm2m; 

vehicle.ford.kinematics.front.lowerAArm.toeRodUpright = vehicle.ford.kinematics.front.steeringRack.toeRodUpright .* mm2m; 
vehicle.ford.kinematics.front.lowerAArm.toeRodChassis = vehicle.ford.kinematics.front.steeringRack.toeRodChassis .* mm2m; 

vehicle.ford.kinematics.front.upright.rotationAxisOne = [-2025.8483, 839.9654, 207.83] .* mm2m; 
vehicle.ford.kinematics.front.upright.rotationAxisTwo = [-2027.1295, 960.6252, 222.0372] .* mm2m; 

vehicle.ford.kinematics.front.ARB.torsionBarEnd =           [-1912.5, 490, 12.5] .* mm2m;  % done
vehicle.ford.kinematics.front.ARB.dropLinkConnection =      [-2089.8249, 490, 12.715] .* mm2m;  % done
vehicle.ford.kinematics.front.ARB.dropLinkRotationAxis =    [-2085, 415, 340] .* mm2m;  % done

vehicle.ford.kinematics.front.ARB.dropLinkHole =                [-2085, 487.4097, 374.0124] .* mm2m;  % done
vehicle.ford.kinematics.front.ARB.transferLinkRotationAxis =    [-2042.5, 415, 340] .* mm2m;  % done
vehicle.ford.kinematics.front.ARB.transferLinkHole =            [-2042.5, 473.8328, 367.6351] .* mm2m;  % done
vehicle.ford.kinematics.front.ARB.transferLinkAArm =            [-2050.2524, 680.5690, 93.5423] .* mm2m;  % done

vehicle.ford.kinematics.front.upright.wheelAxleOffsetToUpright =         [0, 9, 0] .* mm2m;  % value in the upright's reference plane
vehicle.ford.kinematics.front.upright.wheelCenterPlaneAlongUBJ2LBJAxis = [0, 0, 122.184] .* mm2m; 
vehicle.ford.kinematics.front.upright.wheelCenterDelta2KPI =             [40.9762, -81.5576, 0] .* mm2m; 
vehicle.ford.kinematics.front.ARB.transferLinkAArm = [-2050.2524, 680.5690, 93.5423] .* mm2m;  % done


%% Sensor Locations

vehicle.ford.sensors.teamData.IMU =[-91.85, 150.75, 25.0] .* mm2m; 

%% Copy the vehicle to toyota and Chevrolet
vehicle.Chevrolet = vehicle.ford .* mm2m; 
vehicle.toyota = vehicle.ford .* mm2m; 
%% VSD
vehicle.ford.minimumWheelbase = 2745.0 .* mm2m;  % mm
vehicle.ford.maximumWheelbase = 2767.5 .* mm2m; % mm
vehicle.ford.maximumTrackWidthFront = 2000 .* mm2m;  % mm
vehicle.ford.maximumTrackWidthRear = 2000 .* mm2m;  % mm
vehicle.ford.maximumLength = 4863.0 .* mm2m; % mm
vehicle.ford.frontAxleBodyWorkMaximum = 1934.5 + 10 .* mm2m; % mm
vehicle.ford.rearAxleBodyWorkMaximum = 1959.5 + 10 .* mm2m; % mm
vehicle.ford.roofHeight_neg510mm = 1165.5 .* mm2m; % mm
vehicle.ford.roofheight_neg290mm = 1181.7 .* mm2m; % mm
vehicle.ford.roofheight_pos305 = 1125.0 .* mm2m; % mm
vehicle.ford.frontBumperLocation = [ -2988, 0 , -23.6] .* mm2m; % mm
vehicle.ford.rearBumperLocation = [1874, 0, 527] .* mm2m; % mm
vehicle.ford.rearWingPivotPointX = 1652.6 + [2 ,-5] .* mm2m; % mm
vehicle.ford.rearWingPivotPointZ = 973.9 + [ 2, -5] .* mm2m; % mm
vehicle.ford.rearWingElementDimensions = 1500 + [ 1, -1] .* mm2m;  % mm
vehicle.ford.rearWingAngleMin = 9 .* mm2m;  % degrees
vehicle.ford.rearWingAngleMax = 10 .* mm2m;  % degrees
vehicle.ford.rearWingToDecklidSpoilerSpacingMax = [0, 270.5, 0] + [0, 3, 0;0, -3, 0] .* mm2m;  % mm
vehicle.ford.rearWingDeflection = 0;
vehicle.ford.bonnetHeight_neg1500 = [0, 0, 792.8] .* mm2m;  % + 3, -1mm
vehicle.ford.bonnetHeight_neg1950 = [0, 0, 771.9] .* mm2m;  % + 3, -1mm
vehicle.ford.bonnetHeight_neg2400 = [0, 0, 720.2] .* mm2m;  % + 3, -1mm
vehicle.ford.bonnetHeight_neg2800 = [0, 0, 579.6] .* mm2m;  % + 3, -1mm
vehicle.ford.bootLidHeight_pos1290 = [0, 0, 864] .* mm2m;  % + 3, -3mm
vehicle.ford.bootLidHeight_pos1675 = [0, 0, 791.3] .* mm2m;  % + 3, -3mm
vehicle.ford.dashHeight = [0, 0, 787.0] .* mm2m; 
vehicle.ford.wheelArchLinersFront = true;
vehicle.ford.wheelArchLinersRear = true;


vehicle.toyota.minimumWheelbase = 2745.0 .* mm2m;  % mm
vehicle.toyota.maximumWheelbase = 2767.5 .* mm2m; % mm
vehicle.toyota.maximumTrackWidthFront = 2000 .* mm2m;  % mm
vehicle.toyota.maximumTrackWidthRear = 2000 .* mm2m;  % mm
vehicle.toyota.maximumLength = 4740.1 .* mm2m; % mm
vehicle.toyota.frontAxleBodyWorkMaximum = (1930.3 + 10) .* mm2m; % mm
vehicle.toyota.rearAxleBodyWorkMaximum = (1958.5 + 10) .* mm2m; % mm
vehicle.toyota.roofHeight_neg630mm = 1136.1 .* mm2m; % mm
vehicle.toyota.roofheight_neg235_5mm = 1155.8 .* mm2m; % mm
vehicle.toyota.roofheight_pos448 = 1098.5 .* mm2m; % mm
vehicle.toyota.frontBumperLocation = [ -2980.8, 0 , -21.9] .* mm2m; % mm
vehicle.toyota.rearBumperLocation = [1759.3, 0, 656.7] .* mm2m; % mm
vehicle.toyota.rearWingPivotPointX = (1704.9 + [ 2 ,-5]) .* mm2m; % mm
vehicle.toyota.rearWingPivotPointZ = (1034.6 + [ 2, -5]) .* mm2m; % mm
vehicle.toyota.rearWingElementDimensions = (1400 + [ 1, -1]) .* mm2m;  % mm
vehicle.toyota.rearWingAngleMin = 9; % degrees
vehicle.toyota.rearWingAngleMax = 10; % degrees
vehicle.toyota.rearWingToDecklidSpoilerSpacingMax = [0, 343.4, 0] + [0, 3, 0;0, -3, 0]; % mm
vehicle.toyota.rearWingDeflection_mm_0 = 0; % mm
vehicle.toyota.rearWingDeflection_mm_80 = 4.5 .* mm2m;  % mm
vehicle.toyota.rearWingDeflection_mm_160 = 7.4 .* mm2m;  % mm
vehicle.toyota.rearWingDeflection_deg_0 = 0; % deg
vehicle.toyota.rearWingDeflection_deg_80 = 0.65; % deg
vehicle.toyota.rearWingDeflection_deg_160 = 1.00; % deg
vehicle.toyota.bonnetHeight_neg1550 = [0, 0, 790.6] .* mm2m;  % + 3, -1mm
vehicle.toyota.bonnetHeight_neg2206 = [0, 0, 746.3] .* mm2m;  % + 3, -1mm
vehicle.toyota.bonnetHeight_neg2500 = [0, 0, 662.9] .* mm2m;  % + 3, -1mm
vehicle.toyota.bonnetHeight_neg2750 = [0, 0, 553.2] .* mm2m;  % + 3, -1mm
vehicle.toyota.bonnetHeight_neg1397 = [0, 0, 820.8] .* mm2m;  % + 3, -3mm
vehicle.toyota.bonnetHeight_neg1675 = [0, 0, 859.3] .* mm2m;  % + 3, -3mm
vehicle.toyota.dashHeight = [0, 0, false];
vehicle.toyota.wheelArchLinersFront = true;
vehicle.toyota.wheelArchLinersRear = true;


vehicle.Chevrolet.minimumWheelbase = 2745.0 .* mm2m;  % mm
vehicle.Chevrolet.maximumWheelbase = 2767.5 .* mm2m; % mm
vehicle.Chevrolet.maximumTrackWidthFront = 2000 .* mm2m;  % mm
vehicle.Chevrolet.maximumTrackWidthRear = 2000 .* mm2m;  % mm
vehicle.Chevrolet.maximumLength = 4876.1 .* mm2m; % mm
vehicle.Chevrolet.frontAxleBodyWorkMaximum = (1933.3 + 10) .* mm2m; % mm
vehicle.Chevrolet.rearAxleBodyWorkMaximum = (1952.6 + 10) .* mm2m; % mm
vehicle.Chevrolet.roofHeight_neg625mm = 1123.3 .* mm2m;  mm
vehicle.Chevrolet.roofheight_neg224_1mm = 1137.8 .* mm2m;  % mm
vehicle.Chevrolet.roofheight_pos605mm = 1081.1 .* mm2m;  % mm
vehicle.Chevrolet.frontBumperLocation = [ -3027.9, 0 , -25.1] .* mm2m; % mm
vehicle.Chevrolet.rearBumperLocation = [1848.2, 0, 648.4] .* mm2m; % mm
vehicle.Chevrolet.rearWingPivotPointX = 1703.8 + [ 2 ,-5];% mm
vehicle.Chevrolet.rearWingPivotPointZ = 977.2 + [ 2, -5];% mm
vehicle.Chevrolet.rearWingElementDimensions = 1500 + [ 1, -1]; % mm
vehicle.Chevrolet.rearWingAngleMin = 9; % degrees
vehicle.Chevrolet.rearWingAngleMax = 10; % degrees
vehicle.Chevrolet.rearWingToDecklidSpoilerSpacingMax = [0, 273.5, 0] + [0, 3, 0;0, -3, 0]; % mm
vehicle.Chevrolet.rearWingDeflection_mm_0 = 0; % mm
vehicle.Chevrolet.rearWingDeflection_mm_TBA1 = 0; % mm
vehicle.Chevrolet.rearWingDeflection_mm_TBA2 = 0; % mmø
vehicle.Chevrolet.rearWingDeflection_deg_0 = 0; % deg
vehicle.Chevrolet.rearWingDeflection_deg_TBA1 = 0; % deg
vehicle.Chevrolet.rearWingDeflection_deg_TBA2 = 0; % deg
vehicle.Chevrolet.bonnetHeight_neg1595 = [0, 0, 801.3] .* mm2m;  % + 3, -1mm
vehicle.Chevrolet.bonnetHeight_neg2170 = [0, 0, 743.5] .* mm2m;  % + 3, -1mm
vehicle.Chevrolet.bonnetHeight_neg2425 = [0, 0, 711.4] .* mm2m;  % + 3, -1mm
vehicle.Chevrolet.bonnetHeight_neg2740 = [0, 0, 609.1] .* mm2m;  % + 3, -1mm
vehicle.Chevrolet.bonnetHeight_neg1397 = [0, 0, 870] .* mm2m;  % + 3, -3mm
vehicle.Chevrolet.bonnetHeight_neg1675 = [0, 0, 845.2] .* mm2m;  % + 3, -3mm
vehicle.Chevrolet.dashHeight = [0, 0, 796] .* mm2m;  %mm
vehicle.Chevrolet.wheelArchLinersFront = true; % boolean
vehicle.Chevrolet.wheelArchLinersRear = true; % boolean

%% ------------------------------------------------------------------------
%  --------------------------Bicycle model calcs---------------------------
%% ------------------------------------------------------------------------
vehicle.ford.bicycleModel.FrontTrackLocation = vehicle.ford.kinematics.front.lowerAArm.ballJoint;
vehicle.ford.bicycleModel.RearTrackLocation  = vehicle.ford.kinematics.rear.lowerAArm.ballJoint;
vehicle.ford.bicycleModel.totalMass     = 1389.8;
vehicle.ford.bicycleModel.frontAxleMass = 737.5;
vehicle.ford.bicycleModel.rearAxleMass  = vehicle.ford.bicycleModel.totalMass - vehicle.ford.bicycleModel.frontAxleMass;
vehicle.ford.bicycleModel.CoGLocation = vehicle.ford.bicycleModel.frontAxleMass / vehicle.ford.bicycleModel.totalMass;
vehicle.ford.bicycleModel.frontArm = vehicle.ford.bicycleModel.CoGLocation * vehicle.toyota.maximumWheelbase;
vehicle.ford.bicycleModel.rearArm  = (1 - vehicle.ford.bicycleModel.CoGLocation) * vehicle.toyota.maximumWheelbase;