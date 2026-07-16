function y = lowpass_filter(x, t, tau)
% LOWPASS_FILTER  First-order (exponential) low-pass filter, no toolbox required.
% Matches MoTeC's filter_lp(channel, tau) behavior.
%
% Inputs:
%   x   - signal vector to filter
%   t   - time vector, same length as x (seconds, monotonic increasing)
%   tau - filter time constant (seconds). Larger tau = more smoothing.
%
% Output:
%   y   - filtered signal, same size as x
%
% Example:
%   y = lowpass_filter(ThrottlePedal, t, 0.8);

x = x(:);
t = t(:);
dt = diff(t);

% Per-sample smoothing coefficient (handles variable sample rate)
alpha = dt ./ (tau + dt);

y = zeros(size(x));
y(1) = x(1);
for k = 2:numel(x)
    y(k) = y(k-1) + alpha(k-1) * (x(k) - y(k-1));
end

end