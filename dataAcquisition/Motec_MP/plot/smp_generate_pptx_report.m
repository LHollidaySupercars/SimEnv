function smp_generate_pptx_report(figs, plots, pptx_template, output_dir, ...
                                   base_report_name, plot_config_file, ...
                                   session_filter, team_filter, track)
% SMP_GENERATE_PPTX_REPORT  Export a set of figures to a PowerPoint report.
%
% Usage:
%   smp_generate_pptx_report(figs, plots, pptx_template, output_dir, ...
%                             base_report_name, plot_config_file, ...
%                             session_filter, team_filter, track)
%
% The output filename is:
%   <base_report_name>_<suffix>.pptx
% where suffix is derived from the plot config filename by stripping
% 'plottingRequest_' and the '.xlsx' extension.
% e.g. 'plottingRequest_BV_recreate.xlsx' → suffix = 'BV_recreate'
% If the filename does not start with 'plottingRequest_', the full
% filename (minus extension) is used as the suffix.

    % ------------------------------------------------------------------
    %  Derive output filename suffix from plot config path
    % ------------------------------------------------------------------
    [~, fname] = fileparts(plot_config_file);
    if startsWith(fname, 'plottingRequest_')
        suffix = strrep(fname, 'plottingRequest_', '');
    else
        suffix = fname;
    end

    report_name = sprintf('%s_%s', base_report_name, suffix);
    output_path = fullfile(output_dir, [report_name, '.pptx']);

    % ------------------------------------------------------------------
    %  Title slide strings
    % ------------------------------------------------------------------
    if iscell(session_filter)
        session_str_display = strjoin(session_filter, sprintf('\r\t'));
    else
        session_str_display = session_filter;
    end
    if iscell(team_filter)
        team_str_display = strjoin(team_filter, sprintf('\r\t'));
    else
        team_str_display = team_filter;
    end
    title_str    = sprintf('Supercars Systems Report %d', year(datetime('now')));
    subtitle_str = sprintf('Sessions:\r\t%s\r\rTeams:\r\t%s', session_str_display, team_str_display);

    % ------------------------------------------------------------------
    %  TOC layout constants
    % ------------------------------------------------------------------
    toc_col_left   = [20,  50,  150, 235, 305];
    toc_col_width  = [25,  100,  60,  80,  70];
    toc_col_heads  = {'#', 'Title', 'Math Op', 'Plot Type', 'Colours'};
    toc_top_start  = 48;
    toc_row_h      = 16;
    toc_hdr_h      = 14;
    toc_max_rows   = 19;
    toc_col2_offset= 455;
    toc_data_start = toc_top_start + toc_hdr_h + 2;

    slide_width  = 720 * 1.1;
    slide_height = 405 * 1.1;
    margin       = 10;

    % ------------------------------------------------------------------
    %  Open PowerPoint
    % ------------------------------------------------------------------
    try
        fprintf('\n--- Opening PowerPoint template ---\n');
        fprintf('    Config : %s\n', plot_config_file);
        fprintf('    Output : %s\n', output_path);
        [pptApp, prs] = smp_open_pptx(pptx_template, output_path);
    catch ME
        fprintf('[ERROR] Could not open PowerPoint template: %s\n', ME.message);
        return;
    end

    try
        % --- Title slide ---
        title_slide = prs.Slides.Item(1);
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

        % --- TOC slide ---
        toc_slide     = create_toc_slide(prs, 2, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h);
        toc_entry     = 0;
        toc_slide_num = 1;

        % --- Figure slides ---
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
            inserted{end+1} = fig; %#ok

            fig_slide_num = prs.Slides.Count + 1;
            slide = invoke(prs.Slides, 'Add', fig_slide_num, 12);

            fig_pos = get(fig, 'Position');
            fig_w   = fig_pos(3);
            fig_h   = fig_pos(4);
            if fig_w <= 0 || fig_h <= 0
                fig_w = 1200; fig_h = 650;
            end
            aspect     = fig_w / fig_h;
            max_h      = slide_height - 2*margin; %#ok
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
                toc_entry         = toc_entry + 1;
                entries_per_slide = toc_max_rows * 2;
                entry_on_slide    = mod(toc_entry - 1, entries_per_slide) + 1;

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

    catch ME_pptx
        fprintf('\n[ERROR] PowerPoint export failed: %s\n', ME_pptx.message);
        fprintf('  Figures remain open in MATLAB.\n');
    end
end


% ======================================================================= %
%  LOCAL HELPERS
% ======================================================================= %
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