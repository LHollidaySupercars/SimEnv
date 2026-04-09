%% =========================================================
%  MAIN SMP REPORT — Parallel Entry Point
%  =========================================================
%  Same as main_smp_report.m but uses parallel workers for
%  the compile step. Everything after Section 6 is identical.
%
%  WORKFLOW:
%    Step 1 — Edit CONFIG section below
%    Step 2 — Run entire script (or section by section)
%    Step 3 — Plots appear; PPTX saved to output folder
% =========================================================

clear; clc; close all;

%% =========================================================
%  SECTION 1: PATHS
% =========================================================

TOP_LEVEL_DIR   = 'E:\2026\02_AGP - Copy\_Team Data';

CHANNELS_FILE    = 'C:\SimEnv\dataAcquisition\Motec_MP\channels.xlsx';
EVENT_ALIAS_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx';
DRIVER_ALIAS_FILE= 'C:\SimEnv\dataAcquisition\Motec_MP\driverAlias.xlsx';
PLOT_CONFIG_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_BV_recreate.xlsx';
PLOT_CONFIG_FILE= 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_Align.xlsx';  % *** REPLACE ***
SEASON_FILE      = 'C:\SimEnv\trackDB\seasonOverview.xlsx';

PPTX_TEMPLATE   = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\templates\SuperCars_PPT.pptx';
OUTPUT_DIR      = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\output';
OUTPUT_FILENAME = 'AGP_Report';
CREATE_PITSTOP_REPORT = 0;
saveFile = 0; 
%% =========================================================
%  SECTION 2: EVENT CONFIG
% =========================================================

TRACK          = 'AGP';
TEAM_FILTER    = {};
SESSION_FILTER = {'QU6', 'QU7'};
N_WORKERS       = 4;
%% =========================================================
%  SECTION 3: PROCESSING OPTIONS
% =========================================================

% Parallel options

TMP_DIR         = fullfile(tempdir, 'smp_parallel');
POLL_INTERVAL_S = 3;
TIMEOUT_S       = 3600;

compile_opts.mode          = 'stream';
compile_opts.track         = TRACK;
compile_opts.max_traces    = 5;
compile_opts.dist_n_points = 1000;
compile_opts.dist_channel  = 'Odometer';
compile_opts.verbose       = true;
compile_opts.date_from     = datetime(2026, 2, 5);

plot_opts.fig_width     = 1200;
plot_opts.fig_height    = 650;
plot_opts.font_size     = 11;
plot_opts.n_laps_avg    = 3;
plot_opts.verbose       = true;
plot_opts.venue         = TRACK;

%% =========================================================
%  SECTION 4: LOAD CONFIG FILES
% =========================================================
fprintf('=== SMP Report (Parallel) — %s ===\n\n', TRACK);

season     = smp_season_load(SEASON_FILE);
channels   = smp_channel_config_load(CHANNELS_FILE);
alias      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map = smp_driver_alias_load(DRIVER_ALIAS_FILE);
cfg        = smp_colours();

%% =========================================================
%  SECTION 5: PARALLEL COMPILE
% =========================================================

% ---- Prep tmp dir ----
if ~exist(TMP_DIR, 'dir'), mkdir(TMP_DIR); end
delete(fullfile(TMP_DIR, 'partial_*.mat'));
delete(fullfile(TMP_DIR, 'done_*.flag'));
delete(fullfile(TMP_DIR, 'chunk_*.mat'));
delete(fullfile(TMP_DIR, 'worker_cfg.mat'));

fprintf('============================================\n');
fprintf('  Parallel Compile\n');
fprintf('  Workers : %d\n', N_WORKERS);
fprintf('  TMP     : %s\n', TMP_DIR);
fprintf('  Time    : %s\n', datestr(now, 'HH:MM:SS'));
fprintf('============================================\n\n');

% ---- Scan and diff ----
scan_all = smp_scan_folders(TOP_LEVEL_DIR);
if ~isempty(TEAM_FILTER)
    keep     = ismember({scan_all.acronym}, TEAM_FILTER);
    scan_all = scan_all(keep);
end

cache = smp_cache_load(TOP_LEVEL_DIR);

% Migrate old cache structure if needed (mirrors smp_compile_event)
% Migrate old cache structure if needed (mirrors smp_compile_event)
if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
if ~isfield(cache, 'traces'), cache.traces = struct(); end
if ~isfield(cache, 'mode'),   cache.mode   = 'stream'; end   % <-- add this
if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
    cache.manifest.GroupKey = repmat({''}, height(cache.manifest), 1);
end

