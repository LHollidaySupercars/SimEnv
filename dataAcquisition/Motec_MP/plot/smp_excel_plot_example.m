%% SMP_EXCEL_PLOT_EXAMPLE
% Demonstrates the full workflow:
%   Excel sheet → smp_read_excel → smp_excel_filter → smp_plot
%
% Excel sheet expected columns (names are flexible, see smp_read_excel):
%   Car | Driver | Team | Manufacturer | Session | Lap | Outing | <channel cols>
%
% Channel columns can be anything — max speed, peak brake, avg throttle, etc.
% The math is already done in the sheet; we just plot it here.

%% ---- 0. Config -------------------------------------------------------
EXCEL_FILE = 'C:\Reports\SMP_R1_Data.xlsx';

% The channel column name in your Excel sheet you want to plot
CHANNEL_COL = 'Max Speed';   % e.g. 'Peak Brake Front', 'Avg Throttle', etc.

cfg = smp_colours();          % manufacturer colour definitions

%% ---- 1. Load Excel ---------------------------------------------------
data = smp_read_excel(EXCEL_FILE);

%% ---- 2. Inspect full dataset ----------------------------------------
smp_excel_summary(data);

%% ---- 3. Filter -------------------------------------------------------
% Example: all manufacturers, Race 1 only
data_r1 = smp_excel_filter(data, 'Session', 'Race 1');
smp_excel_summary(data_r1);

% Example: just Ford in Race 1
% data_ford = smp_excel_filter(data, 'Manufacturer', 'Ford', 'Session', 'Race 1');

%% ---- 4a. TRACE — outing-wise or fastest-lap-wise --------------------
% For a trace plot you need x (distance or time) and y (channel) per dataset.
% Two modes are shown: outing-wise and fastest-lap-wise.
%
% This example assumes your Excel has:
%   'Distance' column  AND  the CHANNEL_COL column  AND  'Outing' column.

T     = data_r1.table;
cols  = data_r1.cols;

% Group by driver
drivers = unique(T.(cols.driver));

plot_data   = {};
labels      = {};
colour_keys = {};
leg_info    = {};

for d = 1:numel(drivers)
    drv  = drivers{d};
    mask = strcmp(T.(cols.driver), drv);
    rows = T(mask, :);

    % ---- OUTING-WISE: concatenate all data for this driver ----
    % (comment this block and use the lap-wise block below to switch modes)
    if ~isempty(cols.outing) && ismember(cols.outing, rows.Properties.VariableNames)
        outings = unique(rows.(cols.outing));
        for o = 1:numel(outings)
            omask = rows.(cols.outing) == outings(o);
            orows = rows(omask,:);
            pd.x  = orows.Distance;         % adjust column name as needed
            pd.y  = orows.(CHANNEL_COL);
            plot_data{end+1}   = pd;         %#ok
            labels{end+1}      = sprintf('%s  Out %d', drv, outings(o)); %#ok
            colour_keys{end+1} = strtrim(char(string(rows.(cols.manufacturer)(1)))); %#ok
            leg_info{end+1}    = sprintf('Car %s', strtrim(char(string(rows.(cols.car)(1))))); %#ok
        end
    else
        % No outing column — treat all rows as one trace
        pd.x = rows.Distance;
        pd.y = rows.(CHANNEL_COL);
        plot_data{end+1}   = pd;
        labels{end+1}      = drv;
        colour_keys{end+1} = strtrim(char(string(rows.(cols.manufacturer)(1))));
        leg_info{end+1}    = sprintf('Car %s', strtrim(char(string(rows.(cols.car)(1)))));
    end
end

opts_trace            = struct();
opts_trace.title      = sprintf('Trace: %s  —  Race 1', CHANNEL_COL);
opts_trace.xLabel     = 'Distance (m)';
opts_trace.yLabel     = CHANNEL_COL;
opts_trace.colourMode = 'manufacturer';
opts_trace.legendInfo = leg_info;

fig_trace = smp_plot('trace', plot_data, labels, colour_keys, cfg, opts_trace);
% saveas(fig_trace, 'C:\Reports\trace_race1.png');


