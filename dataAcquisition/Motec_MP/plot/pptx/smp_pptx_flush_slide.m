function smp_pptx_flush_slide(slide)
% SMP_PPTX_FLUSH_SLIDE  Write a slide's accumulated shapes (and any
%                        picture relationships) into its actual XML/.rels
%                        files on disk.
%
% Call this once after all smp_pptx_add_textbox / smp_pptx_add_picture
% calls for a given slide are done. smp_save_close_pptx also calls this
% automatically for any slides passed to it, so explicit calls are only
% needed if you want to inspect/finalize a slide mid-flow.

    % --- Insert accumulated shape XML into the {{SHAPES}} placeholder ---
    slide_xml = fileread(slide.path);
    shapes_xml = strjoin(slide.shapes, '');
    slide_xml = strrep(slide_xml, '{{SHAPES}}', shapes_xml);
    write_text_file(slide.path, slide_xml);

    % --- Append any picture / hyperlink relationships to the slide's
    %     .rels file. Both are collected here (rather than written
    %     immediately when added) because they share slide.rid_counter
    %     and are only finalised at flush time, same as media_rels. ---
    has_media = isfield(slide, 'media_rels')     && ~isempty(slide.media_rels);
    has_hlink = isfield(slide, 'hyperlink_rels') && ~isempty(slide.hyperlink_rels);

    if has_media || has_hlink
        rels_xml = fileread(slide.rels_path);
        new_rels = '';

        if has_media
            for i = 1:numel(slide.media_rels)
                r = slide.media_rels{i};
                new_rels = [new_rels, sprintf(...
                    '<Relationship Id="%s" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="%s"/>', ...
                    r.rid, r.target)]; %#ok<AGROW>
            end
        end

        if has_hlink
            for i = 1:numel(slide.hyperlink_rels)
                r = slide.hyperlink_rels{i};
                new_rels = [new_rels, sprintf(...
                    '<Relationship Id="%s" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="%s"/>', ...
                    r.rid, r.target)]; %#ok<AGROW>
            end
        end

        rels_xml = strrep(rels_xml, '</Relationships>', [new_rels, '</Relationships>']);
        write_text_file(slide.rels_path, rels_xml);
    end
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
