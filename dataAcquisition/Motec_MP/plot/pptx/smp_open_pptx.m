function pkg = smp_open_pptx(template_path, output_path)
% SMP_OPEN_PPTX  Open a PowerPoint template for editing via direct OOXML
%                manipulation (no COM, no actxserver — works on Mac/Linux/Win).
%
% Copies the template to output_path, unzips it to a temp working
% directory, and returns a "pkg" struct that tracks all the state needed
% to add slides/shapes and re-zip at the end. This struct is the
% Mac-safe replacement for the COM (pptApp, prs) handle pair.
%
% Usage:
%   pkg = smp_open_pptx('/path/to/template.pptx', '/path/to/output.pptx')
%
% Fields on pkg (treat as opaque — pass to smp_pptx_* functions):
%   pkg.work_dir      - temp folder holding unzipped OOXML parts
%   pkg.output_path    - final .pptx path to write on save
%   pkg.next_slide_num - next slideN.xml index to use
%   pkg.next_rid_pres   - next free rId in ppt/_rels/presentation.xml.rels
%   pkg.next_sld_id     - next free <p:sldId id="..."> value
%   pkg.slide_w_emu/h_emu - slide dimensions in EMU (from presentation.xml)
%   pkg.slide_order     - cell array of slide filenames in display order

    if ~exist(template_path, 'file')
        error('smp_open_pptx: Template not found: %s', template_path);
    end

    % --- Copy template alongside output, then unzip a working copy ---
    copyfile(template_path, output_path);
    fprintf('Template copied to: %s\n', output_path);

    work_dir = tempname();
    mkdir(work_dir);
    unzip(output_path, work_dir);

    pkg.work_dir    = work_dir;
    pkg.output_path = output_path;

    % --- Read presentation.xml to get slide size + existing slide order ---
    pres_path = fullfile(work_dir, 'ppt', 'presentation.xml');
    pres_xml  = fileread(pres_path);

    sz = regexp(pres_xml, '<p:sldSz cx="(\d+)" cy="(\d+)"', 'tokens', 'once');
    if isempty(sz)
        error('smp_open_pptx: Could not find slide size in presentation.xml');
    end
    pkg.slide_w_emu = str2double(sz{1});
    pkg.slide_h_emu = str2double(sz{2});

    % --- Existing slide rIds (to find next free rId / sldId / slide#) ---
    rels_path = fullfile(work_dir, 'ppt', '_rels', 'presentation.xml.rels');
    rels_xml  = fileread(rels_path);

    rid_nums = regexp(rels_xml, 'Id="rId(\d+)"', 'tokens');
    rid_nums = cellfun(@(c) str2double(c{1}), rid_nums);
    pkg.next_rid_pres = max(rid_nums) + 1;

    sldid_nums = regexp(pres_xml, '<p:sldId id="(\d+)"', 'tokens');
    sldid_nums = cellfun(@(c) str2double(c{1}), sldid_nums);
    if isempty(sldid_nums)
        pkg.next_sld_id = 256;
    else
        pkg.next_sld_id = max(sldid_nums) + 1;
    end

    slide_files = dir(fullfile(work_dir, 'ppt', 'slides', 'slide*.xml'));
    slide_nums  = regexp({slide_files.name}, 'slide(\d+)\.xml', 'tokens');
    slide_nums  = cellfun(@(c) str2double(c{1}{1}), slide_nums);
    if isempty(slide_nums)
        pkg.next_slide_num = 1;
    else
        pkg.next_slide_num = max(slide_nums) + 1;
    end

    % --- Slide display order, derived from presentation.xml's sldIdLst,
    %     resolved through presentation.xml.rels to actual filenames ---
    pkg.slide_order = resolve_slide_order(pres_xml, rels_xml);

    fprintf('Presentation opened: %d slides in template.\n', numel(pkg.slide_order));
end


% ======================================================================= %
function order = resolve_slide_order(pres_xml, rels_xml)
% Walk <p:sldIdLst> in document order, map each r:id to its slide filename
% via presentation.xml.rels.
    rid_list = regexp(pres_xml, '<p:sldId id="\d+" r:id="(rId\d+)"/>', 'tokens');
    rid_list = cellfun(@(c) c{1}, rid_list, 'UniformOutput', false);

    order = cell(1, numel(rid_list));
    for i = 1:numel(rid_list)
        rid = rid_list{i};
        pat = sprintf('Id="%s"[^>]*Target="slides/(slide\\d+\\.xml)"', rid);
        tok = regexp(rels_xml, pat, 'tokens', 'once');
        if isempty(tok)
            error('smp_open_pptx: Could not resolve %s to a slide file', rid);
        end
        order{i} = tok{1};
    end
end
