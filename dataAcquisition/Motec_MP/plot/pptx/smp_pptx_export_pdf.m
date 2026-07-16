function pdf_path = smp_pptx_export_pdf(pptx_path)
% SMP_PPTX_EXPORT_PDF  Export a PDF alongside an already-saved .pptx.
%
% This is a read-only conversion of a finished file — it never touches
% the OOXML parts directly, so it can't introduce the kind of corruption
% that hand-rolled XML editing can. Two strategies, tried in order:
%
%   1. LibreOffice headless (`soffice --headless --convert-to pdf`) —
%      works identically on macOS/Windows/Linux if LibreOffice is
%      installed. Preferred because it needs no PowerPoint install and
%      no COM, keeping the whole pipeline Mac-compatible.
%   2. PowerPoint COM Export (Windows only, requires PowerPoint
%      installed) — fallback if LibreOffice isn't found.
%
% Usage:
%   pdf_path = smp_pptx_export_pdf('/path/to/report.pptx')
%
% Returns the path to the generated PDF, or '' if export failed (a
% warning is printed either way rather than throwing, so callers in a
% batch-report loop aren't halted by a missing converter).

    if ~exist(pptx_path, 'file')
        error('smp_pptx_export_pdf: File not found: %s', pptx_path);
    end

    [out_dir, out_name, ~] = fileparts(pptx_path);
    pdf_path = fullfile(out_dir, [out_name, '.pdf']);

    % --- Strategy 1: LibreOffice headless ---
    soffice_cmd = find_soffice();
    if ~isempty(soffice_cmd)
        fprintf('--- Exporting PDF via LibreOffice headless ---\n');
        cmd = sprintf('"%s" --headless --convert-to pdf --outdir "%s" "%s"', ...
                       soffice_cmd, out_dir, pptx_path);
        [status, cmdout] = system(cmd);
        if status == 0 && exist(pdf_path, 'file')
            fprintf('PDF saved: %s\n', pdf_path);
            return;
        else
            fprintf('[WARN] LibreOffice conversion failed (status %d):\n%s\n', status, cmdout);
        end
    end

    % --- Strategy 2: PowerPoint COM (Windows only) ---
    if ispc
        try
            fprintf('--- Exporting PDF via PowerPoint COM ---\n');
            pptApp = actxserver('PowerPoint.Application');
            prs = pptApp.Presentations.Open(pptx_path, 0, 0, 0);
            prs.SaveAs(pdf_path, 32);   % 32 = ppSaveAsPDF
            prs.Close();
            pptApp.Quit();
            delete(pptApp);
            if exist(pdf_path, 'file')
                fprintf('PDF saved: %s\n', pdf_path);
                return;
            end
        catch ME
            fprintf('[WARN] PowerPoint COM conversion failed: %s\n', ME.message);
        end
    end

    warning('smp_pptx_export_pdf:noConverter', ...
        ['Could not export PDF: no working converter found. ', ...
         'Install LibreOffice (recommended, cross-platform) or, on ', ...
         'Windows, ensure PowerPoint is installed for COM export.']);
    pdf_path = '';
end


% ======================================================================= %
function cmd = find_soffice()
% Locate a usable LibreOffice `soffice` executable across platforms.
% Returns '' if none found.
    candidates = {};
    if ismac
        candidates = {'/Applications/LibreOffice.app/Contents/MacOS/soffice'};
    elseif ispc
        candidates = {
            'C:\Program Files\LibreOffice\program\soffice.exe', ...
            'C:\Program Files (x86)\LibreOffice\program\soffice.exe'};
    else
        candidates = {'/usr/bin/soffice', '/usr/local/bin/soffice'};
    end

    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file')
            cmd = candidates{i};
            return;
        end
    end

    % Fall back to checking PATH
    [status, ~] = system('soffice --version');
    if status == 0
        cmd = 'soffice';
        return;
    end

    cmd = '';
end
