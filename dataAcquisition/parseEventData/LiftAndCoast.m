function LiftAndCoast(event, varargin)
% LIFTANDCOAST  Lift-and-coast analysis for a given event
%
% USAGE:
%   LiftAndCoast('04_RUA')
%   LiftAndCoast('04_RUA', 'session_id', 'Q13', 'driver_tla', 'JAC')
%   LiftAndCoast('04_RUA', 'visible', false)
%   LiftAndCoast('04_RUA', 'year', 2025, 'rerun', true)
%
% REQUIRED PARAMETERS:
%   event          (string)  Event code, e.g. '04_RUA'
%
% OPTIONAL NAME-VALUE PARAMETERS:
%   year           (numeric) Championship year                        [default: 2026]
%   session_id     (string)  Session name, e.g. 'Q13'                [default: 'Q13']
%   driver_tla     (string)  Driver TLA; empty = global fastest       [default: '']
%   accel          (double)  Coast deceleration m/s²                 [default: -11.5/3.6]
%   fuel_rate      (double)  Fuel rate kg/s                          [default: 2.5/1000]
%   auto_detect    (logical) Auto-detect segments                     [default: true]
%   config_file    (string)  Excel config path; empty = auto-generate [default: '']
%   rerun          (logical) Skip plot + reuse existing Excel         [default: false]
%   run_diagnostic (logical) Inspect cache structure first           [default: false]
%   time_budget    (double)  Lap-time loss budget (s) for cross-segment
%                            optimisation. NaN = no constraint (max fuel).
%                            [default: NaN]
%   fuel_targets   (double array) Target fuel savings in kg, e.g. [0.1 0.2 0.3].
%                            For each target, finds the most time-efficient
%                            combination and plots the full lap speed trace.
%                            Empty = disabled.                        [default: []]
%   visible        (logical) Show plots on screen.
%                            false = all figures saved to disk only.  [default: true]

%% PARSE INPUTS
p = inputParser;
addRequired(p,  'event',                                @ischar);
addParameter(p, 'year',          2026,                  @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'session_id',    'Q13',                 @ischar);
addParameter(p, 'driver_tla',    '',                    @ischar);
addParameter(p, 'accel',         -11.5/3.6,             @isnumeric);
addParameter(p, 'fuel_rate',     2.5/1000,              @isnumeric);
addParameter(p, 'auto_detect',   true,                  @islogical);
addParameter(p, 'config_file',   '',                    @ischar);
addParameter(p, 'rerun',         false,                 @islogical);
addParameter(p, 'run_diagnostic',false,                 @islogical);
addParameter(p, 'time_budget',   NaN,                   @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'fuel_targets',  [],                    @isnumeric);
addParameter(p, 'visible',       true,                  @islogical);
parse(p, event, varargin{:});

r              = p.Results;
year_val       = r.year;
session_id     = r.session_id;
driver_tla     = r.driver_tla;
accel          = r.accel;
fuel_rate      = r.fuel_rate;
auto_detect    = r.auto_detect;
config_file    = r.config_file;
rerun          = r.rerun;
run_diagnostic = r.run_diagnostic;
time_budget    = r.time_budget;
fuel_targets   = r.fuel_targets;
visible        = r.visible;

