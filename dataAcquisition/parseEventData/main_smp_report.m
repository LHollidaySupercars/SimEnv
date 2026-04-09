%% =========================================================
%  MAIN SMP REPORT — Entry Point
%  =========================================================
%  Run this script to compile .ld data and generate plots.
%
%  WORKFLOW:
%    Step 1 — Edit CONFIG section below
%    Step 2 — Run Section 5 OR Section 5b (not both):
%               Section 5   — compile new/changed files + save cache
%               Section 5b  — load existing cache only (fast, re-plot only)
%    Step 3 — Plots appear; PPTX saved to output folder
%
%  CACHE SAVE MODES (compile_opts.save_mode):
%    'legacy'  — one smp_cache.mat  (original behaviour, default)
%    'session' — one file per session: smp_cache_RA1.mat etc.
%                Faster saves, and Section 5b only loads what you need.
% =========================================================

clear; clc; close all;

%% =========================================================
%  SECTION 1: PATHS
% =========================================================

TOP_LEVEL_DIR    = 'E:\2026\02_AGP\_TeamData';
% TOP_LEVEL_DIR  = 'E:\02_AGP\_Team Data';

CHANNELS_FILE    = 'C:\SimEnv\dataAcquisition\Motec_MP\channels.xlsx';
EVENT_ALIAS_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx';
DRIVER_ALIAS_FILE= 'C:\SimEnv\dataAcquisition\Motec_MP\driverAlias.xlsx';
% PLOT_CONFIG_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_Align.xlsx';
% PLOT_CONFIG_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_Devo.xlsx';
% PLOT_CONFIG_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_pez_request.xlsx';
PLOT_CONFIG_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_BV_recreate.xlsx';
SEASON_FILE      = 'C:\SimEnv\trackDB\seasonOverview.xlsx';

PPTX_TEMPLATE    = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\templates\SuperCars_PPT.pptx';
OUTPUT_DIR       = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\output';
OUTPUT_FILENAME  = 'AGP_Report';
CREATE_PITSTOP_REPORT = 0;

%% =========================================================
%  SECTION 2: EVENT CONFIG
% =========================================================

TRACK          = 'AGP';
TEAM_FILTER    = {};        % {} = all teams, e.g. {'T8R', 'WAU'}
SESSION_FILTER = {'QU6'};   % sessions to plot, e.g. {'RA1'} or {'FP1','FP2'}

%% =========================================================
%  SECTION 3: PROCESSING OPTIONS
% =========================================================

compile_opts.mode          = 'stream';    % 'stream' (safe) or 'bulk' (high RAM)
compile_opts.track         = TRACK;
compile_opts.max_traces    = 4;           % top-N laps stored per car (0 = none)
compile_opts.dist_n_points = 1000;
compile_opts.dist_channel  = 'Odometer';
compile_opts.verbose       = true;
compile_opts.date_from     = datetime(2026, 2, 20);
compile_opts.saveCache     = true;
compile_opts.save_mode     = 'session';   % 'legacy' or 'session'
compile_opts.session_filter = SESSION_FILTER;

plot_opts.fig_width     = 1200;
plot_opts.fig_height    = 650;
plot_opts.font_size     = 11;
plot_opts.n_laps_avg    = 3;
plot_opts.verbose       = true;
plot_opts.venue         = TRACK;

%% =========================================================
%  SECTION 4: LOAD CONFIG FILES
% =========================================================
fprintf('=== SMP Report — %s ===\n\n', TRACK);

season     = smp_season_load(SEASON_FILE);
% channels   = smp_channel_config_load(CHANNELS_FILE);
[channels, channel_rules] = smp_channel_config_load(CHANNELS_FILE);
alias      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map = smp_driver_alias_load(DRIVER_ALIAS_FILE);
cfg        = smp_colours();
compile_opts.channel_rules  = channel_rules;
%% =========================================================
%  SECTION 5: COMPILE
%  Run this when you have new/changed .ld files to process.
%  Already-cached files are skipped automatically.
%  The returned cache covers ALL sessions compiled so far.
%  SESSION_FILTER is applied in Section 6.
% =========================================================

% cache = smp_compile_event(TOP_LEVEL_DIR, TEAM_FILTER, channels, ...
%                           season, driver_map, alias, compile_opts);
compile_opts.channel_rules = channel_rules;
cache = smp_compile_event(TOP_LEVEL_DIR, TEAM_FILTER, channels, ...
                          season, driver_map, alias, compile_opts);
