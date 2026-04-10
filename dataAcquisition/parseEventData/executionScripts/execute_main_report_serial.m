%% =========================================================
%  EXECUTE_MAIN_REPORT_SERIAL
%  =========================================================
%  Single-worker compile + plot + PowerPoint export + SQL upload.
%
%  WORKFLOW:
%    Step 1  — Edit CONFIG sections (1–3)
%    Step 2  — Run Section 5 to compile new files (or 5b to load cache only)
%    Step 3  — Plots are generated and exported to PPTX
%    Step 4  — Data is uploaded to the configured SQL target
%
%  SQL TARGETS (TARGET):
%    'pocketbase'   — local PocketBase instance
%    'azure_local'  — local SQL Server Express  (motorsport_local db)
%    'azure_online' — Motorsport Azure SQL       (Entra ID / browser MFA)
%
%  Set RUN_UPLOAD = false to skip the upload step entirely.
% =========================================================

clear; clc; close all;
t_script = tic;

%% =========================================================
%  SECTION 1: PATHS
% =========================================================

TOP_LEVEL_DIR     = 'E:\2026\03_TAU\_TeamData';

CHANNELS_FILE     = 'C:\SimEnv\dataAcquisition\Motec_MP\channels.xlsx';
EVENT_ALIAS_FILE  = 'C:\SimEnv\dataAcquisition\Motec_MP\eventAlias.xlsx';
DRIVER_ALIAS_FILE = 'C:\SimEnv\dataAcquisition\Motec_MP\driverAlias.xlsx';
PLOT_CONFIG_FILE  = 'C:\SimEnv\dataAcquisition\Motec_MP\plottingRequest_BV_recreate.xlsx';
SEASON_FILE       = 'C:\SimEnv\trackDB\seasonOverview.xlsx';

PPTX_TEMPLATE     = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\templates\SuperCars_PPT.pptx';
OUTPUT_DIR        = 'C:\SimEnv\dataAcquisition\Motec_MP\plot\output';
OUTPUT_FILENAME   = 'TAU_Report';


%% =========================================================
%  SECTION 2: EVENT CONFIG
% =========================================================

TRACK                 = 'TAU';
EVENT_NAME            = 'TAU';
TEAM_FILTER           = {};           % {} = all teams, e.g. {'T8R', 'WAU'}
SESSION_FILTER        = {'FP1', 'FP2'};
CREATE_PITSTOP_REPORT = false;

%% =========================================================
%  SECTION 3: PROCESSING + UPLOAD OPTIONS
% =========================================================

TARGET     = 'azure_online';   % 'pocketbase' | 'azure_local' | 'azure_online'
RUN_UPLOAD = true;             % false = skip flatten + upload
BATCH_SIZE = 200;
OVERWRITE  = true;

compile_opts.mode           = 'stream';
compile_opts.track          = TRACK;
compile_opts.max_traces     = 4;
compile_opts.dist_n_points  = 1000;
compile_opts.dist_channel   = 'Odometer';
compile_opts.verbose        = true;
compile_opts.date_from      = datetime(2026, 4, 10);
compile_opts.saveCache      = true;
compile_opts.save_mode      = 'session';   % 'legacy' | 'session'
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
fprintf('=== Serial Report — %s ===\n\n', TRACK);

season                     = smp_season_load(SEASON_FILE);
[channels, channel_rules]  = smp_channel_config_load(CHANNELS_FILE);
alias                      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map                 = smp_driver_alias_load(DRIVER_ALIAS_FILE);
cfg                        = smp_colours();
compile_opts.channel_rules = channel_rules;

%% =========================================================
%  SECTION 5: COMPILE
%  Run this cell when you have new/changed .ld files.
%  Already-cached files are skipped automatically.
% =========================================================

cache = smp_compile_event(TOP_LEVEL_DIR, TEAM_FILTER, channels, ...
                          season, driver_map, alias, compile_opts);

%% =========================================================
%  SECTION 5b: LOAD ONLY  (re-plot without recompiling)
%  Comment out Section 5 and run this instead when no new
%  .ld files need processing.
% =========================================================

% cache = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

%% =========================================================
%  SECTION 6: FILTER CACHE TO SESSION(S) OF INTEREST
% =========================================================

SMP_filtered = smp_filter_cache(cache, alias, 'Session', SESSION_FILTER);
smp_filter_summary(SMP_filtered);

%% =========================================================
%  SECTION 7: LOAD PLOT CONFIG AND GENERATE PLOTS
% =========================================================

plots    = smp_plot_config_load(PLOT_CONFIG_FILE);
holdFigs = smp_plot_from_config(SMP_filtered, plots, cfg, driver_map, plot_opts);
figs     = holdFigs;

for i = 1:numel(figs)
    if ~isempty(figs{i})
        set(figs{i}, 'Visible', 'off');
    end
