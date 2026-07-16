function exclude_mask = smp_show_concat_report(report, label, file_names, sessions, merged, date_flags)
% SMP_SHOW_CONCAT_REPORT  Blocking pop-up summarising concat_sessions decisions.
%
% Called automatically by load_and_concat when compile_opts.showConcatReport=true.
% Can also be called directly from validate_concat_sessions or any other script.
%
% INPUTS
%   report      - struct array (2nd output of concat_sessions)
%   label       - title string, e.g. group key
%   file_names  - cell array of file paths (optional)
%   sessions    - cell array of raw session structs (optional) — enables full
%                 speed-vs-time trace for every stint
%   merged      - merged session struct (1st output of concat_sessions, optional)
%                 enables a post-concat result trace panel
%   date_flags  - optional struct array (one entry per file) with fields:
%                   .is_suspect  logical
%                   .file_date   'yyyy-mm-dd' string
%                   .event_date  'yyyy-mm-dd' string
%                 Suspect files are shown as DATE? in the table (yellow row).
%                 After the window closes a questdlg fires per suspect file.
%
% OUTPUT
%   exclude_mask - logical vector (length = numel(report)) — true where the
%                  user confirmed exclusion via the date questdlg.

    if nargin < 2 || isempty(label),      label      = ''; end
    if nargin < 3 || isempty(file_names), file_names = {}; end
    if nargin < 4,                        sessions   = {}; end
    if nargin < 5,                        merged     = []; end
    if nargin < 6,                        date_flags = []; end

    exclude_mask = false(numel(report), 1);

    n = numel(report);
    if n < 2, return; end

    n_d = sum(strcmp({report.status}, 'dropped'));
    n_k = n - n_d;

    SPEED_CANDS  = {'Ground_Speed','Speedkmh','Speed','Lateral_Acc','Longitudinal_Acc'};
    KEPT_CLRS    = [0.28 0.75 1.00; 0.20 0.90 0.65; 0.90 0.75 0.20; 0.60 0.40 1.00; 0.20 0.85 0.85];
    DROP_CLRS    = [1.00 0.35 0.35; 1.00 0.60 0.20; 0.95 0.20 0.70; 0.85 0.50 0.30];
    MAX_PTS      = 3000;

    has_traces = ~isempty(sessions) && numel(sessions) == n;
    has_merged = ~isempty(merged) && isstruct(merged);

    HDR_H    = 80;
    HINT_H   = 20;   % hint text below summary
    TBL_H    = n * 24 + 32;
    TRC_H    = 260;
    MERGED_H = 220;
    ALIGN_H  = 220;
    PAD      = 12;

    % Count dropped stints that have a valid match with session data available
    n_aligned = 0;
    if has_traces
        for si = 1:n
            if strcmp(report(si).status,'dropped') && report(si).matched_idx > 0 ...
                    && report(si).matched_idx <= numel(sessions)
                n_aligned = n_aligned + 1;
            end
        end
    end

    fig_h = HDR_H + HINT_H + PAD + TBL_H + PAD;
    if has_traces, fig_h = fig_h + TRC_H + PAD; end
    if has_merged, fig_h = fig_h + MERGED_H + PAD; end
    if n_aligned > 0, fig_h = fig_h + n_aligned * (ALIGN_H + PAD); end
    fig_h = max(fig_h, 380);

    scr_sz  = get(0, 'ScreenSize');            % [left bottom width height]
    win_h   = min(fig_h, floor(scr_sz(4) * 0.88));
    need_scroll = fig_h > win_h;
    fig_w   = 1060 + 20 * need_scroll;        % extra 20 px for slider column

    fig = figure('Name', ['Concat Report: ' label], ...
                 'NumberTitle', 'off', ...
                 'Position', [60 max(10, floor((scr_sz(4)-win_h)/2)) fig_w win_h], ...
                 'Color', [0.10 0.10 0.10], ...
                 'CloseRequestFcn', @(src,~)   uiresume(src), ...
                 'KeyPressFcn',     @(src,evt) on_keypress(src, evt));

    % Inner panel that holds all content at full height; scrolled via slider.
    inner_pan = uipanel('Parent', fig, ...
        'Units', 'pixels', ...
        'Position', [0, -(fig_h - win_h), 1060, fig_h], ...
        'BackgroundColor', [0.10 0.10 0.10], ...
        'BorderType', 'none');

    if need_scroll
        scroll_range = fig_h - win_h;
        sld = uicontrol('Parent', fig, 'Style', 'slider', ...
            'Units', 'pixels', 'Position', [1061 0 19 win_h], ...
            'Min', 0, 'Max', scroll_range, 'Value', scroll_range, ...
            'SliderStep', [min(1, 24/scroll_range), min(1, 100/scroll_range)], ...
            'Callback', @(src,~) set(inner_pan, 'Position', ...
                [0, -get(src,'Value'), 1060, fig_h]));
        set(fig, 'WindowScrollWheelFcn', ...
            @(~,evt) wheel_scroll(sld, inner_pan, fig_h, evt));
    end

    y = fig_h;  % running top-down cursor (relative to inner panel)

    % ---- Title ----
    y = y - 44;
    uicontrol('Parent', inner_pan, 'Style', 'text', ...
        'String', ['Concat Report  —  ' strrep(label, '_', ' ')], ...
        'Units', 'pixels', 'Position', [5 y 1050 38], ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'ForegroundColor', 'w', 'BackgroundColor', [0.10 0.10 0.10], ...
        'HorizontalAlignment', 'center');

    % ---- Summary ----
    y = y - 30;
    if n_d == 0, sum_clr = [0.40 0.90 0.40]; else, sum_clr = [1.00 0.52 0.22]; end
    uicontrol('Parent', inner_pan, 'Style', 'text', ...
        'String', sprintf('%d stints in   |   %d kept   |   %d dropped', n, n_k, n_d), ...
        'Units', 'pixels', 'Position', [5 y 1050 24], ...
        'FontSize', 11, 'ForegroundColor', sum_clr, ...
        'BackgroundColor', [0.10 0.10 0.10], ...
        'HorizontalAlignment', 'center');

    y = y - 20;
    uicontrol('Parent', inner_pan, 'Style', 'text', ...
        'String', 'Tick "Exclude?" to remove a stint from the concat  —  pre-ticked = algorithm dropped or date flagged', ...
        'Units', 'pixels', 'Position', [5 y 1050 16], ...
        'FontSize', 8, 'ForegroundColor', [0.55 0.55 0.55], ...
        'BackgroundColor', [0.10 0.10 0.10], ...
        'HorizontalAlignment', 'center');

    y = y - PAD;

    % ---- Session table ----
    y = y - TBL_H;
    tbl_data = cell(n, 6);
    tbl_row_colors = repmat([0.16 0.16 0.16; 0.20 0.20 0.20], ceil(n/2), 1);
    tbl_row_colors = tbl_row_colors(1:n, :);
    for si = 1:n
        fname = '';
        if ~isempty(file_names) && si <= numel(file_names)
            [~, fn, ext] = fileparts(file_names{si});
            fname = [fn ext];
        end
        m_str = '';
        if report(si).matched_idx > 0
            m_str = sprintf('Stint %d', report(si).matched_idx);
        end
        tbl_data{si,1} = si;
        tbl_data{si,2} = fname;
        % Show DATE? if this file is date-suspect; normal concat status otherwise
        is_date_sus = ~isempty(date_flags) && si <= numel(date_flags) && date_flags(si).is_suspect;
        is_dropped  = strcmp(report(si).status, 'dropped');
        if is_date_sus
            tbl_data{si,3} = sprintf('DATE? (%s)', date_flags(si).file_date);
            tbl_row_colors(si,:) = [0.30 0.27 0.05];  % dark yellow highlight
        else
            tbl_data{si,3} = upper(report(si).status);
        end
        tbl_data{si,4} = m_str;
        if is_date_sus
            tbl_data{si,5} = sprintf('File date %s — event %s  |  %s', ...
                date_flags(si).file_date, date_flags(si).event_date, report(si).reason);
        else
            tbl_data{si,5} = report(si).reason;
        end
        % Exclude? checkbox: pre-tick if algorithm dropped it OR date-flagged
        tbl_data{si,6} = is_dropped || is_date_sus;
    end
    tbl_h = uitable('Parent', inner_pan, ...
        'Data', tbl_data, ...
        'ColumnName', {'#', 'File', 'Status', 'Matched', 'Reason', 'Exclude?'}, ...
        'ColumnWidth', {28, 310, 90, 70, 340, 60}, ...
        'ColumnEditable', [false false false false false true], ...
        'ColumnFormat',   {'numeric','char','char','char','char','logical'}, ...
        'Units', 'pixels', 'Position', [5 y 1050 TBL_H], ...
        'FontSize', 10, ...
        'BackgroundColor', tbl_row_colors, ...
        'ForegroundColor', [0.95 0.95 0.95]);

    y = y - PAD;

    % ---- Full session speed traces ----
    if has_traces
        y = y - TRC_H;
        ax_t = axes('Parent', inner_pan, 'Units', 'pixels', ...
                    'Position', [60 y+6 980 TRC_H-16], ...
                    'Color', [0.08 0.08 0.08], ...
                    'XColor', [0.60 0.60 0.60], 'YColor', [0.60 0.60 0.60]);
        hold(ax_t,'on'); grid(ax_t,'on');
        ax_t.GridColor = [0.25 0.25 0.25];

        spd_ch = '';
        k_ci = 0; d_ci = 0;
        for si = 1:n
            ch = find_channel(sessions{si}, SPEED_CANDS);
            if isempty(ch), continue; end
            if isempty(spd_ch), spd_ch = ch; end

            t_raw = sessions{si}.(ch).time(:);
            v_raw = sessions{si}.(ch).data(:);
            if numel(t_raw) > MAX_PTS
                idx   = round(linspace(1, numel(t_raw), MAX_PTS));
                t_raw = t_raw(idx);  v_raw = v_raw(idx);
            end

            is_drop = strcmp(report(si).status, 'dropped');
            if is_drop
                d_ci = mod(d_ci, size(DROP_CLRS,1)) + 1;
                clr = DROP_CLRS(d_ci,:); lw = 1.2; ls = '--';
            else
                k_ci = mod(k_ci, size(KEPT_CLRS,1)) + 1;
                clr = KEPT_CLRS(k_ci,:); lw = 1.8; ls = '-';
            end
            plot(ax_t, t_raw/60, v_raw, ls, 'Color', clr, 'LineWidth', lw, ...
                 'DisplayName', sprintf('S%d [%s]  %s', si, upper(report(si).status), tbl_data{si,2}));
        end

        title(ax_t, 'Full speed trace — all stints (blue=kept  red=dropped)', ...
              'Color','w','FontSize',10);
        xlabel(ax_t, 'Time (min)', 'Color',[0.65 0.65 0.65],'FontSize',9);
        y_lbl = spd_ch;
        if ~isempty(spd_ch)
            u = get_units(sessions, spd_ch);
            if ~isempty(u), y_lbl = [spd_ch ' (' u ')']; end
        end
        ylabel(ax_t, y_lbl, 'Color',[0.65 0.65 0.65],'FontSize',9);
        lg = legend(ax_t,'show','Location','northeast');
        set(lg,'TextColor','w','Color',[0.14 0.14 0.14],'FontSize',8);

        y = y - PAD;
    end

    % ---- Merged result trace ----
    if has_merged
        y = y - MERGED_H;
        ch_m = find_channel(merged, SPEED_CANDS);
        ax_m = axes('Parent', inner_pan, 'Units', 'pixels', ...
                    'Position', [60 y+6 980 MERGED_H-16], ...
                    'Color', [0.08 0.08 0.08], ...
                    'XColor', [0.60 0.60 0.60], 'YColor', [0.60 0.60 0.60]);
        hold(ax_m,'on'); grid(ax_m,'on');
        ax_m.GridColor = [0.25 0.25 0.25];
        if ~isempty(ch_m)
            t_m_full = merged.(ch_m).time(:);
            v_m_full = merged.(ch_m).data(:);
            u_m = '';
            if isfield(merged.(ch_m), 'units'), u_m = merged.(ch_m).units; end
            y_lbl_m = ch_m;
            if ~isempty(u_m), y_lbl_m = [ch_m ' (' u_m ')']; end

            % Build per-file colored segments using cumulative lengths from kept sessions.
            kept_idx = find(strcmp({report.status}, 'kept'));
            seg_start = 1;
            for ki = 1:numel(kept_idx)
                si_k = kept_idx(ki);
                ch_k = find_channel(sessions{si_k}, SPEED_CANDS);
                if ~isempty(ch_k)
                    seg_len = numel(sessions{si_k}.(ch_k).data);
                else
                    % Fallback: split merged evenly if channel not found
                    seg_len = floor(numel(v_m_full) / numel(kept_idx));
                end
                seg_end = min(seg_start + seg_len - 1, numel(v_m_full));

                t_seg = t_m_full(seg_start:seg_end);
                v_seg = v_m_full(seg_start:seg_end);
                if numel(t_seg) > MAX_PTS
                    idx_ds = round(linspace(1, numel(t_seg), MAX_PTS));
                    t_seg  = t_seg(idx_ds);
                    v_seg  = v_seg(idx_ds);
                end

                k_ci = mod(ki - 1, size(KEPT_CLRS,1)) + 1;
                clr  = KEPT_CLRS(k_ci,:);

                lbl = '';
                if ~isempty(file_names) && si_k <= numel(file_names)
                    [~, fn_base, fn_ext] = fileparts(file_names{si_k});
                    lbl = [fn_base fn_ext];
                else
                    lbl = sprintf('File %d', si_k);
                end
                plot(ax_m, t_seg/60, v_seg, '-', 'Color', clr, 'LineWidth', 1.6, ...
                     'DisplayName', lbl);
                seg_start = seg_end + 1;
                if seg_start > numel(v_m_full), break; end
            end

            if numel(kept_idx) > 1
                lg_m = legend(ax_m, 'show', 'Location', 'northeast');
                set(lg_m, 'TextColor', 'w', 'Color', [0.14 0.14 0.14], 'FontSize', 8);
            end

            ylabel(ax_m, y_lbl_m, 'Color',[0.65 0.65 0.65],'FontSize',9);
        end
        title(ax_m, 'Merged result — post-concat time axis (colour = individual file)', ...
              'Color','w','FontSize',10);
        xlabel(ax_m, 'Time (min)', 'Color',[0.65 0.65 0.65],'FontSize',9);
        y = y - PAD;
    end

    % ---- Per-pair aligned comparison (one subplot per dropped/kept pair) ----
    % Both speed traces are resampled to a common 10 Hz grid, cross-correlated
    % to find the best time offset, then plotted aligned on a relative time axis.
    GRID_HZ = 10;
    for si = 1:n
        r = report(si).matched_idx;
        if ~strcmp(report(si).status,'dropped') || r <= 0 || r > numel(sessions)
            continue;
        end

        ch_s = find_channel(sessions{si}, SPEED_CANDS);
        ch_r = find_channel(sessions{r},  SPEED_CANDS);
        if isempty(ch_s) || isempty(ch_r), continue; end

        t_s   = sessions{si}.(ch_s).time(:);
        spd_s = sessions{si}.(ch_s).data(:);
        t_r   = sessions{r}.(ch_r).time(:);
        spd_r = sessions{r}.(ch_r).data(:);

        % Resample both to uniform GRID_HZ grid for cross-correlation
        dt    = 1 / GRID_HZ;
        tg_s  = (t_s(1) : dt : t_s(end))';
        tg_r  = (t_r(1) : dt : t_r(end))';
        sg_s  = interp1(t_s, spd_s, tg_s, 'linear', 'extrap');
        sg_r  = interp1(t_r, spd_r, tg_r, 'linear', 'extrap');

        % Cross-correlate to find lag (S relative to R)
        % Use whichever is shorter as the template; let xcorr return lags.
        if numel(sg_s) <= numel(sg_r)
            [xc, lags] = xcorr(sg_r - mean(sg_r), sg_s - mean(sg_s));
        else
            [xc, lags] = xcorr(sg_s - mean(sg_s), sg_r - mean(sg_r));
            xc   = flipud(xc);
            lags = flipud(-lags);
        end
        [~, peak_idx] = max(xc);
        lag_samples   = lags(peak_idx);
        lag_secs      = lag_samples * dt;   % positive = S starts lag_secs into R

        % Build plotting axes: R starts at 0, S shifted by lag
        x_r   = tg_r / 60;
        x_s   = (tg_s + lag_secs) / 60;

        % Downsample for rendering
        if numel(x_r) > MAX_PTS
            idx2 = round(linspace(1, numel(x_r), MAX_PTS));
            x_r = x_r(idx2);  sg_r = sg_r(idx2);
        end
        if numel(x_s) > MAX_PTS
            idx2 = round(linspace(1, numel(x_s), MAX_PTS));
            x_s = x_s(idx2);  sg_s = sg_s(idx2);
        end

        y = y - ALIGN_H;
        ax_a = axes('Parent', inner_pan, 'Units', 'pixels', ...
                    'Position', [60 y+6 980 ALIGN_H-16], ...
                    'Color', [0.08 0.08 0.08], ...
                    'XColor', [0.60 0.60 0.60], 'YColor', [0.60 0.60 0.60]);
        hold(ax_a,'on'); grid(ax_a,'on');
        ax_a.GridColor = [0.25 0.25 0.25];

        % Kept (solid) first, dropped (dashed) on top
        plot(ax_a, x_r, sg_r, '-',  'Color', [0.28 0.75 1.00], 'LineWidth', 1.8, ...
             'DisplayName', sprintf('S%d [KEPT]  %s', r, tbl_data{r,2}));
        plot(ax_a, x_s, sg_s, '--', 'Color', [1.00 0.35 0.35], 'LineWidth', 1.2, ...
             'DisplayName', sprintf('S%d [DROPPED]  %s', si, tbl_data{si,2}));

        u_a = get_units(sessions, ch_r);
        y_lbl_a = ch_r;
        if ~isempty(u_a), y_lbl_a = [ch_r ' (' u_a ')']; end

        title(ax_a, sprintf('S%d vs S%d  |  cross-corr aligned (lag=%.1f s)  —  kept (solid) vs dropped (dashed)', ...
              si, r, lag_secs), 'Color','w','FontSize',10);
        xlabel(ax_a, 'Time (min)', 'Color',[0.65 0.65 0.65],'FontSize',9);
        ylabel(ax_a, y_lbl_a, 'Color',[0.65 0.65 0.65],'FontSize',9);
        lg_a = legend(ax_a,'show','Location','northeast');
        set(lg_a,'TextColor','w','Color',[0.14 0.14 0.14],'FontSize',8);

        y = y - PAD;
    end

    drawnow;

    % ---- Print lap times for dropped sessions ----
    if ~isempty(sessions) && numel(sessions) == n
        for si = 1:n
            if ~strcmp(report(si).status,'dropped'), continue; end
            r = report(si).matched_idx;
            fname_s = '';
            fname_r = '';
            if ~isempty(file_names)
                if si <= numel(file_names), [~,fn,ext] = fileparts(file_names{si}); fname_s = [fn ext]; end
                if r > 0 && r <= numel(file_names), [~,fn,ext] = fileparts(file_names{r}); fname_r = [fn ext]; end
            end
            laps_s = get_lap_times(sessions{si});
            tag_s  = '';
            if isfield(report(si), 'tag') && ~isempty(report(si).tag)
                tag_s = sprintf('  [%s]', report(si).tag);
            end
            fprintf('\n  [DROPPED] S%d  %s%s\n', si, fname_s, tag_s);
            if isempty(laps_s)
                fprintf('    Lap times: (none extracted)\n');
            else
                fprintf('    Lap times (%d laps):', numel(laps_s));
                for kk = 1:numel(laps_s)
                    fprintf('  Lap %d: %.1fs', kk, laps_s(kk));
                end
                fprintf('\n');
            end
            if r > 0 && r <= numel(sessions)
                laps_r = get_lap_times(sessions{r});
                fprintf('  [KEPT]    S%d  %s\n', r, fname_r);
                if isempty(laps_r)
                    fprintf('    Lap times: (none extracted)\n');
                else
                    % Highlight which laps in R matched laps in S
                    match_pos = extract_match_pos(report(si).tag);
                    ns = numel(laps_s);
                    fprintf('    Lap times (%d laps):', numel(laps_r));
                    for kk = 1:numel(laps_r)
                        if match_pos > 0 && kk >= match_pos && kk < match_pos + ns
                            fprintf('  Lap %d: %.1fs*', kk, laps_r(kk));
                        else
                            fprintf('  Lap %d: %.1fs', kk, laps_r(kk));
                        end
                    end
                    fprintf('  (* = matched laps)\n');
                end
            end
        end
    end

    uiwait(fig);

    % ---- Read checkbox state before destroying the figure ----
    if ishandle(tbl_h)
        final_data   = get(tbl_h, 'Data');
        exclude_mask = logical(cell2mat(final_data(:, 6)));
    end
    if ishandle(fig), delete(fig); end
