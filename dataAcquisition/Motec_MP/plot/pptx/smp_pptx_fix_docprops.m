function smp_pptx_fix_docprops(pkg)
% SMP_PPTX_FIX_DOCPROPS  Reconcile docProps/app.xml with the actual final
%                         slide count before zipping.
%
% WHY THIS EXISTS:
%   smp_pptx_add_slide correctly updates presentation.xml, its .rels, and
%   [Content_Types].xml when slides are added — but never touches
%   docProps/app.xml. That part carries a <Slides>N</Slides> count plus a
%   HeadingPairs/TitlesOfParts vt:vector pair whose declared "size"
%   attribute must equal the number of <vt:lpstr>/<vt:variant> children
%   it contains (this is a hard OOXML schema constraint, not just
%   cosmetic metadata).
%
%   Once slides are added without updating app.xml, that count/size goes
%   stale relative to the real slide count in presentation.xml. Windows
%   PowerPoint validates this strictly and prompts "PowerPoint found a
%   problem with content" / repair on open. macOS Keynote and Preview do
%   not validate this part, which is why the corruption is invisible
%   there. Once PowerPoint "repairs" the file, it rewrites app.xml
%   correctly and it opens cleanly forever after — matching the
%   resave-fixes-it symptom.
%
% Call this once, after all slides have been added/flushed and
% pkg.slide_order reflects the final slide count, right before zipping.

    app_path = fullfile(pkg.work_dir, 'docProps', 'app.xml');
    if ~exist(app_path, 'file')
        return;   % nothing to fix — template has no app.xml
    end

    xml = fileread(app_path);
    n_slides = numel(pkg.slide_order);

    % --- Simple <Slides>N</Slides> count ---
    xml = regexprep(xml, '<Slides>\d+</Slides>', sprintf('<Slides>%d</Slides>', n_slides));

    % --- HeadingPairs: find the "Slide Titles" category pair, update its count ---
    old_tok = regexp(xml, ...
        '<vt:lpstr>Slide Titles</vt:lpstr></vt:variant><vt:variant><vt:i4>(\d+)</vt:i4>', ...
        'tokens', 'once');

    if isempty(old_tok)
        write_text_file(app_path, xml);
        return;   % no Slide Titles category present — nothing further to reconcile
    end

    old_slide_title_count = str2double(old_tok{1});

    xml = regexprep(xml, ...
        '(<vt:lpstr>Slide Titles</vt:lpstr></vt:variant><vt:variant><vt:i4>)\d+(</vt:i4>)', ...
        sprintf('$1%d$2', n_slides));

    delta = n_slides - old_slide_title_count;

    if delta ~= 0
        tp_match = regexp(xml, ...
            '<TitlesOfParts><vt:vector size="(\d+)" baseType="lpstr">(.*?)</vt:vector></TitlesOfParts>', ...
            'tokens', 'once');

        if ~isempty(tp_match)
            old_total = str2double(tp_match{1});
            inner     = tp_match{2};

            if delta > 0
                extra = '';
                for k = 1:delta
                    extra = [extra, sprintf('<vt:lpstr>Slide %d</vt:lpstr>', old_slide_title_count + k)]; %#ok<AGROW>
                end
                new_inner = [inner, extra];
            else
                % Defensive only — slides are never removed by this
                % pipeline, but trim trailing entries if they ever are.
                entries   = regexp(inner, '<vt:lpstr>.*?</vt:lpstr>', 'match');
                entries   = entries(1:end+delta);
                new_inner = strjoin(entries, '');
            end

            new_total = old_total + delta;
            old_block = sprintf('<TitlesOfParts><vt:vector size="%d" baseType="lpstr">%s</vt:vector></TitlesOfParts>', old_total, inner);
            new_block = sprintf('<TitlesOfParts><vt:vector size="%d" baseType="lpstr">%s</vt:vector></TitlesOfParts>', new_total, new_inner);
            xml = strrep(xml, old_block, new_block);
        end
    end

    write_text_file(app_path, xml);
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