%% =========================================================
%  SECTION 5b: LOAD ONLY (skip compile — re-plot existing cache)
%  Use this instead of Section 5 when no new files need compiling.
%  In 'session' save_mode this ONLY loads the sessions in SESSION_FILTER
%  off disk — fast, low RAM.
%  In 'legacy' save_mode this loads the full smp_cache.mat as before.
% =========================================================

cache = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

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
%%

for i = 1:numel(figs)
    if ~isempty(figs{i})
        set(figs{i}, 'Visible', 'off');
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
%  SECTION 9: EXPORT TO POWERPOINT (optional)
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

% --- Slide 1: Title ---
title_slide = prs.Slides.Item(1);
if iscell(SESSION_FILTER)
    session_str_display = strjoin(SESSION_FILTER, sprintf('\r\t'));
else
    session_str_display = SESSION_FILTER;
end
title_str        = sprintf('Supercars Systems Report %d', year(datetime('now')));
team_str_display = strjoin(TEAM_FILTER, sprintf('\r\t'));
subtitle_str     = sprintf('Sessions:\r\t%s\r\rTeams:\r\t%s', session_str_display, team_str_display);

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

% --- TOC layout constants ---
toc_col_left    = [20,  50,  150, 235, 305];
toc_col_width   = [25,  100,  60,  80,  70];
toc_col_heads   = {'#', 'Title', 'Math Op', 'Plot Type', 'Colours'};
toc_top_start   = 48;
toc_row_h       = 16;
toc_hdr_h       = 14;
toc_max_rows    = 19;
toc_col2_offset = 455;
toc_data_start  = toc_top_start + toc_hdr_h + 2;

% --- Slide 2: first TOC slide ---
toc_slide      = create_toc_slide(prs, 2, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h);
toc_entry      = 0;   % total TOC entries written
toc_slide_num  = 1;   % how many TOC slides exist so far

% --- Slide dimensions ---
slide_width  = 720 * 1.1;
slide_height = 405 * 1.1;
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

    % Record slide number before adding
    fig_slide_num = prs.Slides.Count + 1;
    slide = invoke(prs.Slides, 'Add', fig_slide_num, 12);

    fig_pos = get(fig, 'Position');
    fig_w   = fig_pos(3);
    fig_h   = fig_pos(4);
    if fig_w <= 0 || fig_h <= 0
        fig_w = 1200; fig_h = 650;
    end
    aspect    = fig_w / fig_h;
    max_w     = slide_width  - 2*margin;
    max_h     = slide_height - 2*margin;
%     img_w     = max_w;
%     img_h     = img_w / aspect;
    img_w     = fig_w;
    img_h     = fig_h + 100;

    if img_h > max_h
        img_h = max_h;
        img_w = img_h * aspect;
    end
    final_left = (slide_width  - 610) / 2;
    final_top  = (slide_height - 360) / 2;

    tmp = [tempname, '.png'];
    exportgraphics(fig, tmp, 'Resolution', 150, 'BackgroundColor', 'white');
    slide.Shapes.AddPicture(tmp, 0, 1, final_left, final_top, img_w, img_h);
    try; delete(tmp); catch; end

    % --- TOC entry ---
    pptx_label = '';
    if i <= numel(plots) && isfield(plots(i), 'pptx_title') && ~isempty(plots(i).pptx_title)
        pptx_label = plots(i).pptx_title;
    end

    if ~isempty(pptx_label)
        toc_entry = toc_entry + 1;

        % Entries per slide = 2 columns x max_rows
        entries_per_slide = toc_max_rows * 2;
        entry_on_slide    = mod(toc_entry - 1, entries_per_slide) + 1;

        % New TOC slide needed
        if toc_entry > 1 && mod(toc_entry - 1, entries_per_slide) == 0
            toc_slide_num = toc_slide_num + 1;
            toc_slide = create_toc_slide(prs, 1 + toc_slide_num, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h);
            % Also write col 2 headers on the new slide
            write_toc_headers(toc_slide, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h, toc_col2_offset);
        end

        % Write col 2 headers on current slide when first col 2 entry arrives
        if toc_entry > 1 && mod(toc_entry - 1, entries_per_slide) == toc_max_rows
            write_toc_headers(toc_slide, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h, toc_col2_offset);
        end

        % Which column group and row
        col_group    = ceil(entry_on_slide / toc_max_rows);
        row_in_group = mod(entry_on_slide - 1, toc_max_rows) + 1;
        col_offset   = (col_group - 1) * toc_col2_offset;
        entry_top    = toc_data_start + (row_in_group - 1) * toc_row_h;

        % Collect all plot rows sharing this fig_num
        this_fig_num = plots(i).fig_num;
        if isnan(this_fig_num)
            shared_idx = i;
        else
            shared_idx = find(arrayfun(@(p) isequal(p.fig_num, this_fig_num), plots));
        end

        % Unique math ops and plot types
        all_math  = unique(arrayfun(@(p) p.math_fn, plots(shared_idx), 'UniformOutput', false));
        all_types = unique(arrayfun(@(p) p.type,    plots(shared_idx), 'UniformOutput', false));
        all_math  = all_math(~cellfun(@isempty, all_math));
        all_types = all_types(~cellfun(@isempty, all_types));

        math_str   = strjoin(all_math,  ' / ');
        type_str   = strjoin(all_types, ' / ');
        colour_str = plots(i).colour_mode;

        toc_row_data = {sprintf('%d', toc_entry), pptx_label, math_str, type_str, colour_str};

        for c = 1:5
            tx = toc_slide.Shapes.AddTextbox(1, toc_col_left(c) + col_offset, entry_top, toc_col_width(c), toc_row_h);
            tr = tx.TextFrame.TextRange;
            tr.Text           = toc_row_data{c};
            tr.Font.Size      = 9;
            tr.Font.Color.RGB = 0;

            if c == 2
                try
                    tr.ActionSettings.Item(1).Action = 2;
                    tr.ActionSettings.Item(1).Hyperlink.Address    = '';
                    tr.ActionSettings.Item(1).Hyperlink.SubAddress = sprintf('%d', fig_slide_num);
                catch ME_link
                    fprintf('  [TOC] Hyperlink failed for "%s": %s\n', pptx_label, ME_link.message);
                end
            end
        end
    end

    fprintf('  [%d/%d] Slide %d added — "%s"\n', i, numel(figs), fig_slide_num, pptx_label);