end

%% =========================================================
%  SECTION 8: PITSTOP REPORT (optional)
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

pptx_ok = false;
try
    fprintf('\n--- Opening PowerPoint template ---\n');
    [pptApp, prs] = smp_open_pptx(PPTX_TEMPLATE, output_path);

    % --- Title slide ---
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
    toc_col_left   = [20,  50,  150, 235, 305];
    toc_col_width  = [25,  100,  60,  80,  70];
    toc_col_heads  = {'#', 'Title', 'Math Op', 'Plot Type', 'Colours'};
    toc_top_start  = 48;
    toc_row_h      = 16;
    toc_hdr_h      = 14;
    toc_max_rows   = 19;
    toc_col2_offset= 455;
    toc_data_start = toc_top_start + toc_hdr_h + 2;

    toc_slide     = create_toc_slide(prs, 2, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h);
    toc_entry     = 0;
    toc_slide_num = 1;

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

        fig_slide_num = prs.Slides.Count + 1;
        slide = invoke(prs.Slides, 'Add', fig_slide_num, 12);

        fig_pos = get(fig, 'Position');
        fig_w   = fig_pos(3);
        fig_h   = fig_pos(4);
        if fig_w <= 0 || fig_h <= 0
            fig_w = 1200; fig_h = 650;
        end
        aspect     = fig_w / fig_h;
        max_w      = slide_width  - 2*margin;
        max_h      = slide_height - 2*margin;
        img_w      = fig_w;
        img_h      = fig_h + 100;
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
            toc_entry        = toc_entry + 1;
            entries_per_slide= toc_max_rows * 2;
            entry_on_slide   = mod(toc_entry - 1, entries_per_slide) + 1;

            if toc_entry > 1 && mod(toc_entry - 1, entries_per_slide) == 0
                toc_slide_num = toc_slide_num + 1;
                toc_slide = create_toc_slide(prs, 1 + toc_slide_num, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h);
                write_toc_headers(toc_slide, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h, toc_col2_offset);
            end
            if toc_entry > 1 && mod(toc_entry - 1, entries_per_slide) == toc_max_rows
                write_toc_headers(toc_slide, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h, toc_col2_offset);
            end

            col_group    = ceil(entry_on_slide / toc_max_rows);
            row_in_group = mod(entry_on_slide - 1, toc_max_rows) + 1;
            col_offset   = (col_group - 1) * toc_col2_offset;
            entry_top    = toc_data_start + (row_in_group - 1) * toc_row_h;

            this_fig_num = plots(i).fig_num;
            if isnan(this_fig_num)
                shared_idx = i;
            else
                shared_idx = find(arrayfun(@(p) isequal(p.fig_num, this_fig_num), plots));
            end
            all_math  = unique(arrayfun(@(p) p.math_fn,  plots(shared_idx), 'UniformOutput', false));
            all_types = unique(arrayfun(@(p) p.type,     plots(shared_idx), 'UniformOutput', false));
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
    pptx_ok = true;

catch ME_pptx
    fprintf('\n[ERROR] PowerPoint export failed: %s\n', ME_pptx.message);
    fprintf('  Figures remain open in MATLAB.\n');
end

%% =========================================================
%  SECTION 10: UPLOAD TO SQL / POCKETBASE
% =========================================================

if RUN_UPLOAD
    fprintf('\n========================================\n');
    fprintf('  DATA UPLOAD — TARGET: %s\n', upper(TARGET));
    fprintf('========================================\n\n');

    fprintf('[Upload 1/3] Loading cache for event "%s"...\n', EVENT_NAME);
    cache_up = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

    if ~isfield(cache_up, 'stats') || isempty(fieldnames(cache_up.stats))
        warning('Cache is empty — skipping upload. Run compile step first.');
    else
        fprintf('      Cache: %d manifest rows, %d group keys.\n', ...
            height(cache_up.manifest), numel(fieldnames(cache_up.stats)));

        fprintf('[Upload 2/3] Flattening stats...\n');
        T = smp_flatten_stats(cache_up, EVENT_NAME);
        if ismember('id', T.Properties.VariableNames)
            T = removevars(T, 'id');
        end

        if isempty(T) || height(T) == 0
            warning('Flatten produced no rows — skipping upload.');
        else
            fprintf('[Upload 3/3] Pushing %d rows to %s...\n', height(T), upper(TARGET));

            switch lower(TARGET)

                % ── PocketBase ────────────────────────────────────────────
                case 'pocketbase'
                    opts_pb           = struct();
                    opts_pb.batch     = BATCH_SIZE;
                    opts_pb.overwrite = OVERWRITE;
                    opts_pb.dry_run   = false;

                    result = smp_push_to_pocketbase(T, opts_pb);
                    fprintf('\n      Upload complete: %d rows uploaded, %d failed.\n', ...
                        result.n_uploaded, result.n_failed);

                % ── Azure Local / Online ──────────────────────────────────
                case {'azure_local', 'azure_online'}
                    if strcmpi(TARGET, 'azure_online')
                        fprintf('      >> Browser MFA popup may appear.\n');
                    end

                    conn = smp_sql_connect(TARGET);

                    opts_sql           = struct();
                    opts_sql.batch     = BATCH_SIZE;
                    opts_sql.overwrite = OVERWRITE;
                    opts_sql.dry_run   = false;

                    result = smp_push_to_sql(T, conn, opts_sql);
                    fprintf('\n      Upload complete: %d rows uploaded, %d failed.\n', ...
                        result.n_uploaded, result.n_failed);

                    assignin('base', 'sql_conn', conn);
                    fprintf('      Connection stored in workspace as ''sql_conn''.\n');
            end
        end
    end
