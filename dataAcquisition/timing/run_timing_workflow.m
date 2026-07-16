%% =========================================================
%  TIMING WORKFLOW — Master Execution Script
%  =========================================================
%  Full pipeline: PDF scrape → master CSV update → plot
%
%  WORKFLOW:
%    Step 1  — Edit CONFIG section below
%    Step 2  — Run Section A  (scrape new PDFs)
%              Skip if CSVs already extracted — jump straight to Section B
%    Step 3  — Run Section B  (plot)
% =========================================================

clear; clc; close all;
nodeDir = 'C:\Program Files\nodejs\'; 
currentPath = getenv('PATH');
setenv('PATH', [currentPath, ':', nodeDir]);
% Add timing functions to path
addpath(fileparts(mfilename('fullpath')));

%% =========================================================
%  CONFIG  *** EDIT THESE PER SESSION ***
%  =========================================================

% ── Event ────────────────────────────────────────────────
EVENT_CODE   = 'TSV';           % Short event code (must match eventAlias.xlsx)
SESSION      = {'P01'};           % Session alias to filter plots  ('' = all sessions)

% ── PDF folders ──────────────────────────────────────────
% Pit speed PDFs live directly in the event folder
PIT_SPEED_FOLDER  = 'C:/SimEnv/dataAcquisition/timing/timingData/07_TSV/pitLane';

% Top speed PDFs live in a 'top_speed' subfolder
TOP_SPEED_FOLDER  = 'C:/SimEnv/dataAcquisition/timing/timingData/07_TSV/speedTrap';

% ── Which reports to run ──────────────────────────────────
RUN_PIT_SPEED    = false;    % Extract + plot pit lane speed trap
RUN_TOP_SPEED    = true;    % Extract + plot on-track top speed
FORCE_RESCRAPE   = true;   % true = re-parse PDFs even if CSVs already exist

% ── Plot options ──────────────────────────────────────────
SORT_ORDER    = 'none';    % 'none' | 'descend' | 'ascend'  (sort x-axis by mean speed)
Y_LIM_PIT     = [0, 50];   % e.g. [40 80]  — leave [] for auto
Y_LIM_TOP     = [210, 260]; % e.g. [250 320] — leave [] for auto
EXCLUDE_CARS  = {};        % e.g. {'97', '88'} — cars to hide from plot
INCLUDE_CARS  = {};        % e.g. {'1', '97'}  — show only these cars ([] = all)


%% =========================================================
%  SECTION A: SCRAPE PDFs → master CSVs
%  =========================================================
%  Re-running is safe — existing rows for this event+session
%  are replaced, no duplicates are created.

fprintf('\n=== SECTION A: Scraping PDFs ===\n');

if RUN_PIT_SPEED
    if isfolder(PIT_SPEED_FOLDER)
        fprintf('\n--- Pit Speed ---\n');
        T_pit = smp_extract_folder(PIT_SPEED_FOLDER, FORCE_RESCRAPE);
        fprintf('Pit speed rows extracted: %d\n', height(T_pit));
    else
        warning('Pit speed folder not found:\n  %s\nSkipping.', PIT_SPEED_FOLDER);
    end
end

if RUN_TOP_SPEED
    if isfolder(TOP_SPEED_FOLDER)
        fprintf('\n--- Top Speed ---\n');
        T_top = smp_extract_topspeed_folder(TOP_SPEED_FOLDER, FORCE_RESCRAPE);
        fprintf('Top speed rows extracted: %d\n', height(T_top));
    else
        warning('Top speed folder not found:\n  %s\nSkipping.', TOP_SPEED_FOLDER);
    end
end

fprintf('\nSection A complete.\n');


%% =========================================================
%  SECTION B: PLOT
%  =========================================================

fprintf('\n=== SECTION B: Plotting ===\n');

% Build common filter args (drop session filter if empty)
car_filter = {};
if ~isempty(EXCLUDE_CARS), car_filter = [car_filter, 'excludeCars', {EXCLUDE_CARS}]; end
if ~isempty(INCLUDE_CARS), car_filter = [car_filter, 'includeCars', {INCLUDE_CARS}]; end

if isempty(SESSION)
    filter_args_pit = [{'event', EVENT_CODE, 'report', 'pit_speed', ...
                        'sort', SORT_ORDER, 'yLim', Y_LIM_PIT}, car_filter];
    filter_args_top = [{'event', EVENT_CODE, 'report', 'top_speed', ...
                        'sort', 'descend', 'yLim', Y_LIM_TOP}, car_filter];
else
    filter_args_pit = [{'event', EVENT_CODE, 'session', SESSION, 'report', 'pit_speed', ...
                        'sort', SORT_ORDER, 'yLim', Y_LIM_PIT}, car_filter];
    filter_args_top = [{'event', EVENT_CODE, 'session', SESSION, 'report', 'top_speed', ...
                        'sort', 'descend', 'yLim', Y_LIM_TOP}, car_filter];
end

if RUN_PIT_SPEED
    fprintf('\n--- Pit Speed plot ---\n');
    smp_plot_speed_trap(filter_args_pit{:});
end

if RUN_TOP_SPEED
    fprintf('\n--- Top Speed plot ---\n');
    smp_plot_speed_trap(filter_args_top{:});
end

fprintf('\nDone.\n');