end

smp_save_close_pptx(pptApp, prs);
fprintf('Report saved: %s\n', output_path);

% --- Helper: write column headers on a TOC slide at a given left offset ---
    function write_toc_headers(slide, col_left, col_width, col_heads, top, hdr_h, left_offset)
        for c = 1:5
            tx = slide.Shapes.AddTextbox(1, col_left(c) + left_offset, top, col_width(c), hdr_h);
            tr = tx.TextFrame.TextRange;
            tr.Text           = col_heads{c};
            tr.Font.Size      = 9;
            tr.Font.Bold      = 1;
            tr.Font.Color.RGB = 0;
        end
    end

% --- Helper: create a new TOC slide at insert_pos ---
    function sl = create_toc_slide(prs, insert_pos, col_left, col_width, col_heads, top_start, hdr_h)
        sl = invoke(prs.Slides, 'Add', insert_pos, 12);
        hdr = sl.Shapes.AddTextbox(1, 20, 12, 680, 28);
        hdr.TextFrame.TextRange.Text           = 'Contents';
        hdr.TextFrame.TextRange.Font.Size      = 18;
        hdr.TextFrame.TextRange.Font.Bold      = 1;
        hdr.TextFrame.TextRange.Font.Color.RGB = 0;
        % Column 1 headers
        for c = 1:5
            tx = sl.Shapes.AddTextbox(1, col_left(c), top_start, col_width(c), hdr_h);
            tr = tx.TextFrame.TextRange;
            tr.Text           = col_heads{c};
            tr.Font.Size      = 9;
            tr.Font.Bold      = 1;
            tr.Font.Color.RGB = 0;
        end
    end

