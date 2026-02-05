function vehicle = clevisOffset(vehicle, fieldPath, clevisShims, axle, varargin)
     p = inputParser;
        addRequired(p, 'vehicle');
        addRequired(p, 'fieldPath');
        addRequired(p, 'clevisShims');
        addRequired(p, 'axle');
        addParameter(p, 'thetaL_range', [])
        
    parse(p, vehicle, fieldPath, clevisShims, axle, varargin{:});
        
    clevisOffset = ...
    sum([vehicle.kinematics.rear.clevisShims_5116;
         vehicle.kinematics.rear.clevisShims_5117;
         vehicle.kinematics.rear.clevisShims_5118;
         vehicle.kinematics.rear.clevisShims_5129] .* clevisShims');
    fields = strsplit(fieldPath, '.');
    
    % Build substruct with separate '.' for each field
    % Split the path into individual field names
    fields = strsplit(fieldPath, '.');
    
    % Get the current value using getfield
    currentValue = getfield(vehicle, fields{:});
    
    % Make your adjustment (example: multiply by 1.1)
    adjustedValue = currentValue +  clevisOffset; % or whatever adjustment you need
    
    % Set the new value using setfield
    vehicle = setfield(vehicle, fields{:}, adjustedValue);
    
    
end