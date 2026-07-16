function smp_pptx_set_placeholder_text(pkg, slide_index, shape_name, text_str, varargin)
% SMP_PPTX_SET_PLACEHOLDER_TEXT  Set the text of a named placeholder shape
%                                 (e.g. 'Title 1', 'Text Placeholder 2') on
%                                 an existing slide from the template.
%
% Usage:
%   smp_pptx_set_placeholder_text(pkg, 1, 'Title 1', 'My Title')
%   smp_pptx_set_placeholder_text(pkg, 1, 'Text Placeholder 2', subtitle_str, 'FontSize', 12)
%
% slide_index is the 1-based position in DISPLAY order (matches
% pkg.slide_order), not necessarily the slideN.xml number.
%
% This targets the shape's existing <p:txBody> wholesale, replacing it
% with a single paragraph/run carrying the given text. CRLF ("\r") in
% text_str is treated as a paragraph break, matching the original
% script's use of sprintf('...\r\t...') for multi-line subtitles.
%
% Name-value options:
%   'FontSize' — if provided, overrides the run font size (points)

    p = inputParser;
    addParameter(p, 'FontSize', []);
    parse(p, varargin{:});
    opt = p.Results;

    if slide_index < 1 || slide_index > numel(pkg.slide_order)
        error('smp_pptx_set_placeholder_text: slide_index %d out of range (1..%d)', ...
              slide_index, numel(pkg.slide_order));
    end

    slide_file = pkg.slide_order{slide_index};
    slide_path = fullfile(pkg.work_dir, 'ppt', 'slides', slide_file);
    xml = fileread(slide_path);

    % --- Find the <p:sp>...</p:sp> block whose cNvPr name matches ---
    name_esc = regexptranslate('escape', shape_name);
    sp_blocks = regexp(xml, '<p:sp>.*?</p:sp>', 'match');

    target_idx = [];
    for i = 1:numel(sp_blocks)
        if ~isempty(regexp(sp_blocks{i}, sprintf('name="%s"', name_esc), 'once'))
            target_idx = i;
            break;
        end
    end

    if isempty(target_idx)
        fprintf('  [smp_pptx_set_placeholder_text] Shape "%s" not found on slide %d — skipped.\n', ...
                shape_name, slide_index);
        return;
    end

    old_block = sp_blocks{target_idx};

    % --- Preserve the template's original <a:bodyPr> (autofit settings,
    %     insets, etc.) rather than dropping it. This keeps PowerPoint's
    %     "shrink text on overflow" behaviour intact, which matters when
    %     the rendering font differs from the design font (e.g. a custom
    %     brand font not installed on every machine) and would otherwise
    %     render larger than expected and overlap nearby shapes. ---
    body_pr_match = regexp(old_block, '<a:bodyPr\s*/>|<a:bodyPr(?:\s[^>]*)?>.*?</a:bodyPr>', 'match', 'once');
    if isempty(body_pr_match)
        body_pr_xml = '<a:bodyPr/>';
    else
        body_pr_xml = body_pr_match;
    end

    % --- Build replacement txBody: one <a:p> per CRLF-delimited line ---
    lines = strsplit(text_str, sprintf('\r'));
    para_xml = '';
    for i = 1:numel(lines)
        if isempty(opt.FontSize)
            rpr = '<a:rPr lang="en-AU" dirty="0"/>';
        else
            rpr = sprintf('<a:rPr lang="en-AU" sz="%d" dirty="0"/>', round(opt.FontSize*100));
        end
        if isempty(lines{i})
            para_xml = [para_xml, '<a:p><a:endParaRPr lang="en-AU" dirty="0"/></a:p>']; %#ok<AGROW>
        else
            para_xml = [para_xml, sprintf('<a:p><a:r>%s<a:t>%s</a:t></a:r></a:p>', ...
                        rpr, escape_xml(lines{i}))]; %#ok<AGROW>
        end
    end
    new_txbody = sprintf('<p:txBody>%s<a:lstStyle/>%s</p:txBody>', body_pr_xml, para_xml);

    % --- Replace the old <p:txBody>...</p:txBody> within this shape block only ---
    new_block = regexprep(old_block, '<p:txBody>.*?</p:txBody>', regexprep(new_txbody, '\$', '$$$$'), 'once');

    xml = strrep(xml, old_block, new_block);
    write_text_file(slide_path, xml);
end


% ======================================================================= %
function s = escape_xml(s)
    s = strrep(s, '&',  '&amp;');
    s = strrep(s, '<',  '&lt;');
    s = strrep(s, '>',  '&gt;');
    s = strrep(s, '"',  '&quot;');
    s = strrep(s, '''', '&apos;');
end


% ======================================================================= %
function write_text_file(path, content)
    fid = fopen(path, 'w');
    if fid == -1
        error('Could not open file for writing: %s', path);
    end
    fwrite(fid, content, 'char');
    fclose(fid);
end
