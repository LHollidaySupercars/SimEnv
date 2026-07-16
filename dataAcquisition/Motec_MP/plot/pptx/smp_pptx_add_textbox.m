function slide = smp_pptx_add_textbox(slide, text_str, left_pt, top_pt, width_pt, height_pt, varargin)
% SMP_PPTX_ADD_TEXTBOX  Add a textbox shape to a slide (in-memory; call
%                        smp_pptx_flush_slide or smp_save_close_pptx to
%                        commit to disk).
%
% Usage:
%   slide = smp_pptx_add_textbox(slide, 'Hello', left, top, width, height)
%   slide = smp_pptx_add_textbox(slide, 'Hello', left, top, width, height, ...
%                                 'FontSize', 12, 'Bold', true, 'ColorRGB', [255 0 0])
%
% Coordinates (left/top/width/height) are in POINTS, matching the
% existing script's point-based layout (1 inch = 72 pt).
%
% Name-value options:
%   'FontSize'         (default 12)
%   'Bold'             (default false)
%   'ColorRGB'         (default [0 0 0] black) — 1x3 RGB, 0-255
%   'Name'             (default 'TextBox')     — shape name, cosmetic only
%   'HyperlinkTarget'  (default '') — a 'slideN.xml' filename (i.e. the
%                       .file field of a slide handle returned by
%                       smp_pptx_add_slide) to make this textbox a
%                       clickable jump-to-slide link. Registers a
%                       slide-relationship rId in this slide's own
%                       .rels file (via smp_pptx_flush_slide) and adds
%                       <a:hlinkClick> to the run.

    p = inputParser;
    addParameter(p, 'FontSize', 12);
    addParameter(p, 'Bold', false);
    addParameter(p, 'ColorRGB', [0, 0, 0]);
    addParameter(p, 'Name', 'TextBox');
    addParameter(p, 'HyperlinkTarget', '');
    parse(p, varargin{:});
    opt = p.Results;

    EMU_PER_PT = 12700;
    left_emu   = round(left_pt   * EMU_PER_PT);
    top_emu    = round(top_pt    * EMU_PER_PT);
    width_emu  = round(width_pt  * EMU_PER_PT);
    height_emu = round(height_pt * EMU_PER_PT);

    shape_id = slide.next_shape_id;
    slide.next_shape_id = slide.next_shape_id + 1;

    font_sz_xml = round(opt.FontSize * 100);   % a:rPr sz is in hundredths of a point
    bold_xml    = ternary(opt.Bold, '1', '0');
    rgb_hex     = sprintf('%02X%02X%02X', opt.ColorRGB(1), opt.ColorRGB(2), opt.ColorRGB(3));

    text_esc = escape_xml(text_str);

    % --- Optional jump-to-slide hyperlink ---
    hlink_xml = '';
    if ~isempty(opt.HyperlinkTarget)
        if ~isfield(slide, 'hyperlink_rels')
            slide.hyperlink_rels = {};   % defensive, for slide handles predating this field
        end
        hlink_rid = sprintf('rId%d', slide.rid_counter);
        slide.rid_counter = slide.rid_counter + 1;
        % Target slide lives in the SAME ppt/slides/ folder as this one,
        % so the relative path is just the filename — no "../" needed.
        % (That's different from the media relationship above: images
        % live in the sibling ppt/media/ folder, so "../media/x" is
        % correct there but would be wrong here — it would resolve one
        % level too high, outside ppt/slides/ entirely.)
        slide.hyperlink_rels{end+1} = struct('rid', hlink_rid, ...
            'target', opt.HyperlinkTarget);
        hlink_xml = sprintf('<a:hlinkClick r:id="%s" action="ppaction://hlinksldjump"/>', hlink_rid);
    end

    shape_xml = sprintf([...
        '<p:sp><p:nvSpPr><p:cNvPr id="%d" name="%s %d"/>' ...
        '<p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>' ...
        '<p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>' ...
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>' ...
        '<p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="t">' ...
        '<a:noAutofit/></a:bodyPr><a:lstStyle/>' ...
        '<a:p><a:r><a:rPr lang="en-AU" sz="%d" b="%s" dirty="0">' ...
        '<a:solidFill><a:srgbClr val="%s"/></a:solidFill>%s</a:rPr>' ...
        '<a:t>%s</a:t></a:r></a:p></p:txBody></p:sp>'], ...
        shape_id, opt.Name, shape_id, left_emu, top_emu, width_emu, height_emu, ...
        font_sz_xml, bold_xml, rgb_hex, hlink_xml, text_esc);

    slide.shapes{end+1} = shape_xml;
end


% ======================================================================= %
function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end


% ======================================================================= %
function s = escape_xml(s)
    s = strrep(s, '&',  '&amp;');
    s = strrep(s, '<',  '&lt;');
    s = strrep(s, '>',  '&gt;');
    s = strrep(s, '"',  '&quot;');
    s = strrep(s, '''', '&apos;');
end
