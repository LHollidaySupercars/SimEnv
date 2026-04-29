function smp_generate_fuel_save_config(segments, output_path)
% SMP_GENERATE_FUEL_SAVE_CONFIG Generate Excel template for fuel-saving segments
%
% USAGE:
%   smp_generate_fuel_save_config(segments, output_path)
%
% INPUTS:
%   segments     (struct array) Auto-detected segments from smp_detect_throttle_brake_phases
%   output_path  (string) Path to write Excel file (e.g., 'config.xlsx')
%
% OUTPUT:
%   Excel file with columns:
%     Segment_ID | Segment_Name | Distance_Start_m | Distance_End_m | Brake_Marker_m | 
%     Enable_Fuel_Save | Coasting_Distance_Max_m | Coasting_Steps
%
% DEFAULTS:
%   Enable_Fuel_Save = 1 (enabled)
%   Coasting_Distance_Max_m = -200 (m, negative = before brake marker)
%   Coasting_Steps = 10
%
% USER EDITS:
%   - Set Enable_Fuel_Save to 0 to skip a segment
%   - Adjust Coasting_Distance_Max_m (e.g., -150, -250)
%   - Adjust Coasting_Steps (e.g., 5, 20)

if isempty(segments)
    warning('No segments provided. Creating template with empty rows.');
    n_segments = 5;  % Default template with 5 empty rows
else
    n_segments = length(segments);
end

% Build table
segment_id = (1:n_segments)';
segment_name = cell(n_segments, 1);
distance_start = zeros(n_segments, 1);
distance_end = zeros(n_segments, 1);
brake_marker = zeros(n_segments, 1);

for s = 1:n_segments
    if s <= length(segments)
        segment_name{s} = segments(s).segment_name;
        distance_start(s) = segments(s).distance_start;
        distance_end(s) = segments(s).distance_end;
        brake_marker(s) = segments(s).brake_marker;
    else
        segment_name{s} = sprintf('Segment_%02d', s);
        distance_start(s) = 0;
        distance_end(s) = 0;
        brake_marker(s) = 0;
    end
end

% Defaults for fuel saving params
enable_fuel_save = ones(n_segments, 1);
coasting_distance_max = -75 * ones(n_segments, 1);  % meters (negative)
coasting_steps = 100 * ones(n_segments, 1);

% Create table
config_table = table(segment_id, segment_name, distance_start, distance_end, ...
    brake_marker, enable_fuel_save, coasting_distance_max, coasting_steps, ...
    'VariableNames', {'Segment_ID', 'Segment_Name', 'Distance_Start_m', 'Distance_End_m', ...
        'Brake_Marker_m', 'Enable_Fuel_Save', 'Coasting_Distance_Max_m', 'Coasting_Steps'});

% Write to Excel
writetable(config_table, output_path);

fprintf('Config template written: %s\n', output_path);
fprintf('User should edit this file to enable/disable segments and adjust coasting parameters.\n');

end
