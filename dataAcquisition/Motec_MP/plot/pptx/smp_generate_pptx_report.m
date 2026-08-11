function smp_generate_pptx_report(figs, plots, pptx_template, output_dir, ...
                                   base_report_name, plot_config_file, ...
                                   session_filter, team_filter, track, ...
                                   produce_pdf)
% SMP_GENERATE_PPTX_REPORT  Export a set of figures to a PowerPo
% int report.
%
% produce_pdf (optional, default false) — if true, also exports a PDF
% alongside the .pptx (same base name) via smp_pptx_export_pdf, using
% LibreOffice headless if available, else PowerPoint COM on Windows.
%
% TOC entries are hyperlinked to their figure slide via smp_pptx_add_textbox's
% 'HyperlinkTarget' option (see the TOC-entry loop below).
%
% MAC-COMPATIBLE VERSION — builds the .pptx via direct OOXML manipulation
% (smp_open_pptx / smp_pptx_add_slide / smp_pptx_add_textbox /
% smp_pptx_add_picture / smp_pptx_set_placeholder_text /
% smp_save_close_pptx) instead of Windows COM automation. No PowerPoint
% installation or actxserver required. PDF export is no longer done
% automatically — open the .pptx and export to PDF manually as needed.
%
% TOC entries are no longer hyperlinked to their figure slide (COM's
% ActionSettings/Hyperlink.SubAddress has no equivalent in this approach
% yet) — the TOC table itself is unchanged otherwise.
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
    if nargin < 10 || isempty(produce_pdf)
        produce_pdf = false;
    end

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
    title_str    = sprintf('Supercars %s Report %d', humanize_suffix(suffix), year(datetime('now')));
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
    %  Open template
    % ------------------------------------------------------------------
    try
        fprintf('\n--- Opening PowerPoint template ---\n');
        fprintf('    Config : %s\n', plot_config_file);
        fprintf('    Output : %s\n', output_path);
        pkg = smp_open_pptx(pptx_template, output_path);
    catch ME
        fprintf('[ERROR] Could not open PowerPoint template: %s\n', ME.message);
        return;
    end

    % Track every slide handle that needs flushing at save time
    pending_slides = {};

    try
        % --- Title slide (slide 1, from template — edited in place) ---
        smp_pptx_set_placeholder_text(pkg, 1, 'Title 1', title_str);
        smp_pptx_set_placeholder_text(pkg, 1, 'Text Placeholder 2', subtitle_str, 'FontSize', 12);

        % --- TOC slide (inserted at position 2) ---
        [pkg, toc_slide] = create_toc_slide(pkg, 2, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h);
        pending_slides{end+1} = toc_slide; %#ok<AGROW>
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

            % --- Slide subheading text (from the Excel pptxTitle column) ---
            pptx_label = '';
            if i <= numel(plots) && isfield(plots(i), 'pptx_title') && ~isempty(plots(i).pptx_title)
                pptx_label = plots(i).pptx_title;
            end

            % Figure slide is appended after all currently-known slides
            % (mirrors COM's prs.Slides.Count + 1 / Add(..., 12) blank-layout add)
            fig_slide_num = numel(pkg.slide_order) + 1;
            [pkg, slide] = smp_pptx_add_slide(pkg, 'blank', [], true);

            % --- Subheading, top-left of the slide ---
            % Styled to match the TOC's own "Contents" header (18pt bold)
            % so headings read consistently across the whole deck.
            if ~isempty(pptx_label)
                slide = smp_pptx_add_textbox(slide, pptx_label, 20, 12, slide_width - 40, 28, ...
                    'FontSize', 18, 'Bold', true, 'ColorRGB', [0 0 0]);
            end

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
            set(fig, 'Renderer', 'painters');     % <-- add: force stable renderer
            drawnow;                               % <-- add: let graphics pipeline settle
            pause(0.05);                           % <-- add

            exportgraphics(fig, tmp, 'Resolution', 150, 'BackgroundColor', 'white');
            [pkg, slide] = smp_pptx_add_picture(pkg, slide, tmp, final_left, final_top, img_w, img_h);
            try; delete(tmp); catch; end
            close(fig);
            pending_slides{end+1} = slide; %#ok<AGROW>

            % --- TOC entry ---
            if ~isempty(pptx_label)
                toc_entry         = toc_entry + 1;
                entries_per_slide = toc_max_rows * 2;
                entry_on_slide    = mod(toc_entry - 1, entries_per_slide) + 1;

                if toc_entry > 1 && mod(toc_entry - 1, entries_per_slide) == 0
                    toc_slide_num = toc_slide_num + 1;
                    [pkg, toc_slide] = create_toc_slide(pkg, 1 + toc_slide_num, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h);
                    pending_slides{end+1} = toc_slide; %#ok<AGROW>
                end
                if toc_entry > 1 && mod(toc_entry - 1, entries_per_slide) == toc_max_rows
                    toc_slide = write_toc_headers(toc_slide, toc_col_left, toc_col_width, toc_col_heads, toc_top_start, toc_hdr_h, toc_col2_offset);
                    % Refresh the handle in pending_slides (same .file, updated .shapes)
                    pending_slides{end} = toc_slide;
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
                    % Only the "Title" column (c==2) is hyperlinked — it's
                    % the label the reader will actually click to jump to
                    % this entry's figure slide. `slide` here is still the
                    % figure-slide handle created earlier in this loop
                    % iteration (numbered/positioned, but not yet flushed —
                    % smp_pptx_add_textbox only needs its .file name, which
                    % is already final at this point).
                    if c == 2
                        toc_slide = smp_pptx_add_textbox(toc_slide, toc_row_data{c}, ...
                            toc_col_left(c) + col_offset, entry_top, toc_col_width(c), toc_row_h, ...
                            'FontSize', 9, 'ColorRGB', [0 0 0], 'HyperlinkTarget', slide.file);
                    else
                        toc_slide = smp_pptx_add_textbox(toc_slide, toc_row_data{c}, ...
                            toc_col_left(c) + col_offset, entry_top, toc_col_width(c), toc_row_h, ...
                            'FontSize', 9, 'ColorRGB', [0 0 0]);
                    end
                end
                % Update the stored handle since toc_slide.shapes grew
                pending_slides{find_slide_in_pending(pending_slides, toc_slide.file)} = toc_slide;
            end
            fprintf('  [%d/%d] Slide %d added — "%s"\n', i, numel(figs), fig_slide_num, pptx_label);
        end

        smp_save_close_pptx(pkg, pending_slides, produce_pdf);
        fprintf('Report saved: %s\n', output_path);

    catch ME_pptx
        fprintf('\n[ERROR] PowerPoint export failed: %s\n', ME_pptx.message);
        fprintf('  Figures remain open in MATLAB.\n');
    end
end


% ======================================================================= %
%  LOCAL HELPERS
% ======================================================================= %
function s = humanize_suffix(suffix)
% HUMANIZE_SUFFIX  Turn a plot-config filename suffix into readable
%                   title text, e.g.:
%                     'BV_recreate'        -> 'BV Recreate'
%                     'SystemsReport'      -> 'Systems Report'
%                     'E06DAR_PR_2'        -> 'E06DAR PR 2'
%
% Splits on underscores, then further splits camelCase word boundaries
% (lower->upper transitions), and capitalizes each resulting word's
% first letter. Existing all-caps tokens (e.g. acronyms like 'BV', 'PR')
% are left alone rather than being re-cased.

    parts = strsplit(suffix, '_');
    words = {};
    for i = 1:numel(parts)
        % Split camelCase: insert a space before an uppercase letter that
        % follows a lowercase letter or digit.
        chunk = regexprep(parts{i}, '([a-z0-9])([A-Z])', '$1 $2');
        sub_words = strsplit(chunk, ' ');
        words = [words, sub_words]; %#ok<AGROW>
    end
    words = words(~cellfun(@isempty, words));

    for i = 1:numel(words)
        w = words{i};
        if ~isempty(w) && ~strcmp(w, upper(w))   % leave existing ALLCAPS acronyms as-is
            words{i} = [upper(w(1)), lower(w(2:end))];
        end
    end

    s = strjoin(words, ' ');
end


% ======================================================================= %
function slide = write_toc_headers(slide, col_left, col_width, col_heads, top, hdr_h, left_offset)
    for c = 1:5
        slide = smp_pptx_add_textbox(slide, col_heads{c}, col_left(c) + left_offset, top, ...
            col_width(c), hdr_h, 'FontSize', 9, 'Bold', true, 'ColorRGB', [0 0 0]);
    end
end

function [pkg, slide] = create_toc_slide(pkg, insert_pos, col_left, col_width, col_heads, top_start, hdr_h)
    [pkg, slide] = smp_pptx_add_slide(pkg, 'blank', insert_pos, true);
    slide = smp_pptx_add_textbox(slide, 'Contents', 20, 12, 680, 28, ...
        'FontSize', 18, 'Bold', true, 'ColorRGB', [0 0 0]);
    for c = 1:5
        slide = smp_pptx_add_textbox(slide, col_heads{c}, col_left(c), top_start, ...
            col_width(c), hdr_h, 'FontSize', 9, 'Bold', true, 'ColorRGB', [0 0 0]);
    end
end

function idx = find_slide_in_pending(pending_slides, slide_file)
    idx = [];
    for k = 1:numel(pending_slides)
        if strcmp(pending_slides{k}.file, slide_file)
            idx = k;
            return;
        end
    end
    error('find_slide_in_pending: slide %s not found in pending list', slide_file);
end
