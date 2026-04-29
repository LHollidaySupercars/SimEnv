function [variants, segments, output_dir, lap, preceding_lap] = smp_fuel_save_coasting(varargin)
% SMP_FUEL_SAVE_COASTING Simulate fuel-saving coasting strategies on qualifying lap
%
% USAGE:
%   [variants, segments, output_dir] = smp_fuel_save_coasting()
%   [variants, segments, output_dir] = smp_fuel_save_coasting('cache_file', cache_path)
%   [variants, segments, output_dir] = smp_fuel_save_coasting('driver_tla', 'ABC')
%   [variants, segments, output_dir] = smp_fuel_save_coasting('config_file', excel_path)
%   [variants, segments, output_dir] = smp_fuel_save_coasting('accel', -0.5, 'fuel_rate', 0.01)
%
% INPUTS (optional name-value pairs):
%   cache_file       (string) Path to smp_cache.mat [default: auto-find in session]
%   driver_tla       (string) Driver TLA code (e.g., 'JAC'). [default: global fastest]
%   config_file      (string) Path to Excel config with segments & params [default: auto-generate]
%   accel            (double) Longitudinal deceleration magnitude (m/s²) [default: -0.5]
%   fuel_rate        (double) Fuel consumption rate while coasting (kg/s) [default: 0.01]
%   output_dir       (string) Output directory for Excel & plots [default: ./fuel_save_output]
%   auto_detect      (logical) Auto-detect segments if no config [default: true]
%
% OUTPUTS:
%   variants         (struct array) All tested lap variants
%     .segment_idx        Index of segment
%     .segment_name       Name/ID of segment
%     .coasting_point     Distance before brake marker (m, negative)
%     .speed_trace        Full lap speed trace [n_dist x 1]
%     .distance           Distance vector [n_dist x 1]
%     .fuel_saved_kg      Fuel saved in this segment (kg)
%     .time_penalty_sec   Time lost in this segment (sec)
%     .status             'success' or error message
%   
%   segments         (struct array) Detected/loaded segments
%     .segment_idx        Index
%     .segment_name       Name
%     .distance_start     Start distance (m)
%     .distance_end       End distance (m)
%     .enabled            Fuel saving enabled (0/1)
%     .coasting_max       Max coasting distance (m, negative)
%     .coasting_steps     Number of steps
%
%   output_dir       (string) Path to output folder (Excel, plots)
%
% WORKFLOW:
%   1. Load session cache
%   2. Select fastest lap (by driver TLA or global)
%   3. Auto-detect throttle-brake segments (optional)
%   4. Generate or load Excel config with segment enable/disable + coasting params
%   5. For each enabled segment & coasting point:
%      - Simulate coasting with linear deceleration + constant fuel burn
%      - Track until speed intersects original lap trace
%      - Compute fuel saved & time penalty
%   6. Assemble all lap variants (distance-continuous)
%   7. Generate strategy Excel file & visualization plots
%
% DEPENDENCIES:
%   - smp_cache_load.m
%   - smp_detect_throttle_brake_phases.m
%   - smp_generate_fuel_save_config.m
%   - smp_simulate_coasting_segment.m
%   - smp_assemble_fuel_save_lap.m
%   - smp_compute_fuel_save_strategy.m
%   - smp_plot_fuel_save_variants.m
%
% AUTHOR: Fuel Strategy Analysis
% DATE: 2026-04-27

%% Parse inputs
p = inputParser;
addParameter(p, 'cache_dir',  '',  @ischar);   % Directory containing smp_cache_*.mat
addParameter(p, 'session_id', '',  @ischar);   % Session name e.g. 'Q13' (optional)
addParameter(p, 'driver_tla', '',  @ischar);
addParameter(p, 'config_file','',  @ischar);
addParameter(p, 'accel',      -11.5/3.6, @isnumeric);  % 11.5 km/h/s
addParameter(p, 'fuel_rate',  0.01, @isnumeric);
addParameter(p, 'output_dir', './fuel_save_output', @ischar);
addParameter(p, 'auto_detect', true, @islogical);
addParameter(p, 'rerun',       false, @islogical);  % skip plot + reuse Excel if it exists
parse(p, varargin{:});

params = p.Results;
fprintf('\n=== SMP Fuel Save Coasting Analysis ===\n');
fprintf('Accel: %.2f m/s², Fuel rate: %.4f kg/s\n', params.accel, params.fuel_rate);

%% Create output directory
if ~exist(params.output_dir, 'dir')
    mkdir(params.output_dir);
end
fprintf('Output directory: %s\n', params.output_dir);