%% ---- 4b. TRACE — fastest lap per driver (lap-wise) -----------------
% If your Excel has lap-level rows with Distance + channel, find fastest lap
% per driver by lap time and plot only that lap.

if ~isempty(cols.lap_time) && ismember(cols.lap_time, T.Properties.VariableNames)

    plot_data_fl   = {};
    labels_fl      = {};
    colour_keys_fl = {};
    leg_info_fl    = {};

    for d = 1:numel(drivers)
        drv  = drivers{d};
        mask = strcmp(T.(cols.driver), drv);
        rows = T(mask, :);

        if isempty(rows), continue; end

        % Find fastest lap — minimum lap time
        lap_times = rows.(cols.lap_time);
        if iscell(lap_times), lap_times = cellfun(@str2double, lap_times); end
        [~, best_idx] = min(lap_times);

        best_lap_num = rows.(cols.lap)(best_idx);
        lap_mask     = rows.(cols.lap) == best_lap_num;
        best_lap     = rows(lap_mask, :);

        pd.x = best_lap.Distance;       % adjust column name as needed
        pd.y = best_lap.(CHANNEL_COL);

        mfr = strtrim(char(string(rows.(cols.manufacturer)(1))));
        car = strtrim(char(string(rows.(cols.car)(1))));
        lt  = lap_times(best_idx);

        plot_data_fl{end+1}   = pd;   %#ok
        labels_fl{end+1}      = drv;  %#ok
        colour_keys_fl{end+1} = mfr;  %#ok
        leg_info_fl{end+1}    = sprintf('Car %s  | Lap %d  | %.3fs', car, best_lap_num, lt); %#ok
    end

    opts_fl            = struct();
    opts_fl.title      = sprintf('Fastest Lap: %s  —  Race 1', CHANNEL_COL);
    opts_fl.xLabel     = 'Distance (m)';
    opts_fl.yLabel     = CHANNEL_COL;
    opts_fl.colourMode = 'manufacturer';
    opts_fl.legendInfo = leg_info_fl;

    fig_fl = smp_plot('trace', plot_data_fl, labels_fl, colour_keys_fl, cfg, opts_fl);
end


%% ---- 5. LAPMAX — session overview of per-lap peak value ------------
% Assumes Excel has one row per lap with a 'Lap' column and your channel.
% Shows how the value evolves across the session for each driver.

plot_data_lm   = {};
labels_lm      = {};
colour_keys_lm = {};
leg_info_lm    = {};

for d = 1:numel(drivers)
    drv  = drivers{d};
    mask = strcmp(T.(cols.driver), drv);
    rows = T(mask, :);
    if isempty(rows), continue; end

    % Expect one row per lap with the channel value already computed
    % (e.g. 'Max Speed' column = max speed of that lap, done in Excel)
    if ~isempty(cols.lap) && ismember(CHANNEL_COL, rows.Properties.VariableNames)
        laps = rows.(cols.lap);
        vals = rows.(CHANNEL_COL);
        if iscell(laps), laps = cellfun(@str2double, laps); end
        if iscell(vals), vals = cellfun(@str2double, vals); end

        pd.laps   = laps;
        pd.values = vals;

        mfr = strtrim(char(string(rows.(cols.manufacturer)(1))));
        car = strtrim(char(string(rows.(cols.car)(1))));

        plot_data_lm{end+1}   = pd;   %#ok
        labels_lm{end+1}      = drv;  %#ok
        colour_keys_lm{end+1} = mfr;  %#ok
        leg_info_lm{end+1}    = sprintf('Car %s', car); %#ok
    end
end

opts_lm              = struct();
opts_lm.title        = sprintf('Session Overview: %s per Lap  —  Race 1', CHANNEL_COL);
opts_lm.xLabel       = 'Lap';
opts_lm.yLabel       = CHANNEL_COL;
opts_lm.colourMode   = 'manufacturer';
opts_lm.showMarkers  = true;
opts_lm.legendInfo   = leg_info_lm;

fig_lm = smp_plot('lapmax', plot_data_lm, labels_lm, colour_keys_lm, cfg, opts_lm);
% saveas(fig_lm, 'C:\Reports\lapmax_race1.png');
