%% RUN_LD_ADD_CHANNEL
clear; clc;

SOURCE_FILE = 'E:\2026\02_DUP\_Team Data\01_T8R\20260307-243060003.ld';
OUTPUT_FILE = 'E:\2026\02_DUP\_Team Data\01_T8R\20260307-243060003_COPY.ld';

%% Define channels — one per available donor frequency + one random
freqs = [1, 2, 5, 10, 20, 25, 50, 100, 333];   % 333 Hz = non-existent donor

ch = struct([]);
for i = 1:numel(freqs)
    ch(i).name        = sprintf('Brake Balance VCH %dHz', freqs(i));
    ch(i).short_name  = sprintf('BB%dHz', freqs(i));
    ch(i).units       = '%';
    ch(i).value       = 60;
    ch(i).sample_rate = freqs(i);
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