% %% =========================================================
% %  MAIN SMP REPORT — Entry Point
% %  =========================================================
% %  Run this script to compile .ld data and generate plots.
% %
% %  WORKFLOW:
% %    Step 1 — Edit CONFIG section below
% %    Step 2 — Run entire script (or section by section)
% %    Step 3 — Plots appear; PPTX saved to output folder
% %
% %  MODES:
% %    'stream'  (default) — RAM-safe, processes one file at a time
% %    'bulk'    (legacy)  — loads everything into memory, requires
% %                          password confirmation at runtime
% % =========================================================
% 
% clear; clc; close all;
% 
% %% =========================================================
% %  SECTION 1: PATHS — *** REPLACE THESE ***
% % =========================================================
% 
% % Root folder containing team subfolders (NN_ACRONYM structure)
% TOP_LEVEL_DIR   = 'E:\2026\01_SMP\_TeamData';         % *** REPLACE ***
% % TOP_LEVEL_DIR   = 'E:\02_AGP\_Team Data';
% % TOP_LEVEL_DIR   = 'C:\LOCAL_DATA\01 - SMP\L180'; % L180 Data, higher logging rate
% % use this for pitot tube analysis
% 
% 
% % Config Excel files
% CHANNELS_FILE   = 'C:\SimEnv\dataAcquisition\Motec_MP\channels.xlsx';         % *** REPLACE ***
% EVENT_ALIAS_FILE= 'C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx';       % *** REPLACE ***
% DRIVER_ALIAS_FILE='C:\SimEnv\dataAcquisition\Motec_MP\driverAlias.xlsx';      % *** REPLACE ***
% PLOT_CONFIG_FILE= 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_Devo.xlsx';  % *** REPLACE ***
% PLOT_CONFIG_FILE= 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_Align.xlsx';  % *** REPLACE ***
% % PLOT_CONFIG_FILE= 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_BV_recreate.xlsx'; 
% SEASON_FILE     = 'C:\SimEnv\trackDB\seasonOverview.xlsx';                    % *** REPLACE ***
% 
% % PowerPoint template and output
% PPTX_TEMPLATE   = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\templates\SuperCars_PPT.pptx';   % *** REPLACE ***
% OUTPUT_DIR      = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\output';                           % *** REPLACE ***
% OUTPUT_FILENAME = 'AGP_Report';                                  % *** REPLACE ***
% CREATE_PITSTOP_REPORT = 0;
% %% =========================================================
% %  SECTION 2: EVENT CONFIG — *** REPLACE THESE ***
% % =========================================================
% 
% % Three-letter track acronym — must match seasonOverview.xlsx
% TRACK           = 'SMP';         % *** REPLACE — e.g. 'BAT', 'ADE', 'SAN' ***
% 
% % Teams to process — cell array of acronyms, {} for all teams
% TEAM_FILTER     = {};            % *** REPLACE — e.g. {'T8R', 'WAU'} ***
% % TEAM_FILTER     = {}; 
% 
% % Filter for the report — what session(s) to analyse
% SESSION_FILTER  = {'RA1'};
% %% =========================================================
% %  SECTION 3: PROCESSING OPTIONS
% % =========================================================
% 
% compile_opts.mode          = 'stream';   % 'stream' (safe) or 'bulk' (high RAM)
% compile_opts.track         = TRACK;
% compile_opts.max_traces    = 5;          % top-N laps stored per car for trace plots
% compile_opts.dist_n_points = 1000;       % interpolation grid points per trace
% compile_opts.dist_channel  = 'Odometer';
% compile_opts.verbose       = true;
% compile_opts.date_from     = datetime(2026, 2, 20);
% compile_opts.saveCache     = false;
% compile_opts.save_mode = 'session';   % splits on save
% 
% plot_opts.fig_width     = 1200;
% plot_opts.fig_height    = 650;
% plot_opts.font_size     = 11;
% plot_opts.n_laps_avg    = 3;
% plot_opts.verbose       = true;
% plot_opts.venue         = TRACK;
% 
% %% =========================================================
% %  SECTION 4: LOAD CONFIG FILES
% % =========================================================
% fprintf('=== SMP Report — %s ===\n\n', TRACK);
% 
% season      = smp_season_load(SEASON_FILE);
% channels    = smp_channel_config_load(CHANNELS_FILE);
% alias       = smp_alias_load(EVENT_ALIAS_FILE);
% driver_map  = smp_driver_alias_load(DRIVER_ALIAS_FILE);
% cfg         = smp_colours();
% 
% %% =========================================================
% %  SECTION 5: COMPILE (incremental — only new/changed files)
% % =========================================================
% % This step is safe to re-run at any time. Already-cached files
% % are skipped automatically. Only new or changed .ld files are processed.
% 
% cache = smp_compile_event(TOP_LEVEL_DIR, TEAM_FILTER, channels, ...
%                           season, driver_map, alias, compile_opts);
% 
% %% =========================================================
% %  SECTION 6: FILTER TO SESSION OF INTEREST
% % =========================================================
% 
% SMP_filtered = smp_filter_cache(cache, alias, 'Session', SESSION_FILTER);
% 
% smp_filter_summary(SMP_filtered);
% 
% %% =========================================================
% %  SECTION 7: LOAD PLOT CONFIG AND GENERATE PLOTS
% % =========================================================
% 
% plots = smp_plot_config_load(PLOT_CONFIG_FILE);
% 
% %%
% 
% holdFigs = smp_plot_from_config(SMP_filtered, plots, cfg, driver_map, plot_opts);
% 
% figs = holdFigs;
% 
% 
% % Make figures visible
% for i = 1:numel(figs)
%     if ~isempty(figs{i})
%         set(figs{i}, 'Visible', 'on');
%     end
% end
% %% =========================================================
% %  SECTION 8: GENERATE PITSTOP REPORT (optional)
% % =========================================================
% if CREATE_PITSTOP_REPORT
% %     stops   = smp_pitstop_detect(SMP_filtered);
%     pitData = smp_stops_to_pitdata(stops, SMP_filtered, driver_map);
%     figs    = plotPitStops(pitData, 'Cfg', cfg, 'DriverMap', driver_map);
% end
% 
% 
% %% =========================================================
% %  SECTION 9: EXPORT TO POWERPOINT (optional)
% % =========================================================
% % --- Build output filename ---
% figs = holdFigs;
% if iscell(SESSION_FILTER)
%     session_str = strjoin(SESSION_FILTER, '_');
% else
%     session_str = SESSION_FILTER;
% end
% team_str    = strjoin(TEAM_FILTER, '_');
% report_name = sprintf('%s_%s_%s_%d', TRACK, team_str, session_str, year(datetime('now')));
% output_path = fullfile(OUTPUT_DIR, [report_name, '.pptx']);
% % --- Open template ---
% fprintf('\n--- Opening PowerPoint template ---\n');
% [pptApp, prs] = smp_open_pptx(PPTX_TEMPLATE, output_path);
% % --- Edit title slide ---
% title_slide = prs.Slides.Item(1);
% if iscell(SESSION_FILTER)
%     session_str = strjoin(SESSION_FILTER, sprintf('\r\t'));
% else
%     session_str = SESSION_FILTER;
% end
% title_str        = sprintf('Supercars Systems Report %d', year(datetime('now')));
% team_str_display = strjoin(TEAM_FILTER, sprintf('\r\t'));
% subtitle_str     = sprintf('Sessions:\r\t%s\r\rTeams:\r\t%s', session_str, team_str_display);
% for s = 1:title_slide.Shapes.Count
%     shp = title_slide.Shapes.Item(s);
%     try
%         if strcmp(shp.Name, 'Title 1')
%             shp.TextFrame.TextRange.Text = title_str;
%         elseif strcmp(shp.Name, 'Text Placeholder 2')
%             shp.TextFrame.TextRange.Text = subtitle_str;
%             shp.TextFrame.TextRange.Font.Size = 12;
%         end
%     catch ME
%         fprintf('  Could not set text on "%s": %s\n', shp.Name, ME.message);
%     end
% end
% % --- Slide dimensions (points, 16:9 = 720 x 405) ---
% slide_width  = 720*1.1;
% slide_height = 405*1.1;
% margin       = 10;
% 
% % --- Add one slide per figure ---
% fprintf('--- Adding %d figure slides ---\n', numel(figs));
% inserted = {};
% for i = 1:numel(figs)
%     fig = figs{i};
%     if isempty(fig) || ~isvalid(fig)
%         fprintf('  [%d/%d] Skipping empty/invalid figure\n', i, numel(figs));
%         continue;
%     end
%     if any(cellfun(@(h) isequal(h, fig), inserted))
%         fprintf('  [%d/%d] Skipping duplicate figure handle\n', i, numel(figs));
%         continue;
%     end
%     inserted{end+1} = fig;
% 
%     slide = invoke(prs.Slides, 'Add', prs.Slides.Count + 1, 12);
% 
%     % --- Aspect-ratio-correct size, centred on slide ---
%     fig_pos = get(fig, 'Position');
%     fig_w   = fig_pos(3);
%     fig_h   = fig_pos(4);
%     if fig_w <= 0 || fig_h <= 0
%         fig_w = 1200; fig_h = 650;
%     end
%     aspect  = fig_w / fig_h;
%     max_w   = slide_width  - 2*margin;
%     max_h   = slide_height - 2*margin;
%     img_w   = max_w;
%     img_h   = img_w / aspect;
%     if img_h > max_h
%         img_h = max_h;
%         img_w = img_h * aspect;
%     end
%     final_left = (slide_width - 610)/2 ;
%     final_top  = (slide_height- 400)/2;
% 
%     % --- Export and insert ---
%     tmp = [tempname, '.png'];
%     exportgraphics(fig, tmp, 'Resolution', 150, 'BackgroundColor', 'white');
%     slide.Shapes.AddPicture(tmp, 0, 1, final_left, final_top, img_w, img_h);
%     try; delete(tmp); catch; end
% 
%     fprintf('  [%d/%d] Slide added\n', i, numel(figs));
% end
% 
% % --- Save and close ---
% smp_save_close_pptx(pptApp, prs);
% fprintf('Report saved: %s\n', output_path);