%% Step 1: Load cache and select lap
fprintf('\n[1/7] Loading cache...\n');

cache_dir = params.cache_dir;
if isempty(cache_dir)
    % Fall back to current directory
    cache_dir = pwd;
end

if ~exist(cache_dir, 'dir')
    error('Cache directory not found: %s', cache_dir);
end

% Load cache — pass session_id as filter if provided
if ~isempty(params.session_id)
    cache = smp_cache_load(cache_dir, {params.session_id});
else
    cache = smp_cache_load(cache_dir);
end

% Verify cache has traces
if ~isfield(cache, 'traces') || isempty(fieldnames(cache.traces))
    fprintf('\n');
    fprintf('ERROR: Cache has no traces data.\n');
    fprintf('Check that %s contains smp_cache_*.mat files\n', cache_dir);
    fprintf('and that the session_id matches (e.g. ''Q13'' for smp_cache_Q13.mat).\n\n');
    error('Cache has no traces data.');
end

fprintf('Cache loaded successfully\n');
fprintf('  Trace groups available: %d\n', length(fieldnames(cache.traces)));

% Step 2: Select fastest lap
fprintf('\n[2/7] Selecting fastest lap...\n');
try
    [lap, group_key, lap_idx] = smp_select_fastest_lap(cache, params.driver_tla);
    fprintf('Selected lap %d from group ''%s'' (time: %.2f s)\n', lap_idx, group_key, lap.lap_time);
catch ME
    fprintf('\nERROR: Failed to select fastest lap: %s\n\n', ME.message);
    rethrow(ME);
end

% Step 2b: Load preceding lap for main-straight segment detection
fprintf('\n[2b] Loading preceding lap from raw .ld file...\n');
[preceding_lap, prec_ok] = smp_load_preceding_lap(cache, group_key, lap_idx);
if prec_ok
    fprintf('  Preceding lap loaded (lap %.2f s)\n', preceding_lap.lap_time);
else
    fprintf('  Preceding lap not available — Segment_01 will be from timed lap only.\n');
end

%% Step 3: Auto-detect segments if needed
fprintf('\n[3/7] Detecting throttle-brake segments...\n');
if isempty(params.config_file) && params.auto_detect
    segments_detected = smp_detect_throttle_brake_phases(lap);
    fprintf('Detected %d segments\n', length(segments_detected));

    % Prepend main-straight segment (Segment_01) — always attempted.
    % brake_marker / distance_end come from the timed lap's first segment.
    % distance_start comes from preceding lap if available, else 0 (finish line).
    if ~isempty(segments_detected)
        prec_arg = [];
        if prec_ok, prec_arg = preceding_lap; end
        ms_seg = smp_build_main_straight_segment(lap, segments_detected(1), prec_arg);
        if ~isempty(ms_seg)
            % Renumber existing segments +1, insert main straight as first
            for s = 1:length(segments_detected)
                segments_detected(s).segment_idx  = s + 1;
                segments_detected(s).segment_name = sprintf('Segment_%02d', s + 1);
            end
            ms_seg.segment_idx  = 1;
            ms_seg.segment_name = 'Segment_01';
            segments_detected   = [ms_seg, segments_detected];
            fprintf('  Main-straight segment prepended — %d total segments\n', length(segments_detected));
        end
    end

    if ~params.rerun
        fprintf('Opening segment review plot — adjust lines if needed, then click Accept...\n');
        prec_arg = [];
        if prec_ok, prec_arg = preceding_lap; end
        segments_detected = smp_plot_segments_interactive(lap, segments_detected, prec_arg);
        fprintf('Accepted %d segments\n', length(segments_detected));
    end
else
    segments_detected = [];
end

%% Step 4: Generate or load Excel config
fprintf('\n[4/7] Loading/generating segment config...\n');
if isempty(params.config_file)
    config_path = fullfile(params.output_dir, 'smp_fuel_save_config.xlsx');
    if params.rerun && exist(config_path, 'file')
        fprintf('Rerun mode: reusing existing config: %s\n', config_path);
    else
        smp_generate_fuel_save_config(segments_detected, config_path);
        fprintf('Config template generated: %s\n', config_path);
        fprintf('>>> EDIT the Excel file and set enable flags, coasting params, then press Enter to continue...\n');
        pause;  % Wait for user to edit
    end
    params.config_file = config_path;
end

% Load config
[segments, segment_table] = smp_load_fuel_save_config(params.config_file);
fprintf('Loaded %d segments from config\n', length(segments));
fprintf('Enabled segments: %d\n', sum([segments.enabled]));

%% Step 5: Generate variants (simulate each segment + coasting point)
fprintf('\n[5/7] Simulating coasting variants...\n');
variants = [];
variant_count = 0;

