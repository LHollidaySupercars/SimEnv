%% RUN_LD_ADD_CHANNEL
clear; clc;

SOURCE_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890002.ld';
OUTPUT_FILE = 'E:\2026\T01_QLR\COM\debug_channel_test121.ld';

%% Define channels — one per available donor frequency + one random
freqs = [1, 2, 5, 10, 20, 25, 50, 100, 333];   % 333 Hz = non-existent donor

ch = struct([]);
for i = 1:numel(freqs)
    ch(i).name        = sprintf('Brake Balance VCH %dHz', freqs(i));
    ch(i).short_name  = sprintf('BB%dHz', freqs(i));
    ch(i).units       = '%';
    ch(i).value       = 60.01;
    ch(i).sample_rate = freqs(i);
    % Compute dec_places: max precision that keeps int16 in range
    val  = double(ch(i).value);
    mdec = 0;
    for d = 3:-1:0
        if abs(val) * 10^d <= 32767
            mdec = d;
            break;
        end
    end
    ch(i).dec_places = mdec;
    ch(i).mul        = 1;
    ch(i).scale      = 1;
    ch(i).offset     = 0;
    ch(i).datatype   = 3;   % force int16 — ensures dec_places is honoured
end

%% Run
ld_add_channel(SOURCE_FILE, OUTPUT_FILE, ch);

%% Verify via reader
fprintf('\n--- Reader verification ---\n');
out = motec_ld_reader(OUTPUT_FILE);
fn  = fieldnames(out);
for i = 1:numel(fn)
    if contains(lower(fn{i}), 'brake_balance')
        v = out.(fn{i}).data;
        fprintf('%-40s  min=%.2f  max=%.2f  n=%d\n', fn{i}, min(v), max(v), numel(v));
    end
end