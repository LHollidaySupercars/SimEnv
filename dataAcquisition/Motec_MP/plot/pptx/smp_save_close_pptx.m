function smp_save_close_pptx(pkg, slides, produce_pdf)
% SMP_SAVE_CLOSE_PPTX  Finalize the presentation: flush any pending
%                       slides, reconcile docProps metadata, re-zip the
%                       OOXML working directory into pkg.output_path,
%                       clean up the temp folder, and optionally export
%                       a PDF alongside it.
%
% No COM, no PowerPoint.Application required to write the .pptx itself.
%
% Usage:
%   smp_save_close_pptx(pkg)                        % all slides already flushed
%   smp_save_close_pptx(pkg, {slide1, slide2})       % flush these slide handles first
%   smp_save_close_pptx(pkg, {slide1, slide2}, true) % ...and also export a PDF
%
% slides (optional) is a cell array of slide handles (as returned by
% smp_pptx_add_slide) that haven't yet been flushed via
% smp_pptx_flush_slide. Passing them here flushes them automatically so
% callers don't have to remember to do it themselves before saving.
%
% produce_pdf (optional, default false) — if true, attempts to export a
% PDF with the same base name alongside the .pptx after it is saved. See
% smp_pptx_export_pdf.m for the platform-dependent conversion strategy
% (LibreOffice headless if available, else PowerPoint COM on Windows).
% This is a read-only conversion performed on the already-saved .pptx,
% so it can't introduce the OOXML corruption issues that direct XML
% manipulation can.

    if nargin < 3 || isempty(produce_pdf)
        produce_pdf = false;
    end

    if nargin >= 2 && ~isempty(slides)
        for i = 1:numel(slides)
            smp_pptx_flush_slide(slides{i});
        end
    end

    % --- Reconcile docProps/app.xml slide-count metadata with the final
    %     slide order. Left stale, this is a strict OOXML schema
    %     violation that Windows PowerPoint flags as corruption on open
    %     (macOS Keynote/Preview don't validate it, hence the
    %     Mac-clean / Windows-repair split). ---
    smp_pptx_fix_docprops(pkg);

    % --- Re-zip work_dir into output_path ---
    % MATLAB's zip() always appends a .zip extension and wraps contents
    % in the top-level folder name, neither of which is OOXML-compliant,
    % so we zip into a temp .zip then move/rename into place.
    [out_dir, out_name, out_ext] = fileparts(pkg.output_path); %#ok<ASGLU>
    tmp_zip_base = fullfile(tempdir, [out_name, '_', char(matlab.lang.makeValidName(tempname))]);

    cwd = pwd();
    try
        cd(pkg.work_dir);
        files_to_zip = get_all_files_relative(pkg.work_dir);
        zip(tmp_zip_base, files_to_zip);
    catch ME
        cd(cwd);
        rethrow(ME);
    end
    cd(cwd);

    tmp_zip_path = [tmp_zip_base, '.zip'];

    if exist(pkg.output_path, 'file')
        delete(pkg.output_path);
    end
    movefile(tmp_zip_path, pkg.output_path);

    % --- Clean up temp working directory ---
    try
        rmdir(pkg.work_dir, 's');
    catch
        % non-fatal - leftover temp dir, not worth failing the whole save
    end

    fprintf('Presentation saved: %s\n', pkg.output_path);

    % --- Optional PDF export (post-save, read-only conversion) ---
    if produce_pdf
        try
            smp_pptx_export_pdf(pkg.output_path);
        catch ME_pdf
            fprintf('[WARN] PDF export failed: %s\n', ME_pdf.message);
        end
    end
end


% ======================================================================= %
function rel_files = get_all_files_relative(root_dir)
% Recursively list all files under root_dir, as paths relative to
% root_dir (required so zip() doesn't bake in absolute paths).
    all_files = dir(fullfile(root_dir, '**', '*'));
    all_files = all_files(~[all_files.isdir]);

    rel_files = cell(1, numel(all_files));
    for i = 1:numel(all_files)
        full_path = fullfile(all_files(i).folder, all_files(i).name);
        rel_files{i} = strrep(full_path, [root_dir, filesep], '');
    end
end
