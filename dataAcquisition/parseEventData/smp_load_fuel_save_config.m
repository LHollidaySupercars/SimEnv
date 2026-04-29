function [segments, segment_table] = smp_load_fuel_save_config(config_path)
% SMP_LOAD_FUEL_SAVE_CONFIG Load fuel-saving segment configuration from Excel
%
% USAGE:
%   [segments, segment_table] = smp_load_fuel_save_config(config_path)
%
% INPUT:
%   config_path  (string) Path to Excel config file
%
% OUTPUT:
%   segments      (struct array) Loaded segments with fields:
%     .segment_idx
%     .segment_name
%     .distance_start        (m)
%     .distance_end          (m)
%     .brake_marker          (m)
%     .enabled               (0 or 1)
%     .coasting_max          (m, negative)
%     .coasting_steps        (count)
%
%   segment_table (table) Original table read from Excel

% Read Excel
segment_table = readtable(config_path);

% Map column names (handle variations)
col_names = lower(segment_table.Properties.VariableNames);

% Find required columns (case-insensitive)
idx_id = find(contains(col_names, 'segment_id', 'IgnoreCase', true), 1);
idx_name = find(contains(col_names, 'segment_name', 'IgnoreCase', true), 1);
idx_start = find(contains(col_names, 'distance_start', 'IgnoreCase', true), 1);
idx_end = find(contains(col_names, 'distance_end', 'IgnoreCase', true), 1);
idx_brake = find(contains(col_names, 'brake_marker', 'IgnoreCase', true), 1);
idx_enable = find(contains(col_names, 'enable_fuel_save', 'IgnoreCase', true), 1);
idx_max_dist = find(contains(col_names, 'coasting_distance_max', 'IgnoreCase', true), 1);
idx_steps = find(contains(col_names, 'coasting_steps', 'IgnoreCase', true), 1);

% Validate required columns
if isempty(idx_enable) || isempty(idx_max_dist) || isempty(idx_steps)
    error('Excel file missing required columns: Enable_Fuel_Save, Coasting_Distance_Max_m, Coasting_Steps');
end

% Build segments struct
n_segs = height(segment_table);
segments = struct('segment_idx',   {}, 'segment_id',    {}, 'segment_name', {}, ...
                  'distance_start',{}, 'distance_end',  {}, 'brake_marker', {}, ...
                  'enabled',       {}, 'coasting_max',  {}, 'coasting_steps', {});

for s = 1:n_segs
    seg.segment_idx = s;
    
    if ~isempty(idx_id)
        seg.segment_id = segment_table{s, idx_id};
    else
        seg.segment_id = s;
    end
    
    if ~isempty(idx_name)
        seg.segment_name = segment_table{s, idx_name};
        if iscell(seg.segment_name)
            seg.segment_name = seg.segment_name{1};
        end
    else
        seg.segment_name = sprintf('Segment_%02d', s);
    end
    
    if ~isempty(idx_start)
        seg.distance_start = segment_table{s, idx_start};
    else
        seg.distance_start = 0;
    end
    
    if ~isempty(idx_end)
        seg.distance_end = segment_table{s, idx_end};
    else
        seg.distance_end = 0;
    end
    
    if ~isempty(idx_brake)
        seg.brake_marker = segment_table{s, idx_brake};
    else
        seg.brake_marker = (seg.distance_start + seg.distance_end) / 2;
    end
    
    seg.enabled = segment_table{s, idx_enable};
    seg.coasting_max = segment_table{s, idx_max_dist};
    seg.coasting_steps = segment_table{s, idx_steps};

    segments(end+1) = seg;
end

fprintf('Loaded %d segments from %s\n', n_segs, config_path);

end
