function [data_out, dist_out] = smp_resample(data_in, dist_in, target_res)
% SMP_RESAMPLE  Resample a data channel onto a uniform distance grid.
%
% Takes a channel's data and its corresponding distance axis and resamples
% to a new uniform distance grid at the specified resolution. Handles both
% upsampling and downsampling robustly.
%
% Usage:
%   [data_out, dist_out] = smp_resample(data_in, dist_in)
%   [data_out, dist_out] = smp_resample(data_in, dist_in, target_res)
%
% Inputs:
%   data_in     - (Nx1) channel data values
%   dist_in     - (Nx1) distance values (metres), must be same length as data_in
%   target_res  - (optional) target distance resolution in metres per sample
%                 If omitted, uses the median spacing of dist_in (no resampling
%                 of grid density, just cleans up non-monotonic points)
%
% Outputs:
%   data_out    - resampled data on uniform distance grid
%   dist_out    - uniform distance grid (metres), same length as data_out
%
% Notes:
%   - Non-monotonic distance points are removed before resampling
%   - NaNs in data are handled via linear interpolation where possible
%   - Extrapolation beyond the original distance range returns NaN
%   - If fewer than 2 valid points remain after cleaning, returns empty

    data_in = data_in(:);
    dist_in = dist_in(:);

    if numel(data_in) ~= numel(dist_in)
        error('smp_resample: data_in and dist_in must be the same length.');
    end

    % ------------------------------------------------------------------
    %  Clean: remove NaN distance, enforce monotonic increasing
    % ------------------------------------------------------------------
    valid = isfinite(dist_in);
    dist_in  = dist_in(valid);
    data_in  = data_in(valid);

    if numel(dist_in) < 2
        data_out = [];
        dist_out = [];
        return;
    end

    % Remove non-monotonic points (keep first occurrence at each distance)
    mono = [true; diff(dist_in) > 0];
    dist_in = dist_in(mono);
    data_in = data_in(mono);

    if numel(dist_in) < 2
        data_out = [];
        dist_out = [];
        return;
    end

    % ------------------------------------------------------------------
    %  Determine target resolution
    % ------------------------------------------------------------------
    if nargin < 3 || isempty(target_res) || target_res <= 0
        % Use median spacing of the input — preserves natural frequency
        target_res = median(diff(dist_in));
    end

    % ------------------------------------------------------------------
    %  Build uniform distance grid
    % ------------------------------------------------------------------
    d_start = dist_in(1);
    d_end   = dist_in(end);

    dist_out = (d_start : target_res : d_end)';

    if numel(dist_out) < 2
        % Edge case: lap is shorter than one resolution step
        dist_out = [d_start; d_end];
    end

    % ------------------------------------------------------------------
    %  Interpolate data onto uniform grid
    %  NaNs in data_in are skipped — interp1 fills gaps linearly
    % ------------------------------------------------------------------
    finite_mask = isfinite(data_in);

    if sum(finite_mask) < 2
        % Not enough finite points to interpolate
        data_out = NaN(numel(dist_out), 1);
        return;
    end

    d_finite = dist_in(finite_mask);
    v_finite = data_in(finite_mask);

    % Remove any duplicate distances after NaN removal
    [d_finite, ia] = unique(d_finite, 'stable');
    v_finite = v_finite(ia);

    if numel(d_finite) < 2
        data_out = NaN(numel(dist_out), 1);
        return;
    end

    % Interpolate — NaN outside original range (no extrapolation)
    data_out = interp1(d_finite, v_finite, dist_out, 'linear', NaN);

end
