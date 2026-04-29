%% singleLapInvestigation.m

clear; clc; close all;

%% CONFIG
LD_FILE = { "E:\2026\02_AGP\L180\20260305-241280000.ld"}
MIN_LAP_S = 85;
MAX_LAP_S = 115;
plotPSD = 1;laps = [];
slice_opts.min_lap_time = MIN_LAP_S;
slice_opts.max_lap_time = MAX_LAP_S;
slice_opts.verbose      = true;
for f = 1:numel(LD_FILE)
    ch_f    = motec_ld_reader(LD_FILE{f});
    laps_f  = lap_slicer(ch_f);
    laps    = [laps, laps_f];
end


%% FASTEST LAP
fastest = [];
for f = 1:numel(LD_FILE)
    ch_f   = motec_ld_reader(LD_FILE{f});
    laps_f = lap_slicer(ch_f, slice_opts);
    if isempty(laps_f), continue; end
    [~, bi] = min([laps_f.lap_time]);
    fastest = [fastest, laps_f(bi)];
end
fprintf('\n%d fastest laps found\n', numel(fastest));
%%

if plotPSD
    damper_chs = {'C1_Damper_Pos_FL', 'C1_Damper_Pos_FR', ...
                  'C1_Damper_Pos_RL', 'C1_Damper_Pos_RR'};
    win_len  = 256;
    overlap  = 128;
    nfft     = 512;
    freq_max = 12;

    colors        = {[0.12 0.31 0.64], [0.18 0.63 0.18], [0.84 0.13 0.13], [0.96 0.75 0.05]};
    line_styles   = {'-', '--'};   % solid = file 1, dashed = file 2
    corner_labels = {'FL','FR','RL','RR'};

    figure('Name','Damper PSD - Comparison', 'Position',[100 100 1200 700]);

    for ci = 1:numel(damper_chs)
        subplot(2, 2, ci);  hold on;
        ch_name = damper_chs{ci};

        for fi = 1:numel(fastest)
            lap_ch = fastest(fi).channels;
            fn     = fieldnames(lap_ch);
            match  = fn(strcmpi(fn, ch_name));
            if isempty(match)
                fprintf('[WARN] File %d: %s not found\n', fi, ch_name);
                continue;
            end

            sig = lap_ch.(match{1}).data(:);
            sig(isnan(sig)) = 0;
            sig = sig - mean(sig);
            Fs  = lap_ch.(match{1}).sample_rate;

            w       = 0.5*(1 - cos(2*pi*(0:win_len-1)'/(win_len-1)));
            w_power = sum(w.^2);
            starts  = 1:(win_len-overlap):numel(sig)-win_len+1;
            n_segs  = numel(starts);
            pxx     = zeros(nfft/2+1, 1);
            for k = 1:n_segs
                seg = sig(starts(k):starts(k)+win_len-1) .* w;
                X   = fft(seg, nfft);
                pxx = pxx + abs(X(1:nfft/2+1)).^2;
            end
            pxx = pxx / (n_segs * Fs * w_power);
            pxx(2:end-1) = 2*pxx(2:end-1);
            f = (0:nfft/2)' * Fs / nfft;

            f_mask = f > 0.2 & f <= freq_max;
semilogy(f(f_mask), pxx(f_mask), ...
    'Color',     colors{fi}, ...
    'LineWidth', 1.5, ...
    'DisplayName', sprintf('File %d — Lap %d (%.3fs)', ...
        fi, fastest(fi).lap_number, fastest(fi).lap_time));
set(gca, 'YScale', 'log');
        end

        title(sprintf('%s', corner_labels{ci}), 'Interpreter','none');
        xlabel('Frequency (Hz)');
        ylabel('PSD (mm²/Hz)');
        grid on;
        xlim([0.2 freq_max]);
        legend('Location','northeast');
    end

    sgtitle(sprintf('Damper PSD | Comparison | win=%d  ovlp=%d  nfft=%d', ...
        win_len, overlap, nfft), 'FontSize', 12);
end