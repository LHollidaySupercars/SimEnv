function [pptApp, prs] = smp_open_pptx(template_path, output_path)
% SMP_OPEN_PPTX  Open a PowerPoint template via COM automation.
%
% Copies the template to output_path, then opens it ready for editing.
% Requires Microsoft PowerPoint to be installed (Windows only).
%
% Usage:
%   [pptApp, prs] = smp_open_pptx('C:\templates\SMP_template.pptx', ...
%                                  'C:\output\SMP_Report_R1.pptx')

    if ~exist(template_path, 'file')
        error('smp_open_pptx: Template not found: %s', template_path);
    end

    % Copy template to output location
    copyfile(template_path, output_path);
    fprintf('Template copied to: %s\n', output_path);

    % Start PowerPoint via COM
    pptApp = actxserver('PowerPoint.Application');
    pptApp.Visible = 1;   % set to 0 for headless if desired

    % Open the copied file
    prs = pptApp.Presentations.Open(output_path, 0, 0, 1);
    fprintf('Presentation opened: %d slides in template.\n', prs.Slides.Count);
end


% ======================================================================= %
function slide = smp_add_slide(prs, layout_index)
% SMP_ADD_SLIDE  Add a new slide using a layout from the template.
%
% Usage:
%   slide = smp_add_slide(prs, 2)   % layout 2 = content layout

    n = prs.Slides.Count;
    slide = prs.Slides.Add(n+1, layout_index);
end


% ======================================================================= %
function smp_set_text(slide, placeholder_idx, text_str)
% SMP_SET_TEXT  Write text to a placeholder on a slide.

    try
        ph = slide.Placeholders.Item(placeholder_idx);
        ph.TextFrame.TextRange.Text = text_str;
    catch ME
        fprintf('[smp_set_text] Could not write to placeholder %d: %s\n', ...
            placeholder_idx, ME.message);
    end
end


% ======================================================================= %
function smp_insert_figure(slide, fig, left, top, max_width, max_height)
% SMP_INSERT_FIGURE  Export a MATLAB figure and embed it in a slide,
%                    preserving the figure's original aspect ratio.
%
% The image is scaled to fit within [max_width x max_height] without
% stretching. It is centred within that bounding box.
%
% Coordinates are in points (1 inch = 72 points).
% Standard 16:9 slide = 720 x 405 points.
%
% Usage:
%   smp_insert_figure(slide, fig)                        % auto layout
%   smp_insert_figure(slide, fig, left, top, w, h)       % explicit bounds
%
% Default bounding box fills most of the slide below the title:
%   left=18, top=72, max_width=684, max_height=306

    if nargin < 3, left      = 18;  end   % 0.25 inch margin
    if nargin < 4, top       = 72;  end   % below title area (~1 inch)
    if nargin < 5, max_width = 684; end   % ~9.5 inch wide
    if nargin < 6, max_height= 306; end   % ~4.25 inch tall

    % --- Read figure pixel dimensions to compute true aspect ratio ---
    fig_pos   = get(fig, 'Position');   % [x y width_px height_px]
    fig_w_px  = fig_pos(3);
    fig_h_px  = fig_pos(4);

    if fig_w_px <= 0 || fig_h_px <= 0
        fig_w_px = 1200;
        fig_h_px = 650;
        warning('smp_insert_figure: could not read figure size; assuming 1200x650 px.');
    end

    aspect = fig_w_px / fig_h_px;   % width:height ratio

    % --- Scale to fit bounding box, preserving aspect ratio ---
    % Try fitting to max_width first
    img_w = max_width;
    img_h = img_w / aspect;

    % If too tall, fit to max_height instead
    if img_h > max_height
        img_h = max_height;
        img_w = img_h * aspect;
    end

    % --- Centre within bounding box ---
    offset_x = (max_width  - img_w) / 2;
    offset_y = (max_height - img_h) / 2;
    final_left = left + offset_x;
    final_top  = top  + offset_y;

    % --- Export to high-res PNG ---
    tmp = [tempname, '.png'];
    exportgraphics(fig, tmp, 'Resolution', 150, 'BackgroundColor', 'white');

    % --- Insert into slide at computed position/size ---
    slide.Shapes.AddPicture(tmp, 0, 1, final_left, final_top, img_w, img_h);

    % Clean up
    try; delete(tmp); catch; end
    close(fig);
end


% ======================================================================= %
function smp_save_close_pptx(pptApp, prs)
% SMP_SAVE_CLOSE_PPTX  Save (overwrite in place) and close the presentation.

    prs.Save();
    prs.Close();
    pptApp.Quit();
    delete(pptApp);
    fprintf('Presentation saved and closed.\n');
end