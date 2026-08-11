function smp_plot_pair_check(dash_file, ecu_file, session_label)
% SMP_PLOT_PAIR_CHECK  Visually verify Dash/ECU alignment after xcorr.
% Overlays RPM from both files on a shared time axis.
%
% Usage:
%   smp_plot_pair_check(dash_file, ecu_file)
%   smp_plot_pair_check(dash_file, ecu_file, 'ALL_Q17')

if nargin < 3
    [~, stem] = fileparts(dash_file);
    session_label = stem;
end

% ---- Load Dash RPM ----
fprintf('Loading Dash...\n');
da = motec_ld_reader(dash_file, {'Engine_Speed'}, false);
fn = fieldnames(da);
if isempty(fn)
    error('No usable RPM channel found in Dash file.');
end
ch_a = da.(fn{1});
t_a  = ch_a.time(:);
v_a  = double(ch_a.data(:));
fprintf('  Dash: %s  |  %.0f Hz  |  %.1f s  |  peak %.0f RPM\n', ...
    fn{1}, ch_a.sample_rate, t_a(end), max(v_a));

% ---- Load ECU RPM ----
fprintf('Loading ECU...\n');
ecu_candidates = {'Engine.Speed', 'Engine_Speed'};
db = [];
for ci = 1:numel(ecu_candidates)
    try
        tmp = motec_ld_reader(ecu_file, {ecu_candidates{ci}}, true);
        fn2 = fieldnames(tmp);
        if ~isempty(fn2) && max(tmp.(fn2{1}).data) > 2500
            db = tmp; break;
        end
    catch, end
end
if isempty(db)
    error('No usable RPM channel found in ECU file.');
end
fn2  = fieldnames(db);
ch_b = db.(fn2{1});
t_b  = ch_b.time(:);
v_b  = double(ch_b.data(:));
fprintf('  ECU:  %s  |  %.0f Hz  |  %.1f s  |  peak %.0f RPM\n', ...
    fn2{1}, ch_b.sample_rate, t_b(end), max(v_b));

% ---- Run xcorr to get offset ----
fprintf('Running xcorr...\n');
RESAMPLE_HZ = 50;
RPM_MIN     = 500;
dt          = 1 / RESAMPLE_HZ;

t_a_g = (t_a(1):dt:t_a(end))';
t_b_g = (t_b(1):dt:t_b(end))';
v_a_g = interp1(t_a, v_a, t_a_g, 'linear', NaN);
v_b_g = interp1(t_b, v_b, t_b_g, 'linear', NaN);

mask_a = v_a_g >= RPM_MIN & ~isnan(v_a_g);
mask_b = v_b_g >= RPM_MIN & ~isnan(v_b_g);

xc_a = v_a_g; xc_b = v_b_g;
xc_a(~mask_a) = 0; xc_b(~mask_b) = 0;
xc_a(mask_a)  = xc_a(mask_a) - mean(xc_a(mask_a));
xc_b(mask_b)  = xc_b(mask_b) - mean(xc_b(mask_b));

[xc_vals, lags] = xcorr(xc_a, xc_b);
[~, peak_idx]   = max(xc_vals);
lag_samples     = lags(peak_idx);
offset_s        = (t_a(1) - t_b(1)) + lag_samples * dt;

xc_norm = max(abs(xc_vals));
xc_self = sqrt(sum(xc_a.^2) * sum(xc_b.^2));
quality = 0;
if xc_self > 0, quality = xc_norm / xc_self; end

fprintf('  Offset: %+.3f s  |  Quality: %.4f\n', offset_s, quality);

% ---- Plot ----
t_b_aligned = t_b + offset_s;

figure('Name', ['Pair Check: ' session_label], 'Position', [100 100 1400 500]);

% Top: full signal overlay
subplot(2,1,1);
plot(t_a,         v_a, 'b',  'LineWidth', 0.8); hold on;
plot(t_b_aligned, v_b, 'r--','LineWidth', 0.8);
xlabel('Time (s)'); ylabel('RPM');
title(sprintf('%s  |  offset = %+.3fs  |  quality = %.4f', ...
    session_label, offset_s, quality));
legend('Dash (Engine\_Speed)', 'ECU (aligned)', 'Location', 'best');
grid on;

% Bottom: zoomed to first 300s of Dash for fine detail
subplot(2,1,2);
t_zoom = [t_a(1), min(t_a(1)+300, t_a(end))];
plot(t_a,         v_a, 'b',  'LineWidth', 1.0); hold on;
plot(t_b_aligned, v_b, 'r--','LineWidth', 1.0);
xlim(t_zoom);
xlabel('Time (s)'); ylabel('RPM');
title('Zoomed — first 300s of Dash');
legend('Dash', 'ECU (aligned)', 'Location', 'best');
grid on;
end


% =========================================================================
%  HELPER FUNCTIONS
% =========================================================================