end

% -------------------------------------------------------------------------
function on_keypress(fig, evt)
    if strcmp(evt.Key, 'return')
        uiresume(fig);
    end
end

% -------------------------------------------------------------------------
function wheel_scroll(sld, inner_pan, fig_h, evt)
% Shift inner panel by 40 px per scroll tick via the slider.
    step    = 40 * evt.VerticalScrollCount;
    new_val = max(sld.Min, min(sld.Max, sld.Value + step));
    set(sld,       'Value',    new_val);
    set(inner_pan, 'Position', [0, -new_val, 1060, fig_h]);
end

% -------------------------------------------------------------------------
function lap_times = get_lap_times(sess)
% Extract completed lap durations (s).
% Method 1: Lap_Time / Running_Lap_Time reset
% Method 2: Engine_Run_Time delta at Lap_Number transitions
% Method 3: Lap_Number time-axis (fallback)
    lap_times = [];

    % --- Method 1: Lap_Time / Running_Lap_Time (1 value per lap) ---
    lt_cands = {'Lap_Time','Running_Lap_Time','LapTime','RunningLapTime'};
    fn = rpt_find_field_any(sess, lt_cands);
    if ~isempty(fn)
        d = sess.(fn).data(:);
        d = d(d > 5);   % discard implausibly short values
        if ~isempty(d)
            lap_times = d;
            return;
        end
    end

    % --- Method 2: Engine_Run_Time delta ---
    fn_ert = rpt_find_field_any(sess, {'Engine_Run_Time','EngineRunTime','Engine_Running_Time'});
    fn_lap = rpt_find_field_any(sess, {'Lap_Number','LapNumber'});
    if ~isempty(fn_ert) && ~isempty(fn_lap)
        ert  = sess.(fn_ert).data(:);
        lapn = round(sess.(fn_lap).data(:));
        if numel(ert) > 10 && numel(ert) == numel(lapn)
            transitions = find(diff(lapn) > 0);
            if numel(transitions) >= 2
                lap_times = diff(ert(transitions));
                lap_times = lap_times(lap_times > 5);
                if ~isempty(lap_times), return; end
            end
        end
    end

    % --- Method 3: Lap_Number time-axis ---
    if isempty(fn_lap)
        fn_lap = rpt_find_field_any(sess, {'Lap_Number','LapNumber'});
    end
    if isempty(fn_lap), return; end
    lap_data = round(sess.(fn_lap).data(:));
    lap_time = sess.(fn_lap).time(:);
    if numel(lap_data) < 10, return; end
    transitions = find(diff(lap_data) > 0);
    if numel(transitions) < 2, return; end
    lap_times = diff(lap_time(transitions));
    lap_times = lap_times(lap_times > 5);
