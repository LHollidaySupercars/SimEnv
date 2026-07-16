%% SMP PLOTTING SCRIPT
% Lap time filter (hard-coded for SMP data): 85s – 115s

%% ---- 0. Setup --------------------------------------------------------
% addpath(pwd);   % ensure all smp_*.m functions are on path

% Manufacturer colours (Ford Blue / Chev Yellow / Toyota Red)
cfg = smp_colours();

% Driver colours — loaded from alias file
driver_map = smp_driver_alias_load('C:\SimEnv\dataAcquisition\Motec_MP\driverAlias.xlsx');

%% ---- 1. Load & filter SMP data --------------------------------------
[SMP, ~] = smp_load_teams('C:\LOCAL_DATA\01 - SMP\_Team Data', {});
%%

alias       = smp_alias_load('C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx');
SMP_filtered = smp_filter(SMP, alias, 'Session', 'RA1');

smp_filter_summary(SMP_filtered);

%% ---- 2. Load plot config from Excel ---------------------------------
% Columns: plotName | plotType | mathFunction | xAxis | yAxis1 | yAxis2 |
%          yAxis3 | yAxis4 | zAxis | colours | differentiator | useSecondary | plotFilter

PLOT_CONFIG_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest.xlsx';
plots = smp_plot_config_load(PLOT_CONFIG_FILE);

%% ---- 3. Configure options -------------------------------------------
plot_opts = struct();
plot_opts.min_lap_time  = 85;     % SMP lap time filter
plot_opts.max_lap_time  = 115;
plot_opts.n_laps_avg    = 3;      % N-lap average for timeseries plots
plot_opts.verbose       = true;
plot_opts.fig_width     = 1200;
plot_opts.fig_height    = 650;
plot_opts.font_size     = 11;
plot_opts.dist_channel  = 'Odometer';
plot_opts.dist_n_points = 1000;
% plot_opts.save_path   = 'C:\Reports\Plots';   % uncomment to auto-save PNGs

%% ---- 4. Generate all plots ------------------------------------------
figs = smp_plot_from_config(SMP_filtered, plots, cfg, driver_map, plot_opts);

% Make visible to inspect
for i = 1:numel(figs)
    if ~isempty(figs{i})
        set(figs{i}, 'Visible', 'on');
    end
end

%% ---- (Optional) Save individual figure manually ---------------------
% exportgraphics(figs{1}, 'C:\Reports\falling_max_speed.png', 'Resolution', 150);