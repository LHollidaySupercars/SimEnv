function mf_plot_model_vs_data(data, conditions, cfg, layer2, Fnomin, Pnomin, slipChannel, forceChannel, IAfilter)
% MF_PLOT_MODEL_VS_DATA  Overlay the Layer-2-predicted Magic Formula
% curve on top of the raw (grey) and binned (black) data, for every
% condition matching IAfilter (default: 0 deg, the reference camber
% used when fitting Layer 2).
%
% Both the raw scatter and the binned line now apply the same
% pure-slip exclusion used in mf_viewer.m and mf_run_layer1_for_all --
% i.e. samples where the SECONDARY channel (SA when plotting SR/Fx, or
% SR when plotting SA/Fy) falls outside its pure-slip range are
% dropped before plotting/binning, not just visually flagged. Without
% this, the plot would show combined-slip-contaminated data even
% though the fit itself was computed only from pure-slip samples.
%
% Pnomin is used (together with each condition's own commanded/measured
% pressure) so the overlaid model curve reflects pressure effects, if
% layer2 was fit with 'FitPressure', true. Pass [] for Pnomin if your
% model doesn't use pressure.
%
% Usage:
%   mf_plot_model_vs_data(data, conditions, cfg, layer2X, Fnomin, Pnomin, 'SR', 'Fx');
%   mf_plot_model_vs_data(data, conditions, cfg, layer2X, Fnomin, Pnomin, 'SR', 'Fx', -2);

if nargin < 9
    IAfilter = 0;
end

if strcmp(slipChannel, 'SA')
    slipRange = cfg.saRange;
    binWidth  = cfg.saBinWidth;
    slipLabel = 'Slip angle SA [deg]';
    secChannel = 'SR';
    secRange = cfg.srRange;
else
    slipRange = cfg.srRange;
    binWidth  = cfg.srBinWidth;
    slipLabel = 'Slip ratio SR [-]';
    secChannel = 'SA';
    secRange = cfg.saRange;
end

matchIdx = find([conditions.IA] == IAfilter);
if isempty(matchIdx)
    error('mf_plot_model_vs_data:noMatch', 'No conditions found with IA == %.2f', IAfilter);
end

nPlots = numel(matchIdx);
nCols = ceil(sqrt(nPlots));
nRows = ceil(nPlots / nCols);

figure('Name', sprintf('Model vs data (IA=%.1f deg)', IAfilter), 'Position', [100 100 1400 900]);

xFine = linspace(slipRange(1), slipRange(2), 200)';

for i = 1:nPlots
    k = matchIdx(i);
    c = conditions(k);

    subplot(nRows, nCols, i);
    hold on;

    % Apply the pure-slip exclusion BEFORE plotting/binning -- the
    % piece that was missing. Without it, this function shows
    % combined-slip-contaminated data even though the fit itself
    % (mf_run_layer1_for_all) was computed only from pure-slip samples.
    if isfield(data, secChannel)
        secVals = data.(secChannel)(c.idx);
        pureMask = secVals >= secRange(1) & secVals <= secRange(2);
    else
        pureMask = true(nnz(c.idx), 1);
    end
    idxAll = find(c.idx);
    pureIdx = false(size(c.idx));
    pureIdx(idxAll(pureMask)) = true;

    % Raw + binned data (pure-slip only)
    slip  = data.(slipChannel)(pureIdx);
    force = data.(forceChannel)(pureIdx);
    inRange = slip >= slipRange(1) & slip <= slipRange(2);
    scatter(slip(inRange), force(inRange), 6, [0.75 0.75 0.75], 'filled', 'MarkerFaceAlpha', 0.3);

    binned = mf_bin_slip(data, pureIdx, slipChannel, forceChannel, binWidth, slipRange);
    plot(binned.slip, binned.force, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 3);

    % Forward model prediction at this condition's actual Fz, IA, and P
    [B, C, D, E, Easym, Sh, Sv, G] = mf_predict_coeffs(layer2, c.Fz, c.IA, c.P, c.SA, xFine, Fnomin, Pnomin);
                                  % mf_predict_coeffs(layer2,   Fz,   IA, P, Fnomin, Pnomin)
    yFine = mf_eval_magic_formula(B, C, D, E, Easym, Sh, Sv, G, xFine);
    plot(xFine, yFine, 'r-', 'LineWidth', 1.8);

    title(sprintf('Fz=%.0fN  IA=%.1f\\circ  P=%s  (n_{pure}=%d/%d)', ...
        c.Fz, c.IA, ternaryLocal(isnan(c.P), 'n/a', sprintf('%.0f', c.P)), nnz(pureMask), numel(pureMask)));
    xlabel(slipLabel);
    ylabel(forceChannel);
    grid on;

    if i == 1
        legend({'raw (pure slip)', 'binned (pure slip)', 'model'}, 'Location', 'best');
    end
end

sgtitle(sprintf('%s vs %s: fitted model (red) vs pure-slip data, IA = %.1f deg', forceChannel, slipChannel, IAfilter));

end


function out = ternaryLocal(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end


function y = mf_eval_magic_formula(B, C, D, E, Easym, Sh, Sv, G, x)
% Same core equation as mf_magic_formula (inside mf_layer1_fit.m),
% including brake/drive asymmetry, exposed here as a standalone
% function so plotting code doesn't depend on mf_layer1_fit's internal
% (nested) function.
xs = x + Sh;
Eeff = E .* (1 - Easym .* sign(xs));
y = (D .* sin(C .* atan(B.*xs - Eeff.*(B.*xs - atan(B.*xs)))) + Sv) .* G;
end