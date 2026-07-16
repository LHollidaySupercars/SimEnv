function test_cache_diagnostic()
% TEST_CACHE_DIAGNOSTIC Simple test to diagnose the actual cache structure

cache_file = 'E:\2026\04_RUA\_TeamData\smp_cache_Q13.mat';

if ~exist(cache_file, 'file')
    fprintf('Cache file not found: %s\n', cache_file);
    return;
end

fprintf('\n=== CACHE DIAGNOSTIC ===\n\n');

% Step 1: Inspect cache
fprintf('Step 1: Inspecting cache structure...\n');
groups_info = smp_cache_inspect(cache_file);

fprintf('\n\nStep 2: Attempting to load cache...\n');
try
    cache = smp_cache_load(cache_file);
    fprintf('✓ Cache loaded\n');
catch ME
    fprintf('✗ Failed to load: %s\n', ME.message);
    return;
end

fprintf('\nStep 3: Checking traces structure...\n');
if ~isfield(cache, 'traces')
    fprintf('✗ No traces field\n');
    return;
end

trace_groups = fieldnames(cache.traces);
fprintf('✓ Found %d trace groups\n', length(trace_groups));

if length(trace_groups) > 0
    fprintf('\nStep 4: Inspecting first group (%s)...\n', trace_groups{1});
    gk = trace_groups{1};
    group_data = cache.traces.(gk);
    
    fprintf('  Fields: %s\n', strjoin(fieldnames(group_data), ', '));
    
    if isfield(group_data, 'lap_times')
        fprintf('  Lap times: %d entries\n', length(group_data.lap_times));
        fprintf('  Best time: %.3f sec\n', min(group_data.lap_times));
    end
    
    % Try to inspect a channel
    all_fields = fieldnames(group_data);
    ch_fields = all_fields(~ismember(all_fields, {'lap_times', 'lap_numbers', 'n_traces'}));
    
    if length(ch_fields) > 0
        fprintf('\nStep 5: Inspecting first channel (%s)...\n', ch_fields{1});
        ch = group_data.(ch_fields{1});
        
        if iscell(ch)
            fprintf('  Type: cell array, length %d\n', length(ch));
            if length(ch) > 0 && ~isempty(ch{1})
                if isstruct(ch{1})
                    fprintf('  Cell[1] struct fields: %s\n', strjoin(fieldnames(ch{1}), ', '));
                    % Try to access data
                    if isfield(ch{1}, 'data')
                        fprintf('  Cell[1].data size: [%d x %d]\n', size(ch{1}.data, 1), size(ch{1}.data, 2));
                    end
                end
            end
        elseif isstruct(ch)
            fprintf('  Type: struct, fields: %s\n', strjoin(fieldnames(ch), ', '));
        elseif isnumeric(ch)
            fprintf('  Type: numeric array, size [%d x %d]\n', size(ch, 1), size(ch, 2));
        end
    end
end

fprintf('\n=== END DIAGNOSTIC ===\n\n');

end
