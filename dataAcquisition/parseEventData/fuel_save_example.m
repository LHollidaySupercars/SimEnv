function fuel_save_example(varargin)
% FUEL_SAVE_EXAMPLE Quick-start example for fuel saving analysis
%
% USAGE:
%   fuel_save_example()
%   fuel_save_example('session_id', 'R1', 'driver_tla', 'JAC')
%   fuel_save_example('rerun', true)
%
% OPTIONAL NAME-VALUE PARAMETERS:
%   cache_dir      (string)  Directory containing smp_cache_*.mat  [default: 'E:\2026\04_RUA\_TeamData']
%   session_id     (string)  Session name, e.g. 'Q13'              [default: 'Q13']
%   driver_tla     (string)  Driver TLA; empty = global fastest     [default: '']
%   output_dir     (string)  Where to save results                  [default: 'E:\2026\04_RUA\Strategy']
%   accel          (double)  Coast deceleration m/s²               [default: -11.5/3.6]
%   fuel_rate      (double)  Fuel rate kg/s                        [default: 2.5/1000]
%   auto_detect    (logical) Auto-detect segments                   [default: true]
%   config_file    (string)  Excel config path; empty = generate   [default: '']
%   rerun          (logical) Skip plot + reuse existing Excel       [default: false]
%   run_diagnostic (logical) Inspect cache structure first         [default: false]
%   time_budget    (double)  Lap-time loss budget (s) for cross-segment
%                            optimisation. NaN = no constraint (max fuel).
%                            [default: NaN]
%   fuel_targets   (double array) Target fuel savings in kg, e.g. [0.1 0.2 0.3].
%                            For each target, finds the most time-efficient
%                            combination and plots the full lap speed trace.
%                            Empty = disabled.  [default: []]

%% SETUP
p = inputParser;
addParameter(p, 'cache_dir',      'E:\2026\04_RUA\_TeamData', @ischar);
addParameter(p, 'session_id',     'Q13',                      @ischar);
addParameter(p, 'driver_tla',     '',                         @ischar);
addParameter(p, 'output_dir',     'E:\2026\04_RUA\Strategy',  @ischar);
addParameter(p, 'accel',          -11.5/3.6,                  @isnumeric);
addParameter(p, 'fuel_rate',      2.5/1000,                   @isnumeric);
addParameter(p, 'auto_detect',    true,                       @islogical);
addParameter(p, 'config_file',    '',                         @ischar);
addParameter(p, 'rerun',          false,                      @islogical);
addParameter(p, 'run_diagnostic', false,                      @islogical);
addParameter(p, 'time_budget',    NaN,                        @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'fuel_targets',   [],                         @(x) isnumeric(x));
parse(p, varargin{:});

cache_dir      = p.Results.cache_dir;
session_id     = p.Results.session_id;
driver_tla     = p.Results.driver_tla;
output_dir     = p.Results.output_dir;
accel          = p.Results.accel;
fuel_rate      = p.Results.fuel_rate;
auto_detect    = p.Results.auto_detect;
config_file    = p.Results.config_file;
rerun          = p.Results.rerun;
run_diagnostic = p.Results.run_diagnostic;
time_budget    = p.Results.time_budget;
fuel_targets   = p.Results.fuel_targets;

clc;
fprintf('\n');
fprintf('===========================================\n');
fprintf('  Fuel-Saving Coasting Analysis v1.0\n');
fprintf('===========================================\n\n');

fprintf('Settings:\n');
fprintf('  Cache dir: %s\n', cache_dir);
fprintf('  Session:   %s\n', session_id);
fprintf('  Driver: %s\n', ifelse(isempty(driver_tla), '(global fastest)', driver_tla));
fprintf('  Accel: %.2f m/s²\n', accel);
fprintf('  Fuel Rate: %.4f kg/s\n', fuel_rate);
fprintf('  Auto-Detect: %s\n', ifelse(auto_detect, 'Yes', 'No'));
fprintf('  Output: %s\n\n', output_dir);

%% OPTIONAL: Run diagnostic
if run_diagnostic
    fprintf('\n>>> Running cache diagnostic...\n\n');
    smp_cache_inspect(cache_dir, session_id);
    fprintf('\n>>> Diagnostic complete. Continuing with analysis...\n\n');
end

