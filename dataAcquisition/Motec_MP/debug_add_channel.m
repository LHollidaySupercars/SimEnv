%% debug_add_channel.m
% Troubleshooting script — append a single hardcoded channel to a .ld file.
% No Excel, no donor lookup dependencies.
% Press Run.

clear; clc;

%% =========================================================
%  CONFIG
%% =========================================================

TARGET_FILE = 'E:\2026\T01_QLR\Dash\20260505-156890009.ld';   % clean source — never appended to
OUTPUT_FILE = 'E:\2026\T01_QLR\COM\debug_channel_test.ld';    % fresh output in COM folder

CHANNEL_NAME  = 'Brake Bias VCH';
CHANNEL_VALUE = 33;     % constant value written for full session
CHANNEL_HZ    = 10;     % sample rate
CHANNEL_UNITS = '%';

%% =========================================================
%  SETUP — add channelAdd to path
%% =========================================================

script_dir = fileparts(mfilename('fullpath'));
ch_add_dir = fullfile(script_dir, 'channelAdd');
if exist(ch_add_dir, 'dir') && ~any(strcmp(strsplit(path, pathsep), ch_add_dir))
    addpath(ch_add_dir);
end

%% =========================================================
%  STEP 1: Build channel struct
%% =========================================================

ch.name        = CHANNEL_NAME;
ch.short_name  = CHANNEL_NAME(1:min(end,7));
ch.units       = CHANNEL_UNITS;
ch.value       = CHANNEL_VALUE;   % scalar — ld_add_channel sizes from donor_n
ch.sample_rate = CHANNEL_HZ;

%% =========================================================
%  STEP 2: Append via ld_add_channel
%% =========================================================

out_com_dir = fileparts(OUTPUT_FILE);
if ~isempty(out_com_dir) && ~exist(out_com_dir, 'dir'), mkdir(out_com_dir); end

fprintf('\nAppending to fresh output file...\n');
ld_add_channel(TARGET_FILE, OUTPUT_FILE, ch);

%% =========================================================
%  STEP 3: Verify via reader
%% =========================================================

fprintf('\n--- Reader verification ---\n');
out = motec_ld_reader(OUTPUT_FILE);
fn  = fieldnames(out);
for i = 1:numel(fn)
    if contains(lower(fn{i}), 'brake') || contains(lower(fn{i}), 'bias')
        v = out.(fn{i}).data;
        fprintf('%-40s  min=%.2f  max=%.2f  n=%d\n', fn{i}, min(v), max(v), numel(v));
    end
end
