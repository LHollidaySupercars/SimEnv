%% Assuming symetric 
%% Shows the number of options per connection point
%% Rear

rearCamberShims = 8;
rearUBJ_Options = 5;
rearUpperForeMaxShim = 8;
rearUpperAftMaxShim = 8;
rearLowerForeMaxShim = 8;
rearLowerAftMaxShim = 8;
% lowerAArm_screw = (5/8 * 25.4) * pi() * tan(deg2rad(9));
screw = ((36.5 - 15 * 1.5) - 5) / 0.5; %  % useable bolt length


%% Front

frontCamberShims = 8;
frontUBJ_Options = 5;
frontUpperForeMaxShim = 8;
frontUpperAftMaxShim = 8;
frontLowerForeMaxShim = 8;
frontLowerAftMaxShim = 8;
screw = ((36.5 - 15 * 1.5) - 5) / 0.5; %  % useable bolt length

rearOptions = length(fullfact([rearCamberShims,   rearUBJ_Options,  rearUpperForeMaxShim,  rearUpperAftMaxShim,  rearLowerForeMaxShim,  lowerAftMaxShim,      screw]));
frontOptions = length(fullfact([frontCamberShims, frontUBJ_Options, frontUpperForeMaxShim, frontUpperAftMaxShim, frontLowerForeMaxShim, frontLowerAftMaxShim, screw]));

fprintf('---------------------------------------------\n')
fprintf('|Front Geometry | %i possible options\t|\n', frontOptions) 
fprintf('|Rear Geometry  | %i possible options\t|\n', rearOptions) 
fprintf('---------------------------------------------\n')


fprintf('----------------Simplified DOE---------------\n')
fprintf('|Front Geometry  | %i possible options\t|\n', frontOptions) 
fprintf('|Rear Geometry   | %i possible options\t|\n', rearOptions) 
fprintf('---------------------------------------------\n')

%% Mapping process

% complete later post validation