% For S01 (distance_start < 0), stitch the preceding lap onto the timed lap
% so the simulator has a continuous distance axis that covers negative distances.
if prec_ok
    lap_s01 = smp_stitch_preceding_lap(preceding_lap, lap);
    fprintf('  S01 stitched lap: %.1f m to %.1f m\n', ...
        lap_s01.channels.Distance.dist(1), lap_s01.channels.Distance.dist(end));
else
    lap_s01 = lap;
end

for seg_idx = 1:length(segments)
    seg = segments(seg_idx);
    if ~seg.enabled
        fprintf('  Segment %d (%.0f-%.0f m): SKIPPED\n', seg_idx, seg.distance_start, seg.distance_end);
        continue;
    end
    
    % Generate coasting points — positive values = metres before peak speed.
    % Accept both positive and negative from Excel; abs() normalises.
    coasting_max_pos = abs(seg.coasting_max);
    coasting_points  = linspace(coasting_max_pos, 0, seg.coasting_steps + 1);
    coasting_points(end) = [];  % Remove 0 (no coasting)
    
    fprintf('  Segment %d (%.0f-%.0f m): %d coasting points\n', ...
        seg_idx, seg.distance_start, seg.distance_end, length(coasting_points));
    
    for cp_idx = 1:length(coasting_points)
        coasting_pt = coasting_points(cp_idx);
        variant_count = variant_count + 1;
        
        try
            % For segments that start before the finish line (S01, negative dist),
            % use the stitched lap that includes the preceding lap data.
            lap_for_sim = lap;
            if seg.distance_start < 0
                lap_for_sim = lap_s01;
            end

            % Simulate coasting for this segment & point
            [lap_modified, fuel_saved, time_penalty, details] = ...
                smp_simulate_coasting_segment(lap_for_sim, seg, coasting_pt, ...
                    'accel', params.accel, 'fuel_rate', params.fuel_rate);

            % Store variant
            v.segment_idx       = seg_idx;
            v.segment_name      = seg.segment_name;
            v.coasting_point    = coasting_pt;
            v.distance          = lap_modified.channels.Ground_Speed.dist;
            v.speed_trace       = lap_modified.channels.Ground_Speed.data; % km/h
            v.fuel_saved_kg     = fuel_saved;
            v.time_penalty_sec  = time_penalty;
            v.details           = details;
            v.status            = 'success';

            variants = [variants, v];

        catch ME
            % Extract the human-readable message (strip error ID prefix)
            msg = ME.message;
            fprintf('    [FAIL] Seg %d (%s) coast=%.0f m: %s\n', ...
                    seg_idx, seg.segment_name, coasting_pt, msg);

            v.segment_idx      = seg_idx;
            v.segment_name     = seg.segment_name;
            v.coasting_point   = coasting_pt;
            v.distance         = [];
            v.speed_trace      = [];
            v.fuel_saved_kg    = NaN;
            v.time_penalty_sec = NaN;
            v.details          = struct('fail_reason', msg, ...
                                        'coasting_start_dist', NaN, ...
                                        'coasting_end_dist',   NaN, ...
                                        'v0_kmh', NaN, 'v_rejoin_kmh', NaN, ...
                                        'dt_original_sec', NaN, 'dt_coasted_sec', NaN);
            v.status           = 'fail';
            variants = [variants, v];
        end
    end
end

fprintf('Generated %d variants\n', variant_count);

%% Step 6: Compute strategy summary
fprintf('\n[6/7] Computing strategy summary...\n');
strategy_table = smp_compute_fuel_save_strategy(variants, segments);
fprintf('Strategy table: %d rows\n', height(strategy_table));

% Write strategy to Excel
strategy_file = fullfile(params.output_dir, 'smp_fuel_save_strategy.xlsx');
writetable(strategy_table, strategy_file);
fprintf('Strategy saved: %s\n', strategy_file);

%% Step 7: Generate visualizations
fprintf('\n[7/7] Generating visualizations...\n');
plot_prec = [];
if prec_ok, plot_prec = preceding_lap; end
smp_plot_fuel_save_variants(variants, segments, lap, params.output_dir, ...
    'fuel_rate', params.fuel_rate, 'lap_time', lap.lap_time, ...
    'preceding_lap', plot_prec);
fprintf('Plots saved to: %s\n', params.output_dir);

fprintf('\n=== Analysis Complete ===\n');
fprintf('Output directory: %s\n', params.output_dir);