%% RUN ANALYSIS
try
    [variants, segments, output_dir, lap, preceding_lap] = smp_fuel_save_coasting(...
        'cache_dir', cache_dir, ...
        'session_id', session_id, ...
        'driver_tla', driver_tla, ...
        'output_dir', output_dir, ...
        'accel', accel, ...
        'fuel_rate', fuel_rate, ...
        'auto_detect', auto_detect, ...
        'config_file', config_file, ...
        'rerun', rerun);
    
    %% PRINT RESULTS SUMMARY
    fprintf('\n');
    fprintf('===========================================\n');
    fprintf('  RESULTS SUMMARY\n');
    fprintf('===========================================\n\n');
    
    % Group by segment
    unique_segs = unique([variants.segment_idx]);
    total_fuel = 0;
    total_time_penalty = 0;
    
    for seg = unique_segs
        seg_variants = variants([variants.segment_idx] == seg);
        seg_struct = segments(seg);
        
        fprintf('Segment %d: %s\n', seg, seg_struct.segment_name);
        fprintf('  Brake marker: %.0f m\n', seg_struct.brake_marker);
        fprintf('  Variants: %d\n', length(seg_variants));
        
        successful = [seg_variants([strcmp({seg_variants.status}, 'success')])];
        if ~isempty(successful)
            fuel_saved_seg = [successful.fuel_saved_kg];
            time_penalty_seg = [successful.time_penalty_sec];
            
            fprintf('    Fuel saved range: %.4f - %.4f kg\n', min(fuel_saved_seg), max(fuel_saved_seg));
            fprintf('    Time penalty range: %.3f - %.3f sec\n', min(time_penalty_seg), max(time_penalty_seg));
            fprintf('    Best ratio: %.4f kg/sec\n', max(fuel_saved_seg ./ (time_penalty_seg + 1e-6)));
            
            total_fuel = total_fuel + max(fuel_saved_seg);
            total_time_penalty = total_time_penalty + max(time_penalty_seg);
        end
        fprintf('\n');
    end
    
    fprintf('TOTAL (summed best per segment):\n');
    fprintf('  Fuel Saved: %.4f kg\n', total_fuel);
    fprintf('  Time Penalty: %.3f sec\n', total_time_penalty);
    fprintf('  Trade-off: %.4f kg/sec\n\n', total_fuel / (total_time_penalty + 1e-6));

    %% RUN CROSS-SEGMENT OPTIMISATION
    fprintf('===========================================\n');
    fprintf('  CROSS-SEGMENT OPTIMISATION\n');
    fprintf('===========================================\n\n');
    [optimal, pareto_curve] = smp_optimize_fuel_save(variants, segments, ...  %#ok<ASGLU>
        'time_budget', time_budget, ...
        'output_dir',  output_dir);

    %% FULL DOE — ALL COMBINATIONS
    fprintf('===========================================\n');
    fprintf('  FULL DOE — ALL LIFT-AND-COAST COMBINATIONS\n');
    fprintf('===========================================\n\n');
    doe = smp_doe_fuel_save(variants, segments, ...  %#ok<NASGU>
        'output_dir', output_dir);

    %% TARGET FUEL SAVING ANALYSIS
    if ~isempty(fuel_targets)
        fprintf('===========================================\n');
        fprintf('  TARGET FUEL SAVING ANALYSIS\n');
        fprintf('===========================================\n\n');
        smp_target_fuel_save(variants, segments, lap, fuel_targets, ...
            'output_dir',     output_dir, ...
            'preceding_lap',  preceding_lap);
    end

    fprintf('Output files:\n');
    fprintf('  - %s/smp_fuel_save_config.xlsx\n', output_dir);
    fprintf('  - %s/smp_fuel_save_strategy.xlsx\n', output_dir);
    fprintf('  - %s/smp_fuel_save_speed_traces_by_segment.png\n', output_dir);
    fprintf('  - %s/smp_fuel_save_trade_off_analysis.png\n', output_dir);
    fprintf('  - %s/smp_fuel_save_coasting_sensitivity.png\n', output_dir);
    fprintf('  - %s/smp_fuel_save_pareto.png\n', output_dir);
    fprintf('  - %s/smp_fuel_save_optimal.xlsx\n', output_dir);
    fprintf('  - %s/smp_doe_top_combinations.xlsx\n', output_dir);
    fprintf('  - %s/smp_doe_scatter.png\n', output_dir);
    if ~isempty(fuel_targets)
        fprintf('  - %s/smp_target_fuel_save.xlsx\n', output_dir);
        fprintf('  - %s/smp_target_fuel_save_traces.png\n', output_dir);
        fprintf('  - %s/smp_target_fuel_save_delta.png\n', output_dir);
    end
    fprintf('\n');

    fprintf('=== COMPLETE ===\n\n');
    
catch ME
    fprintf('\nERROR: %s\n', ME.message);
    fprintf('Stack:\n');
    disp(ME.stack);
end

end

%% Helper: Inline if-else
function result = ifelse(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end
