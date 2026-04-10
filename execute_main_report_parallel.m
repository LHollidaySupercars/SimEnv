%% =========================================================
%  EXECUTE_MAIN_REPORT_PARALLEL
%  =========================================================
%  Multi-worker compile + plot + PowerPoint export + SQL upload.
%
%  WORKFLOW:
%    Step 1  — Edit CONFIG sections (1–3)
%    Step 2  — Section 5 launches N_WORKERS MATLAB instances to compile
%              .ld files in parallel, polls until all finish, then merges
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
workshop              = false;        % true = no session filter on stint grouping

%% =========================================================
%  SECTION 3: PROCESSING + UPLOAD OPTIONS
% =========================================================

N_WORKERS       = 4;
TMP_DIR         = fullfile(tempdir, 'smp_parallel');
POLL_INTERVAL_S = 3;
TIMEOUT_S       = 3600;

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
compile_opts.save_mode      = 'session';
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
fprintf('=== Parallel Report — %s ===\n\n', TRACK);

season                     = smp_season_load(SEASON_FILE);
[channels, channel_rules]  = smp_channel_config_load(CHANNELS_FILE);
alias                      = smp_alias_load(EVENT_ALIAS_FILE);
driver_map                 = smp_driver_alias_load(DRIVER_ALIAS_FILE);
cfg                        = smp_colours();
compile_opts.channel_rules = channel_rules;

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

cache = smp_cache_load(TOP_LEVEL_DIR, SESSION_FILTER);

% Migrate old cache structure if needed
if ~isfield(cache, 'stats'),  cache.stats  = struct(); end
if ~isfield(cache, 'traces'), cache.traces = struct(); end
if ~isfield(cache, 'mode'),   cache.mode   = 'stream'; end
if ~ismember('GroupKey', cache.manifest.Properties.VariableNames)
    cache.manifest.GroupKey = repmat({''}, height(cache.manifest), 1);
end

% Apply date_from filter
if isfield(compile_opts, 'date_from') && ~isempty(compile_opts.date_from)
    date_from_dn = datenum(compile_opts.date_from);
    for i = 1:numel(scan_all)
        files = scan_all(i).files;
        keep  = false(1, numel(files));
        for j = 1:numel(files)
            d    = dir(files{j});
            keep(j) = ~isempty(d) && d(1).datenum >= date_from_dn;
        end
        scan_all(i).files = files(keep);
    end
    scan_all = scan_all(arrayfun(@(t) ~isempty(t.files), scan_all));
end

[to_load, cache] = smp_cache_diff(cache, scan_all);

if isempty(to_load)
    fprintf('All files up to date — nothing to compile.\n\n');
else
    fprintf('%d file(s) to process.\n', numel(to_load));

    if workshop
        groups = smp_append_stints(to_load, driver_map, alias);
    else
        groups = smp_append_stints(to_load, driver_map, alias, SESSION_FILTER);
    end
    n_groups = numel(groups);
    fprintf('%d group(s) across %d worker(s).\n\n', n_groups, N_WORKERS);

    % ---- Split groups across workers ----
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
    worker_cfg.channel_rules       = channel_rules;
    worker_cfg.driver_map          = driver_map;
    worker_cfg.alias               = alias;
    worker_cfg.season              = season;
    worker_cfg.top_level_dir       = TOP_LEVEL_DIR;
    worker_cfg.min_lt              = min_lt;
    worker_cfg.max_lt              = max_lt;
    save(fullfile(TMP_DIR, 'worker_cfg.mat'), 'worker_cfg');
    fprintf('\n');

    % ---- Launch workers ----
    fprintf('Launching %d compile worker(s)...\n', N_WORKERS);
    matlab_exe = fullfile(matlabroot, 'bin', 'matlab.exe');
    for w = 1:N_WORKERS
        sys_cmd = sprintf('start "SMP Worker %d" cmd /k ""%s" -batch "smp_compile_worker(%d, ''%s'')"', ...
            w, matlab_exe, w, strrep(TMP_DIR, '\', '\\'));
        system(sys_cmd);
        fprintf('  Worker %d launched\n', w);
        pause(1.5);
    end

    % ---- Poll until all workers finish ----
    fprintf('\nWaiting for workers...\n\n');
    t_poll     = tic;
    last_count = -1;
    while true
        done_flags = dir(fullfile(TMP_DIR, 'done_*.flag'));
        n_done     = numel(done_flags);
        if n_done ~= last_count
            fprintf('[%s]  %d / %d worker(s) done\n', datestr(now,'HH:MM:SS'), n_done, N_WORKERS);
            last_count = n_done;
        end
        if n_done >= N_WORKERS
            fprintf('\nAll workers finished.\n\n');
            break;
        end
        if toc(t_poll) > TIMEOUT_S
            error('Timeout after %ds — check worker windows for errors.', TIMEOUT_S);
        end
        pause(POLL_INTERVAL_S);
    end

    % ---- Merge partial caches ----
    fprintf('Merging results...\n');
    for w = 1:N_WORKERS
        partial_file = fullfile(TMP_DIR, sprintf('partial_%d.mat', w));
        if ~exist(partial_file, 'file')
            fprintf('  [WARN] Worker %d produced no output — skipping.\n', w);
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
        fprintf('  Worker %d — %d manifest rows, %d stats, %d traces merged\n', ...
            w, height(pc.manifest), numel(keys_st), numel(keys_tr));
    end

    % Deduplicate manifest
    [~, unique_idx] = unique(cache.manifest.Path, 'stable');
    cache.manifest  = cache.manifest(unique_idx, :);
    fprintf('Manifest deduplicated: %d unique rows.\n', numel(unique_idx));
end

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
    fprintf('Time to PPTX complete: %.1f min (%.0fs)\n', toc(t_script)/60, toc(t_script));

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