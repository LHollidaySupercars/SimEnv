function [groups_info] = smp_cache_inspect(cache_path)
% SMP_CACHE_INSPECT Inspect cache structure and trace data availability
%
% USAGE:
%   [groups_info] = smp_cache_inspect(cache_path)
%
% Helps diagnose cache loading issues

fprintf('Inspecting cache: %s\n', cache_path);
fprintf('===============================================\n\n');

if ~exist(cache_path, 'file')
    error('Cache file not found: %s', cache_path);
end

% Load cache
cache = smp_cache_load(cache_path);

% Inspect structure
fprintf('CACHE STRUCTURE:\n');
fprintf('  Fields: %s\n', strjoin(fieldnames(cache), ', '));

if isfield(cache, 'manifest')
    fprintf('\nMANIFEST (table):\n');
    fprintf('  Rows: %d\n', height(cache.manifest));
    if height(cache.manifest) > 0
        fprintf('  Columns: %s\n', strjoin(cache.manifest.Properties.VariableNames, ', '));
    end
end

if isfield(cache, 'traces')
    fprintf('\nTRACES:\n');
    groups = fieldnames(cache.traces);
    fprintf('  Groups: %d\n', length(groups));
    
    groups_info = table();
    
    for g = 1:length(groups)
        gk = groups{g};
        group_struct = cache.traces.(gk);
        
        % Get basic info
        n_traces = 0;
        lap_times = [];
        channels = {};
        
        if isfield(group_struct, 'n_traces')
            n_traces = group_struct.n_traces;
        elseif isfield(group_struct, 'lap_times')
            n_traces = length(group_struct.lap_times);
            lap_times = group_struct.lap_times;
        end
        
        % List channels
        ch_names = fieldnames(group_struct);
        ch_names(ismember(ch_names, {'lap_times', 'lap_numbers', 'n_traces'})) = [];
        channels = ch_names;
        
        fprintf('\n  [%d] %s\n', g, gk);
        fprintf('      Laps: %d\n', n_traces);
        if ~isempty(lap_times)
            fprintf('      Lap times: %.3f - %.3f sec (min-max)\n', min(lap_times), max(lap_times));
            fprintf('      Fastest: %.3f sec\n', min(lap_times));
        end
        fprintf('      Channels: %d\n', length(channels));
        if length(channels) <= 10
            fprintf('        %s\n', strjoin(channels, ', '));
        else
            fprintf('        %s... (%d more)\n', strjoin(channels(1:5), ', '), length(channels)-5);
        end
        
        % Try to inspect first trace structure
        if n_traces > 0 && length(channels) > 0
            try
                first_ch = channels{1};
                ch_data = group_struct.(first_ch);
                
                fprintf('      Sample channel structure (%s):\n', first_ch);
                if iscell(ch_data)
                    fprintf('        Cell array, length: %d\n', length(ch_data));
                    if length(ch_data) > 0 && ~isempty(ch_data{1})
                        if isstruct(ch_data{1})
                            fprintf('        Cell[1] is struct with fields: %s\n', ...
                                strjoin(fieldnames(ch_data{1}), ', '));
                        elseif isnumeric(ch_data{1})
                            fprintf('        Cell[1] is numeric: [%d x %d]\n', ...
                                size(ch_data{1}, 1), size(ch_data{1}, 2));
                        end
                    end
                elseif isstruct(ch_data)
                    fprintf('        Direct struct with fields: %s\n', ...
                        strjoin(fieldnames(ch_data), ', '));
                elseif isnumeric(ch_data)
                    fprintf('        Numeric: [%d x %d]\n', size(ch_data, 1), size(ch_data, 2));
                end
            catch
                fprintf('      (Could not inspect sample channel)\n');
            end
        end
        
        % Add to table
        groups_info = [groups_info; table(gk, n_traces, min(lap_times), length(channels), ...
            'VariableNames', {'Group', 'Num_Laps', 'Best_Time_sec', 'Num_Channels'})];
    end
    
else
    fprintf('No traces in cache!\n');
    groups_info = table();
end

fprintf('\n===============================================\n');
fprintf('SUMMARY:\n');
if isfield(cache, 'mode')
    fprintf('  Cache mode: %s\n', cache.mode);
end
if isfield(cache, 'save_mode')
    fprintf('  Save mode: %s\n', cache.save_mode);
end

if ~isempty(groups_info)
    fprintf('\n  Fastest lap across all groups:\n');
    [min_time, min_idx] = min(groups_info.Best_Time_sec);
    fprintf('    Group: %s\n', groups_info.Group{min_idx});
    fprintf('    Time: %.3f sec\n', min_time);
end

end
