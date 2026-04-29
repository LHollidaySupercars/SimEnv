function out = align_to(source_ch, target_ch)
% Resample source_ch onto the time base of target_ch.
% Binary channels (unique finite values are a subset of {0,1}) are
% interpolated with 'nearest' to preserve square-wave shape.
% All other channels use 'linear'.
    s_t = source_ch.time(:);
    t_t = target_ch.time(:);
    if numel(s_t) == numel(t_t) && max(abs(s_t - t_t)) < 1e-9
        out = source_ch.data(:);
        return;
    end
    % Detect binary channel from data content
    finite_vals = unique(source_ch.data(isfinite(source_ch.data)));
    if all(ismember(finite_vals, [0; 1]))
        method = 'nearest';
    else
        method = 'linear';
    end
    t_q = min(max(t_t, s_t(1)), s_t(end));
    out = interp1(s_t, source_ch.data(:), t_q, method, 'extrap');
    out = out(:);
end