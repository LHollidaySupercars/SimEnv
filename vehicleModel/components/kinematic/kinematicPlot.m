%% Initiation script for kinematic analysis
% Current kinematic logic requires the execution of the GEN3_KinematicParameters file
% % Not doing so will result in continuous offsets, if excecuting scripts multiple times
clear all; close all;
manufacturer = 'ford';
fprintf('Loading Kinematic properties...\n');

GEN3_KinematicParameters
POS = containers.Map();
axle = 'front'

% Shim Enquiry
% ============================== FRONT ==================================
% Upright Positions
POS('FRONT_UBJ_UPRIGHT_POS') = 3;


POS('FLF_POS') = 3;
Clevis = 'ford.kinematics.front.lowerAArm.fore';
clevisShims = ...
[1              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('FLA_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.front.lowerAArm.aft';
clevisShims = ...
[1              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('FUF_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.front.upperAArm.fore';
clevisShims = ...
[1              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('FUA_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.front.upperAArm.aft';
clevisShims = ...
[1              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
% ============================== REAR ==================================
POS('REAR_UBJ_UPRIGHT_POS') = 3;


axle = 'rear'
original = vehicle.ford.kinematics.rear.upperAArm.fore;
POS('RLF_POS') = 3;
Clevis = 'ford.kinematics.rear.lowerAArm.fore';
clevisShims = ...
[0              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('RLA_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.rear.lowerAArm.aft';
clevisShims = ...
[0              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('RUF_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.rear.upperAArm.fore';
clevisShims = ...
[0              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
POS('RUA_POS') = 3;
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle)
Clevis = 'ford.kinematics.rear.upperAArm.aft';
clevisShims = ...
[0              ,0                  ,0              ,0              ];
%======1mm======|======1.5mm======|======2mm=======|======5mm=======|
%clevisShims_5116, clevisShims_5129, clevisShims_5117, clevisShims_5118
vehicle = clevisOffset(vehicle, Clevis, clevisShims, axle);
camberShims = [1, 1, 0];
%%
kinSweep_Script
%%
kinematicPlot_script