%% BUILD PATHS FROM EVENT + YEAR
base_path  = fullfile('E:\', num2str(year_val), event);
cache_dir  = fullfile(base_path, '_TeamData');
output_dir = fullfile(base_path, 'Strategy');

%% FIGURE VISIBILITY
% Save the current default and override if the caller wants save-only mode.
prev_vis = get(groot, 'DefaultFigureVisible');
if ~visible
    set(groot, 'DefaultFigureVisible', 'off');
end
% Restore on exit (error or normal)
cleanup = onCleanup(@() set(groot, 'DefaultFigureVisible', prev_vis));  %#ok<NASGU>

%% HEADER
clc;
fprintf('\n');
fprintf('===========================================\n');
fprintf('  Lift-and-Coast Analysis\n');
fprintf('===========================================\n\n');

fprintf('Settings:\n');
fprintf('  Event:       %s (%d)\n', event, year_val);
fprintf('  Cache dir:   %s\n', cache_dir);
fprintf('  Output dir:  %s\n', output_dir);
fprintf('  Session:     %s\n', session_id);
fprintf('  Driver:      %s\n', ifelse(isempty(driver_tla), '(global fastest)', driver_tla));
fprintf('  Accel:       %.2f m/s²\n', accel);
fprintf('  Fuel Rate:   %.4f kg/s\n', fuel_rate);
fprintf('  Auto-Detect: %s\n', ifelse(auto_detect, 'Yes', 'No'));
fprintf('  Plots:       %s\n\n', ifelse(visible, 'on screen', 'save to disk only'));

%% OPTIONAL: Run diagnostic
if run_diagnostic
    fprintf('\n>>> Running cache diagnostic...\n\n');
    smp_cache_inspect(cache_dir, session_id);
    fprintf('\n>>> Diagnostic complete. Continuing with analysis...\n\n');
end

%% RUN ANALYSIS
try
    [variants, segments, output_dir, lap, preceding_lap] = smp_fuel_save_coasting(...
        'cache_dir',  cache_dir, ...
        'session_id', session_id, ...
        'driver_tla', driver_tla, ...
        'output_dir', output_dir, ...
        'accel',      accel, ...
        'fuel_rate',  fuel_rate, ...
        'auto_detect',auto_detect, ...
        'config_file',config_file, ...
        'rerun',      rerun);

    %% PRINT RESULTS SUMMARY
    fprintf('\n');
    fprintf('===========================================\n');
    fprintf('  RESULTS SUMMARY\n');
    fprintf('===========================================\n\n');

    % Group by segment
    unique_segs        = unique([variants.segment_idx]);
    total_fuel         = 0;
    total_time_penalty = 0;

    for seg = unique_segs
        seg_variants = variants([variants.segment_idx] == seg);
        seg_struct   = segments(seg);

        fprintf('Segment %d: %s\n', seg, seg_struct.segment_name);
        fprintf('  Brake marker: %.0f m\n', seg_struct.brake_marker);
        fprintf('  Variants: %d\n', length(seg_variants));

        successful = seg_variants(strcmp({seg_variants.status}, 'success'));
        if ~isempty(successful)
            fuel_saved_seg   = [successful.fuel_saved_kg];
            time_penalty_seg = [successful.time_penalty_sec];

            fprintf('    Fuel saved range:   %.4f – %.4f kg\n', min(fuel_saved_seg), max(fuel_saved_seg));
            fprintf('    Time penalty range: %.3f – %.3f sec\n', min(time_penalty_seg), max(time_penalty_seg));
            fprintf('    Best ratio:         %.4f kg/sec\n', max(fuel_saved_seg ./ (time_penalty_seg + 1e-6)));

            total_fuel         = total_fuel         + max(fuel_saved_seg);
            total_time_penalty = total_time_penalty + max(time_penalty_seg);
        end
        fprintf('\n');
    end

    fprintf('TOTAL (summed best per segment):\n');
    fprintf('  Fuel Saved:   %.4f kg\n', total_fuel);
    fprintf('  Time Penalty: %.3f sec\n', total_time_penalty);
    fprintf('  Trade-off:    %.4f kg/sec\n\n', total_fuel / (total_time_penalty + 1e-6));

    %% CROSS-SEGMENT OPTIMISATION
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
            'output_dir',    output_dir, ...
            'preceding_lap', preceding_lap);
    end

    %% OUTPUT FILE LIST
    fprintf('Output files:\n');
    fprintf('  - %s/smp_fuel_save_config.xlsx\n',                    output_dir);
    fprintf('  - %s/smp_fuel_save_strategy.xlsx\n',                  output_dir);
    fprintf('  - %s/smp_fuel_save_speed_traces_by_segment.png\n',    output_dir);
    fprintf('  - %s/smp_fuel_save_trade_off_analysis.png\n',         output_dir);
    fprintf('  - %s/smp_fuel_save_coasting_sensitivity.png\n',       output_dir);
    fprintf('  - %s/smp_fuel_save_pareto.png\n',                     output_dir);
    fprintf('  - %s/smp_fuel_save_optimal.xlsx\n',                   output_dir);
    fprintf('  - %s/smp_doe_top_combinations.xlsx\n',                output_dir);
    fprintf('  - %s/smp_doe_scatter.png\n',                          output_dir);
    if ~isempty(fuel_targets)
        fprintf('  - %s/smp_target_fuel_save.xlsx\n',                output_dir);
        fprintf('  - %s/smp_target_fuel_save_traces.png\n',          output_dir);
        fprintf('  - %s/smp_target_fuel_save_delta.png\n',           output_dir);
    end
    fprintf('\n');

    fprintf('=== COMPLETE ===\n\n');

catch ME
    fprintf('\nERROR: %s\n', ME.message);
    fprintf('Stack:\n');
    disp(ME.stack);
end

end

%% Helper: inline if-else
function result = ifelse(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end
