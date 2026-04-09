function smp_insert_figure(slide, fig, left, top, max_width, max_height)

    if nargin < 3, left       = 18;  end
    if nargin < 4, top        = 72;  end
    if nargin < 5, max_width  = 684; end
    if nargin < 6, max_height = 306; end

    % --- Read figure's true pixel dimensions ---
    fig_pos = get(fig, 'Position');   % [x y width_px height_px]
    fig_w   = fig_pos(3);
    fig_h   = fig_pos(4);
    aspect  = fig_w / fig_h;

    % --- Fit within bounding box, preserving aspect ratio ---
    img_w = max_width;
    img_h = img_w / aspect;

    if img_h > max_height          % too tall — constrain by height instead
        img_h = max_height;
        img_w = img_h * aspect;
    end

    % --- Centre within the bounding box ---
    final_left = left + (max_width  - img_w) / 2;
    final_top  = top  + (max_height - img_h) / 2;

    % --- Export and insert ---
    tmp = [tempname, '.png'];
    exportgraphics(fig, tmp, 'Resolution', 150, 'BackgroundColor', 'white');
    slide.Shapes.AddPicture(tmp, 0, 1, final_left, final_top, img_w, img_h);

    try; delete(tmp); catch; end
    close(fig);
end