output_dir = params.output_dir;
% lap and preceding_lap are already in workspace from Steps 2-3 — returned as 4th/5th outputs.
% If preceding lap was not loaded, return empty struct.
if ~prec_ok
    preceding_lap = [];
end

end

%% Helper: Select fastest lap
function [lap, group_key, lap_idx] = smp_select_fastest_lap(cache, driver_tla)
    if isempty(driver_tla)
        % Global fastest: search all groups
        best_time = inf;
        best_group = '';
        best_idx = 0;
        
        groups = fieldnames(cache.traces);
        for g = 1:length(groups)
            gk = groups{g};
            times = cache.traces.(gk).lap_times;
            [t_best, idx_best] = min(times);
            if t_best < best_time
                best_time = t_best;
                best_group = gk;
                best_idx = idx_best;
            end
        end
        
        group_key = best_group;
        lap_idx = best_idx;
    else
        % Find by driver TLA: search for group containing driver_tla
        groups = fieldnames(cache.traces);
        found = false;
        for g = 1:length(groups)
            gk = groups{g};
            if contains(gk, driver_tla, 'IgnoreCase', true)
                times = cache.traces.(gk).lap_times;
                [~, idx_best] = min(times);
                group_key = gk;
                lap_idx = idx_best;
                found = true;
                break;
            end
        end
        if ~found
            error('Driver TLA ''%s'' not found in cache', driver_tla);
        end
    end
    
    % Reconstruct lap struct from cache traces
    lap = smp_reconstruct_lap_from_cache(cache, group_key, lap_idx);
end

%% Helper: Reconstruct lap from cache
function lap = smp_reconstruct_lap_from_cache(cache, group_key, lap_idx)
    % Extract traces for this lap from cache
    % Structure: traces.(channel_name)(lap_idx).data, .dist
    
    lap.lap_number = lap_idx;
    lap.lap_time = cache.traces.(group_key).lap_times(lap_idx);
    lap.group_key = group_key;
    lap.channels = struct();
    
    % List of all channels in this group
    channel_names = fieldnames(cache.traces.(group_key));
    
    fprintf('  Reconstructing lap from %d channels...\n', length(channel_names));
    channels_loaded = 0;
    
    for c = 1:length(channel_names)
        ch_name = channel_names{c};
        
        % Skip metadata fields
        if ismember(ch_name, {'lap_times', 'lap_numbers', 'n_traces'})
            continue;
        end
        
        try
            % Get channel struct array: traces.(ch_name) is a struct array
            traces_ch = cache.traces.(group_key).(ch_name);
            
            % traces_ch should be a struct array; access by lap_idx
            if isstruct(traces_ch) && length(traces_ch) >= lap_idx
                trace_data = traces_ch(lap_idx);
                
                % Check if it has .data field
                if isstruct(trace_data) && isfield(trace_data, 'data')
                    % Store as simple struct with .data and .dist
                    lap.channels.(ch_name).data = trace_data.data(:);
                    if isfield(trace_data, 'dist')
                        lap.channels.(ch_name).dist = trace_data.dist(:);
                    else
                        % Synthesize distance if not available
                        lap.channels.(ch_name).dist = (0:length(trace_data.data)-1)';
                    end
                    channels_loaded = channels_loaded + 1;
                end
            end
        catch
            % Skip channels that can't be accessed
        end
    end
    
    fprintf('  Loaded %d channels\n', channels_loaded);
    
    % Map potential channel name variations to standard names
    channel_aliases = {
        'Distance',  'Lap_Distance',    'Odometer',          'Trip_Distance';
        'Speed',     'Ground_Speed',    '',                  '';
        'Throttle',  'Throttle_Pedal',  'Throttle_Position', '';
        'Brake',     'Brake_Pressure_Front', '',             '';
    };
    
    % Standardize channel names
    for row = 1:size(channel_aliases, 1)
        standard_name = channel_aliases{row, 1};
        if ~isfield(lap.channels, standard_name)
            for col = 2:size(channel_aliases, 2)
                alt_name = channel_aliases{row, col};
                if ~isempty(alt_name) && isfield(lap.channels, alt_name)
                    lap.channels.(standard_name) = lap.channels.(alt_name);
                    break;
                end
            end
        end
    end
    
    % Validate essential channels
    required = {'Distance', 'Speed', 'Throttle', 'Brake'};
    missing = {};
    for i = 1:length(required)
        if ~isfield(lap.channels, required{i})
            missing = [missing, required{i}];
        end
    end
    
    if ~isempty(missing)
        warning('Missing channels: %s', strjoin(missing, ', '));
    end
    
    if channels_loaded < 2
        error('Too few channels loaded (%d). Cache structure may be invalid.', channels_loaded);
    end
end