else
    fprintf('\n[Upload] Skipped (RUN_UPLOAD = false)\n');
end

%% =========================================================
%  SECTION 11: SAVE CACHE
% =========================================================

fprintf('\nSaving cache...\n');
try
    smp_cache_save(TOP_LEVEL_DIR, cache, compile_opts.save_mode, alias);
    fprintf('Cache saved.\n');
catch ME_save
    fprintf('[ERROR] Cache save failed: %s\n', ME_save.message);
end

fprintf('\n=== Total time: %.1f minutes (%.0f seconds) ===\n', ...
    toc(t_script)/60, toc(t_script));

%% =========================================================
%  LOCAL HELPERS
% =========================================================

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

function sl = create_toc_slide(prs, insert_pos, col_left, col_width, col_heads, top_start, hdr_h)
    sl  = invoke(prs.Slides, 'Add', insert_pos, 12);
    hdr = sl.Shapes.AddTextbox(1, 20, 12, 680, 28);
    hdr.TextFrame.TextRange.Text           = 'Contents';
    hdr.TextFrame.TextRange.Font.Size      = 18;
    hdr.TextFrame.TextRange.Font.Bold      = 1;
    hdr.TextFrame.TextRange.Font.Color.RGB = 0;
    for c = 1:5
        tx = sl.Shapes.AddTextbox(1, col_left(c), top_start, col_width(c), hdr_h);
        tr = tx.TextFrame.TextRange;
        tr.Text           = col_heads{c};
        tr.Font.Size      = 9;
        tr.Font.Bold      = 1;
        tr.Font.Color.RGB = 0;
    end
end

% ── Inline PocketBase upload (kept local to avoid dependency) ────────────
function result = smp_push_to_pocketbase_fn(T, pb_url, batch_size, overwrite) %#ok<DEFNU>
    import matlab.net.http.*
    import matlab.net.http.io.*

    endpoint  = [pb_url '/api/collections/lap_stats/records'];
    col_names = T.Properties.VariableNames;
    n_rows    = height(T);
    result.n_uploaded = 0;
    result.n_failed   = 0;

    if overwrite
        fprintf('      Clearing existing records...\n');
        get_req  = RequestMessage('GET', []);
        get_resp = get_req.send([endpoint '?perPage=500']);
        if double(get_resp.StatusCode) == 200 && ~isempty(get_resp.Body.Data.items)
            items = get_resp.Body.Data.items;
            for k = 1:numel(items)
                del_url = sprintf('%s/%s', endpoint, items(k).id);
                del_req = RequestMessage('DELETE', []);
                del_req.send(del_url);
            end
            fprintf('      Deleted %d existing rows.\n', numel(items));
        end
    end

    fprintf('      Uploading %d rows...\n', n_rows);
    t_start = tic;
    for ri = 1:n_rows
        s = struct();
        for ci = 1:numel(col_names)
            col = col_names{ci};
            val = T.(col)(ri);
            if iscell(val),    val = val{1};   end
            if isstring(val),  val = char(val); end
            if isnumeric(val) && ~isempty(val) && ~isfinite(val), val = 0; end
            s.(col) = val;
        end
        body   = StringProvider(jsonencode(s));
        req    = RequestMessage('POST', HeaderField('Content-Type','application/json'), body);
        resp   = req.send(endpoint);
        status = double(resp.StatusCode);
        if status == 200 || status == 201
            result.n_uploaded = result.n_uploaded + 1;
        else
            result.n_failed = result.n_failed + 1;
            if result.n_failed <= 3
                fprintf('      [ERROR] Row %d: HTTP %d\n', ri, status);
            end
        end
        if mod(ri, 100) == 0
            elapsed = toc(t_start);
            rate    = ri / elapsed;
            eta     = (n_rows - ri) / rate;
            fprintf('      %d/%d  (%.0f rows/s  ETA %.0fs)\n', ri, n_rows, rate, eta);
        end
    end
end