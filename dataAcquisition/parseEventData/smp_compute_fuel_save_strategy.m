function strategy_table = smp_compute_fuel_save_strategy(variants, segments)
% SMP_COMPUTE_FUEL_SAVE_STRATEGY Compute fuel-saving strategy summary table
%
% USAGE:
%   strategy_table = smp_compute_fuel_save_strategy(variants, segments)
%
% INPUTS:
%   variants  (struct array) Output from smp_fuel_save_coasting
%   segments  (struct array) Segment definitions
%
% OUTPUT:
%   strategy_table (table) Summary with columns:
%     Segment_ID | Segment_Name | Coasting_Distance_m | Fuel_Saved_kg | 
%     Time_Penalty_sec | Fuel_per_Time_kg_per_sec | Status
%
% INTERPRETATION:
%   Fuel_per_Time > 0: Savings per unit time lost
%   Time_Penalty > 0: Time lost vs original lap
%   Fuel_Saved_kg > 0: Fuel conserved

n_variants = length(variants);

% Preallocate output arrays
segment_ids = zeros(n_variants, 1);
segment_names = cell(n_variants, 1);
coasting_distances = zeros(n_variants, 1);
fuel_saveds = zeros(n_variants, 1);
time_penalties = zeros(n_variants, 1);
fuel_per_times = zeros(n_variants, 1);
statuses = cell(n_variants, 1);

% Extract data from each variant
for v = 1:n_variants
    var = variants(v);
    
    segment_ids(v) = var.segment_idx;
    segment_names{v} = var.segment_name;
    coasting_distances(v) = var.coasting_point;
    fuel_saveds(v) = var.fuel_saved_kg;
    time_penalties(v) = var.time_penalty_sec;
    statuses{v} = var.status;
    
    % Compute ratio
    if var.time_penalty_sec > 0.001  % Avoid division by zero
        fuel_per_times(v) = var.fuel_saved_kg / var.time_penalty_sec;
    else
        fuel_per_times(v) = 0;
    end
end

% Create table
strategy_table = table(segment_ids, segment_names, coasting_distances, ...
    fuel_saveds, time_penalties, fuel_per_times, statuses, ...
    'VariableNames', {'Segment_ID', 'Segment_Name', 'Coasting_Distance_m', ...
        'Fuel_Saved_kg', 'Time_Penalty_sec', 'Fuel_per_Time_Ratio', 'Status'});

% Sort by segment_id, then by coasting distance
strategy_table = sortrows(strategy_table, {'Segment_ID', 'Coasting_Distance_m'});

fprintf('Strategy table: %d variants\n', height(strategy_table));

end
