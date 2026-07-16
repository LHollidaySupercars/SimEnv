% RUN_TIMING_INVESTIGATION.m — Execution script for tail bytes investigation
% Runs debug_record_tail against the single-session QLR Dash file.
% Use this script in the timing investigation chat session.

clear; clc;

fprintf('Running timing investigation on single-session file...\n\n');

ch_add_dir = fileparts(mfilename('fullpath'));
addpath(ch_add_dir);

run(fullfile(ch_add_dir, 'debug_record_tail'));

fprintf('\nDone. Analyze the tail bytes output above.\n');