end

% -------------------------------------------------------------------------
function fn = rpt_find_field_any(sess, candidates)
    fn  = '';
    fns = fieldnames(sess);
    for ci = 1:numel(candidates)
        for fi = 1:numel(fns)
            if strcmpi(fns{fi}, candidates{ci})
                if isfield(sess.(fns{fi}), 'data') && numel(sess.(fns{fi}).data) > 10
                    fn = fns{fi}; return;
                end
            end
        end
    end
end

% -------------------------------------------------------------------------
function pos = extract_match_pos(tag)
% Parse 'lap-time subset (N laps matched at position P in ref)' -> P, else 0.
    pos = 0;
    if isempty(tag), return; end
    tok = regexp(tag, 'position\s+(\d+)', 'tokens');
    if ~isempty(tok)
        pos = str2double(tok{1}{1});
    end
end

% -------------------------------------------------------------------------
function ch = find_channel(sess, candidates)
    ch = '';
    fns = fieldnames(sess);
    for ci = 1:numel(candidates)
        for fi = 1:numel(fns)
            if strcmpi(fns{fi}, candidates{ci})
                if isfield(sess.(fns{fi}), 'data') && numel(sess.(fns{fi}).data) > 10
                    ch = fns{fi};  return;
                end
            end
        end
    end
end

% -------------------------------------------------------------------------
function u = get_units(sessions, ch)
    u = '';
    for si = 1:numel(sessions)
        if isfield(sessions{si}, ch) && isfield(sessions{si}.(ch), 'units')
            u = sessions{si}.(ch).units;
            if ~isempty(u), return; end
        end
    end
end

