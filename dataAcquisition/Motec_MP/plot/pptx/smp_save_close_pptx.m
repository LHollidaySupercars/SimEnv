function smp_save_close_pptx(pptApp, prs)
    % Save as PPTX
    try
        prs.Save();
        fprintf('Presentation saved.\n');
    catch ME
        fprintf('[WARN] Could not save PPTX: %s\n', ME.message);
    end

    % Save as PDF alongside the PPTX
    try
        pptx_path = prs.FullName;
        [folder, name, ~] = fileparts(pptx_path);
        pdf_path = fullfile(folder, [name '.pdf']);
        prs.SaveAs(pdf_path, 32);   % 32 = ppSaveAsPDF
        fprintf('PDF saved: %s\n', pdf_path);
    catch ME
        fprintf('[WARN] Could not save PDF: %s\n', ME.message);
    end

    try; prs.Close();    catch; end
    try; pptApp.Quit();  catch; end
    try; delete(pptApp); catch; end
    fprintf('PowerPoint closed.\n');
end