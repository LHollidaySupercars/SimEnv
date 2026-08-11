function [pkg, slide] = smp_pptx_add_slide(pkg, layout_name, insert_pos, force_blank_bg)
% SMP_PPTX_ADD_SLIDE  Add a new slide based on a named layout from the
%                      template (e.g. 'blank'), and insert it at a given
%                      1-based position in the slide order.
%
% Usage:
%   [pkg, slide] = smp_pptx_add_slide(pkg, 'blank')                    % append
%   [pkg, slide] = smp_pptx_add_slide(pkg, 'blank', 2)                 % insert at position 2
%   [pkg, slide] = smp_pptx_add_slide(pkg, 'blank', [], true)          % append, force white bg
%
% Returns:
%   slide.file   - 'slideN.xml' filename for this new slide
%   slide.path   - full path to the slide XML on disk
%   slide.rels_path - full path to the slide's .rels file
%   slide.shapes - growing cell array of shape XML strings (call
%                  smp_pptx_add_textbox / smp_pptx_add_picture to append)
%   slide.rid_counter - next free rId *within this slide's own .rels*
%   slide.media_rels   - cell array of {rId, target} for images used
%
% layout_name is matched against slideLayouts/*.xml <p:cSld name="...">
% (case-insensitive). 'blank' resolves to whichever layout in the
% template is literally named "Blank" — but note that a layout named
% "Blank" can still inherit a background fill/image from the slide
% master, since a layout only needs to omit *placeholders*, not
% necessarily override the master's background.
%
% force_blank_bg (optional, default false) — if true, writes an explicit
% <p:bg> with a solid white fill into the new slide's own XML. A
% slide-level <p:bg> always wins over whatever the layout/master would
% otherwise paint, so this guarantees a genuinely blank white background
% regardless of what the chosen layout inherits — useful when no layout
% in the template is "clean" enough on its own. (Deliberately solid
% white rather than <a:noFill/> — noFill just removes the override and
% leaves the renderer to fall back to whatever's underneath, which isn't
% guaranteed to be white; an explicit solidFill is unambiguous.)

    if nargin < 3 || isempty(insert_pos)
        insert_pos = numel(pkg.slide_order) + 1;
    end
    if nargin < 4 || isempty(force_blank_bg)
        force_blank_bg = false;
    end

    layout_file = find_layout_by_name(pkg, layout_name);

    % --- New slide filename/number ---
    slide_num   = pkg.next_slide_num;
    pkg.next_slide_num = pkg.next_slide_num + 1;
    slide_file  = sprintf('slide%d.xml', slide_num);
    slide_path  = fullfile(pkg.work_dir, 'ppt', 'slides', slide_file);
    rels_path   = fullfile(pkg.work_dir, 'ppt', 'slides', '_rels', sprintf('%s.rels', slide_file));

    % --- Optional explicit background override (must be the first child
    %     of <p:cSld>, ahead of <p:spTree>, per the schema) ---
    if force_blank_bg
        bg_xml = '<p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>';
    else
        bg_xml = '';
    end

    % --- Minimal empty slide XML (shapes appended later via smp_pptx_add_*) ---
    slide_xml = [...
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' ...
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ' ...
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ' ...
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">' ...
        '<p:cSld>' , bg_xml, '<p:spTree>' ...
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>' ...
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>' ...
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>' ...
        '{{SHAPES}}' ...
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>'];

    fid = fopen(slide_path, 'w');
    fwrite(fid, slide_xml, 'char');
    fclose(fid);

    % --- Slide .rels: points at the chosen layout ---
    rels_dir = fileparts(rels_path);
    if ~exist(rels_dir, 'dir'), mkdir(rels_dir); end
    rels_xml = sprintf([...
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' ...
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' ...
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" ' ...
        'Target="../slideLayouts/%s"/></Relationships>'], layout_file);
    fid = fopen(rels_path, 'w');
    fwrite(fid, rels_xml, 'char');
    fclose(fid);

    % --- Register in presentation.xml.rels ---
    pres_rels_path = fullfile(pkg.work_dir, 'ppt', '_rels', 'presentation.xml.rels');
    pres_rels_xml  = fileread(pres_rels_path);
    new_rid = sprintf('rId%d', pkg.next_rid_pres);
    pkg.next_rid_pres = pkg.next_rid_pres + 1;
    new_rel = sprintf(['<Relationship Id="%s" ' ...
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" ' ...
        'Target="slides/%s"/>'], new_rid, slide_file);
    pres_rels_xml = strrep(pres_rels_xml, '</Relationships>', [new_rel, '</Relationships>']);
    write_text_file(pres_rels_path, pres_rels_xml);

    % --- Register in presentation.xml sldIdLst at the right position ---
    pres_path = fullfile(pkg.work_dir, 'ppt', 'presentation.xml');
    pres_xml  = fileread(pres_path);
    new_sld_id = pkg.next_sld_id;
    pkg.next_sld_id = pkg.next_sld_id + 1;
    new_entry = sprintf('<p:sldId id="%d" r:id="%s"/>', new_sld_id, new_rid);

    pres_xml = insert_sldid_at_position(pres_xml, new_entry, insert_pos);
    write_text_file(pres_path, pres_xml);

    % --- Register in [Content_Types].xml ---
    ct_path = fullfile(pkg.work_dir, '[Content_Types].xml');
    ct_xml  = fileread(ct_path);
    new_override = sprintf(['<Override PartName="/ppt/slides/%s" ' ...
        'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'], slide_file);
    ct_xml = strrep(ct_xml, '</Types>', [new_override, '</Types>']);
    write_text_file(ct_path, ct_xml);

    % --- Update pkg.slide_order to reflect new position ---
    pkg.slide_order = [pkg.slide_order(1:insert_pos-1), {slide_file}, pkg.slide_order(insert_pos:end)];

    % --- Return slide handle for shape-building calls ---
    slide.file       = slide_file;
    slide.path       = slide_path;
    slide.rels_path  = rels_path;
    slide.shapes     = {};
    slide.next_shape_id = 2;   % id=1 is the group shape itself
    slide.rid_counter   = 2;   % rId1 is the layout relationship
    slide.media_rels    = {};
    slide.hyperlink_rels = {};
end


% ======================================================================= %
function layout_file = find_layout_by_name(pkg, layout_name)
% Resolve a friendly layout name (e.g. 'blank') to its slideLayoutN.xml
% filename by reading <p:cSld name="..."> across all layouts.
    layouts_dir = fullfile(pkg.work_dir, 'ppt', 'slideLayouts');
    files = dir(fullfile(layouts_dir, 'slideLayout*.xml'));

    layout_name_lc = lower(layout_name);
    layout_file = '';
    for i = 1:numel(files)
        xml = fileread(fullfile(layouts_dir, files(i).name));
        tok = regexp(xml, '<p:cSld name="([^"]*)"', 'tokens', 'once');
        if ~isempty(tok) && strcmpi(strtrim(tok{1}), layout_name_lc)
            layout_file = files(i).name;
            break;
        end
    end

    if isempty(layout_file)
        error('smp_pptx_add_slide: No layout named "%s" found in template.', layout_name);
    end
end


% ======================================================================= %
function pres_xml = insert_sldid_at_position(pres_xml, new_entry, insert_pos)
% Insert new_entry into the <p:sldIdLst>...</p:sldIdLst> block at the
% given 1-based slide position (existing entries shift right).
    list_match = regexp(pres_xml, '<p:sldIdLst>(.*?)</p:sldIdLst>', 'tokens', 'once');
    if isempty(list_match)
        error('smp_pptx_add_slide: Could not find <p:sldIdLst> in presentation.xml');
    end
    inner = list_match{1};

    entries = regexp(inner, '<p:sldId[^/]*/>', 'match');

    if insert_pos > numel(entries) + 1
        insert_pos = numel(entries) + 1;
    end
    if insert_pos < 1
        insert_pos = 1;
    end

    new_entries = [entries(1:insert_pos-1), {new_entry}, entries(insert_pos:end)];
    new_inner = strjoin(new_entries, '');

    pres_xml = strrep(pres_xml, ['<p:sldIdLst>', inner, '</p:sldIdLst>'], ...
                                 ['<p:sldIdLst>', new_inner, '</p:sldIdLst>']);
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