% Apply date_from filter to scan_all
if isfield(compile_opts, 'date_from') && ~isempty(compile_opts.date_from)
    date_from_dn = datenum(compile_opts.date_from);
    for i = 1:numel(scan_all)
        files = scan_all(i).files;
        keep  = false(1, numel(files));
        for j = 1:numel(files)
            d = dir(files{j});
            keep(j) = ~isempty(d) && d(1).datenum >= date_from_dn;
        end
        scan_all(i).files = files(keep);
    end
    scan_all = scan_all(arrayfun(@(t) ~isempty(t.files), scan_all));
end

[to_load, cache] = smp_cache_diff(cache, scan_all);

if isempty(to_load)
    fprintf('All files up to date - nothing to compile.\n\n');
else
    fprintf('%d file(s) to process.\n', numel(to_load));

    groups   = smp_append_stints(to_load, driver_map, alias);
    n_groups = numel(groups);
    fprintf('%d group(s) across %d worker(s).\n\n', n_groups, N_WORKERS);

    % ---- Split groups ----
    chunk_size = ceil(n_groups / N_WORKERS);
    for w = 1:N_WORKERS
        i_start = (w-1)*chunk_size + 1;
        i_end   = min(w*chunk_size, n_groups);
        if i_start > n_groups
            worker_groups = groups([]); %#ok<NASGU>
            fprintf('Worker %d: no groups assigned\n', w);
        else
            worker_groups = groups(i_start:i_end); %#ok<NASGU>
            fprintf('Worker %d: groups %d-%d  (%d group(s))\n', ...
                w, i_start, i_end, i_end - i_start + 1);
        end
        save(fullfile(TMP_DIR, sprintf('chunk_%d.mat', w)), 'worker_groups');
    end

    % ---- Save shared worker config ----
    [min_lt, max_lt]               = smp_season_get(season, TRACK);
    worker_cfg.test_mode           = false;
    worker_cfg.channels_to_extract = channels;
    worker_cfg.driver_map          = driver_map;
    worker_cfg.alias               = alias;
    worker_cfg.season              = season;
    worker_cfg.top_level_dir       = TOP_LEVEL_DIR;
    worker_cfg.min_lt              = min_lt;
    worker_cfg.max_lt              = max_lt;
    save(fullfile(TMP_DIR, 'worker_cfg.mat'), 'worker_cfg');
    fprintf('\n');

    % ---- Launch workers ----
    fprintf('Launching %d worker(s)...\n', N_WORKERS);
    matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');

    for w = 1:N_WORKERS
        sys_cmd = sprintf('start "SMP Worker %d" cmd /k ""%s" -batch "smp_compile_worker(%d, ''%s'')"', ...
            w, matlab_exe, w, strrep(TMP_DIR, '\', '\\'));
        system(sys_cmd);
        fprintf('  Worker %d launched\n', w);
        pause(1.5);
    end

    % ---- Poll ----
    fprintf('\nWaiting for workers...\n\n');
    t_start    = tic;
    last_count = -1;

    while true
        done_flags = dir(fullfile(TMP_DIR, 'done_*.flag'));
        n_done     = numel(done_flags);

        if n_done ~= last_count
            fprintf('[%s]  %d / %d worker(s) done\n', ...
                datestr(now,'HH:MM:SS'), n_done, N_WORKERS);
            last_count = n_done;
        end

        if n_done >= N_WORKERS
            fprintf('\nAll workers finished.\n\n');
            break;
        end

        if toc(t_start) > TIMEOUT_S
            error('Timeout after %ds - check worker windows for errors.', TIMEOUT_S);
        end

        pause(POLL_INTERVAL_S);
    end

    % ---- Merge partial caches ----
    fprintf('Merging results...\n');
    for w = 1:N_WORKERS
        partial_file = fullfile(TMP_DIR, sprintf('partial_%d.mat', w));
        if ~exist(partial_file, 'file')
            fprintf('  [WARN] Worker %d produced no output - skipping.\n', w);
            continue;
        end

        loaded = load(partial_file, 'partial_cache');
        pc     = loaded.partial_cache;

        if isempty(cache.manifest)
            cache.manifest = pc.manifest;
        else
            cache.manifest = [cache.manifest; pc.manifest];
        end

        keys_st = fieldnames(pc.stats);
        for k = 1:numel(keys_st)
            cache.stats.(keys_st{k}) = pc.stats.(keys_st{k});
        end

        keys_tr = fieldnames(pc.traces);
        for k = 1:numel(keys_tr)
            cache.traces.(keys_tr{k}) = pc.traces.(keys_tr{k});
        end

        fprintf('  Worker %d - %d manifest row(s), %d stats, %d traces merged\n', ...
            w, height(pc.manifest), numel(keys_st), numel(keys_tr));
    end
    % After all workers merged, deduplicate manifest by Path
    [~, unique_idx] = unique(cache.manifest.Path, 'stable');
    cache.manifest  = cache.manifest(unique_idx, :);
    fprintf('Manifest deduplicated: %d unique rows.\n', numel(unique_idx));
    % ---- Save ----
    fprintf('\nSaving cache...\n');
    if saveFile
        smp_cache_save(TOP_LEVEL_DIR, cache);
    end 
    fprintf('Cache saved.\n\n');
end

%% =========================================================
%  SECTION 6: FILTER TO SESSION OF INTEREST
% =========================================================

SMP_filtered = smp_filter_cache(cache, alias, 'Session', SESSION_FILTER);

smp_filter_summary(SMP_filtered);

%% =========================================================
%  SECTION 7: LOAD PLOT CONFIG AND GENERATE PLOTS
% =========================================================

plots = smp_plot_config_load(PLOT_CONFIG_FILE);

%%
holdFigs = smp_plot_from_config(SMP_filtered, plots, cfg, driver_map, plot_opts);


figs = holdFigs;

for i = 1:numel(figs)
    if ~isempty(figs{i})
        set(figs{i}, 'Visible', 'on');
    end
end

%% =========================================================
%  SECTION 8: GENERATE PITSTOP REPORT (optional)
% =========================================================
if CREATE_PITSTOP_REPORT
    stops   = smp_pitstop_detect(SMP_filtered);
    pitData = smp_stops_to_pitdata(stops, SMP_filtered, driver_map);
    figs    = plotPitStops(pitData, 'Cfg', cfg, 'DriverMap', driver_map);
end

%% =========================================================
%  SECTION 9: EXPORT TO POWERPOINT
% =========================================================
figs = holdFigs;
if iscell(SESSION_FILTER)
    session_str = strjoin(SESSION_FILTER, '_');
else
    session_str = SESSION_FILTER;
end
team_str    = strjoin(TEAM_FILTER, '_');
report_name = sprintf('%s_%s_%s_%d', TRACK, team_str, session_str, year(datetime('now')));
output_path = fullfile(OUTPUT_DIR, [report_name, '.pptx']);

fprintf('\n--- Opening PowerPoint template ---\n');
[pptApp, prs] = smp_open_pptx(PPTX_TEMPLATE, output_path);

title_slide = prs.Slides.Item(1);
if iscell(SESSION_FILTER)
    session_str = strjoin(SESSION_FILTER, sprintf('\r\t'));
else
    session_str = SESSION_FILTER;
end
title_str        = sprintf('Supercars Systems Report %d', year(datetime('now')));
team_str_display = strjoin(TEAM_FILTER, sprintf('\r\t'));
subtitle_str     = sprintf('Sessions:\r\t%s\r\rTeams:\r\t%s', session_str, team_str_display);

for s = 1:title_slide.Shapes.Count
    shp = title_slide.Shapes.Item(s);
    try
        if strcmp(shp.Name, 'Title 1')
            shp.TextFrame.TextRange.Text = title_str;
        elseif strcmp(shp.Name, 'Text Placeholder 2')
            shp.TextFrame.TextRange.Text = subtitle_str;
            shp.TextFrame.TextRange.Font.Size = 12;
        end
    catch ME
        fprintf('  Could not set text on "%s": %s\n', shp.Name, ME.message);
    end
end

slide_width  = 720*1.1;
slide_height = 405*1.1;
margin       = 10;

fprintf('--- Adding %d figure slides ---\n', numel(figs));
inserted = {};
for i = 1:numel(figs)
    fig = figs{i};
    if isempty(fig) || ~isvalid(fig)
        fprintf('  [%d/%d] Skipping empty/invalid figure\n', i, numel(figs));
        continue;
    end
    if any(cellfun(@(h) isequal(h, fig), inserted))
        fprintf('  [%d/%d] Skipping duplicate figure handle\n', i, numel(figs));
        continue;
    end
    inserted{end+1} = fig;

    slide = invoke(prs.Slides, 'Add', prs.Slides.Count + 1, 12);

    fig_pos = get(fig, 'Position');
    fig_w   = fig_pos(3);
    fig_h   = fig_pos(4);
    if fig_w <= 0 || fig_h <= 0
        fig_w = 1200; fig_h = 650;
    end
    aspect    = fig_w / fig_h;
    max_w     = slide_width  - 2*margin;
    max_h     = slide_height - 2*margin;
    img_w     = max_w;
    img_h     = img_w / aspect;
    if img_h > max_h
        img_h = max_h;
        img_w = img_h * aspect;
    end
    final_left = (slide_width  - 610) / 2;
    final_top  = (slide_height - 400) / 2;

    tmp = [tempname, '.png'];
    exportgraphics(fig, tmp, 'Resolution', 150, 'BackgroundColor', 'white');
    slide.Shapes.AddPicture(tmp, 0, 1, final_left, final_top, img_w, img_h);
    try; delete(tmp); catch; end

    fprintf('  [%d/%d] Slide added\n', i, numel(figs));
end

smp_save_close_pptx(pptApp, prs);
fprintf('Report saved: %s\n', output_path);