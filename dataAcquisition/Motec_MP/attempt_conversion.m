%% =========================================================
%  RUN_LD_WRITER  —  Example execution script for motec_ld_writer
%
%  Run this script (not motec_ld_writer directly).
%  Re-run it to resume after a checkpoint pause or crash.
% =========================================================
clear; clc;

%% ---- Paths ----------------------------------------------------------
SOURCE_FILE   = 'E:\2026\02_DUP\_Team Data\01_T8R\20260307-243060003.ld';  % *** REPLACE ***
OUTPUT_FILE   = 'E:\2026\02_DUP\_Team Data\01_T8R\20260307-243060003_COPY.ld';  % *** REPLACE ***
PROGRESS_FILE = 'E:\2026\02_DUP\_Team Data\01_T8R\PROGRESS.mat'; % *** REPLACE ***

%% ---- Options --------------------------------------------------------
%  Set FORCE_RESTART = true to wipe saved progress and start from scratch.
%  Leave false to resume from the last checkpoint.
FORCE_RESTART = false;

%% ---- Run ------------------------------------------------------------
motec_ld_writer(SOURCE_FILE, OUTPUT_FILE, PROGRESS_FILE, FORCE_RESTART);