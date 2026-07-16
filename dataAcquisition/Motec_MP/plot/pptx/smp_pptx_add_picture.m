function [pkg, slide] = smp_pptx_add_picture(pkg, slide, image_path, left_pt, top_pt, width_pt, height_pt)
% SMP_PPTX_ADD_PICTURE  Add a picture to a slide (in-memory shape list +
%                        immediate media copy/relationship registration).
%
% Usage:
%   [pkg, slide] = smp_pptx_add_picture(pkg, slide, '/tmp/fig.png', left, top, w, h)
%
% Coordinates are in POINTS (1 inch = 72 pt), matching the existing
% script's layout convention.

    if ~exist(image_path, 'file')
        error('smp_pptx_add_picture: Image not found: %s', image_path);
    end

    EMU_PER_PT = 12700;
    left_emu   = round(left_pt   * EMU_PER_PT);
    top_emu    = round(top_pt    * EMU_PER_PT);
    width_emu  = round(width_pt  * EMU_PER_PT);
    height_emu = round(height_pt * EMU_PER_PT);

    % --- Copy image into ppt/media with a unique name ---
    media_dir = fullfile(pkg.work_dir, 'ppt', 'media');
    if ~exist(media_dir, 'dir'), mkdir(media_dir); end

    [~, ~, ext] = fileparts(image_path);
    media_name  = sprintf('image_%s%s', char(matlab.lang.makeValidName(slide.file)), ...
                           sprintf('_%d', numel(slide.media_rels)+1));
    media_name  = [media_name, ext];
    copyfile(image_path, fullfile(media_dir, media_name));

    % --- Relationship for this slide ---
    rid = sprintf('rId%d', slide.rid_counter);
    slide.rid_counter = slide.rid_counter + 1;
    slide.media_rels{end+1} = struct('rid', rid, 'target', sprintf('../media/%s', media_name));

    % --- Shape XML ---
    shape_id = slide.next_shape_id;
    slide.next_shape_id = slide.next_shape_id + 1;

    shape_xml = sprintf([...
        '<p:pic><p:nvPicPr><p:cNvPr id="%d" name="Picture %d"/>' ...
        '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>' ...
        '<p:blipFill><a:blip r:embed="%s"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>' ...
        '<p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>' ...
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>'], ...
        shape_id, shape_id, rid, left_emu, top_emu, width_emu, height_emu);

    slide.shapes{end+1} = shape_xml;
end
