% %% ========================================================================
% %  DOE_Experiment.m
% %  Full Factorial DOE — Rear Axle Chassis Pickup Points (Parallel)
% %
% %  Design:
% %    RUF  — POS slots  x  Y sweep  (discrete + continuous)
% %    RUA  — POS slots  x  Y sweep
% %    RLF  — POS slots  x  Y sweep
% %    RLA  — POS slots  x  Y sweep
% %
% %  Parallelisation:
% %    Master splits valid combinations across N_WORKERS MATLAB instances.
% %    Each worker calls DOE_Worker (local function below) on its chunk.
% %    Master waits for done_N.flag files, aggregates, writes to Excel.
% %
% %  Single file — DOE_Worker is a local function at the bottom of this script.
% %  Workers call it via:
% %    matlab -batch "addpath(genpath('<path>')); DOE_Experiment_worker(<id>, '<tmp>')"
% %
% %  Outputs: VCS26_Kinematic_LookUp.xlsx  ->  sheet 'RKin_DB'
% % ========================================================================
% 
% %% ========================================================================
% %  MASTER ENTRY POINT
% %  (workers call DOE_Experiment_worker directly — see bottom of file)
% % ========================================================================
% 
% clear all; close all; clc;
% 
% fprintf('=================================================\n');
% fprintf('  DOE Experiment — Rear Axle Full Factorial\n');
% fprintf('  %s\n', datestr(now, 'HH:MM:SS'));
% fprintf('=================================================\n\n');
% 
% %% -----------------------------------------------------------------------
% %  CONFIGURATION — edit here only
% % -----------------------------------------------------------------------
% 
% % --- General ---
% manufacturer  = 'ford';
% axle          = 'rear';
% outputFile    = 'VCS26_Kinematic_LookUp.xlsx';
% sheetName     = 'RKin_DB';
% overwrite     = true;
% CoGHeight     = 300;       % mm — used for anti geometry %
% 
% % --- Camber shims on upper A-arm ---
% % [5219=1.016mm | 5220=1.600mm | 5221=2.540mm | 5222=5.000mm]
% % 1 = shim active, 0 = not used
% camberShims = [1, 1, 0, 0];
% 
% % --- UBJ upright POS slot (fixed throughout DOE) ---
% UBJ_slots = [3]
% % --- Clevis shim stacks (applied before POS offsets) ---
% % [1mm | 1.5mm | 2mm | 5mm] — 1 = active, 0 = not used
% % Field names are axle-agnostic (UF/UA/LF/LA = Upper Fore/Aft, Lower Fore/Aft)
% shims.UF = [0, 0, 0, 0];   % upper fore
% shims.UA = [0, 0, 0, 0];   % upper aft
% shims.LF = [0, 0, 0, 0];   % lower fore
% shims.LA = [0, 0, 0, 0];   % lower aft
% 
% % --- POS slot selection ---
% % [] = all available slots, or e.g. [1 3 5] to restrict
% RUF_slots = [1];
% RUA_slots = [5];
% RLF_slots = [];
% RLA_slots = [];
% 
% sweep.damperAxial_range = [-5, -2.5, 0, 2.5, 5];  % mm offset from nominal along damper axis
% 
% % --- Y sweep — defined as offset from nominal ---
% % Nominals (from CAD / regulations)
% nominal.RUF.Y = 5;    % mm
% nominal.RUA.Y = 5;    % mm
% nominal.RLF.Y = 10;   % mm
% nominal.RLA.Y = 10;   % mm
% 
% % Sweep ranges (relative to nominal) — independent per connection point
% % Converted to absolute at build time: abs_Y = nominal + range
% sweep.RUF.Y_range = [-5,  0,  8];   % abs: [0,  5, 13] mm
% sweep.RUA.Y_range = [-5,  0,  8];   % abs: [0,  5, 13] mm
% sweep.RLF.Y_range = [-10, -5 , 0, 6, 12];   % abs: [0, 10, 22] mm
% sweep.RLA.Y_range = [-10, -5 , 0, 6, 12];   % abs: [0, 10, 22] mm
% 
% % --- Geometric constraints (absolute Y positions) ---
% % Upper A-arm
% constraints.rear.upper.Y_min     =  0;    % mm  absolute
% constraints.rear.upper.Y_max     = 13;    % mm  absolute
% constraints.rear.upper.Y_delta   = 13;    % mm  max fore-aft Y difference
% constraints.rear.upper.POS_delta = Inf;   % slots — no constraint
% 
% % Lower A-arm
% constraints.rear.lower.Y_min     =  0;    % mm  absolute
% constraints.rear.lower.Y_max     = 22;    % mm  absolute
% constraints.rear.lower.Y_delta   = 22;    % mm  max fore-aft Y difference
% constraints.rear.lower.POS_delta =  Inf;    % slots max between RLF and RLA
% 
% % Front (for reference / future front DOE)
% constraints.front.upper.Y_min     =  0;
% constraints.front.upper.Y_max     = 10;
% constraints.front.upper.Y_delta   =  4;
% constraints.front.upper.POS_delta = Inf;
% 
% constraints.front.lower.Y_min     =  0;
% constraints.front.lower.Y_max     = 20;
% constraints.front.lower.Y_delta   =  4;
% constraints.front.lower.POS_delta =  2;
% 
% % --- Parallel options ---
% MODE              = 'serial';  % 'serial' = run inline in this MATLAB session (debug)
%                                  % 'parallel' = spawn N_WORKERS separate MATLAB instances
% N_WORKERS         = 2;
% KEEP_WORKERS_OPEN = false;   % true = worker windows stay open (debug)
% TMP_DIR           = '';      % '' = auto -> <pwd>/_tmp_doe
% 
% %% -----------------------------------------------------------------------
% %  BUILD DESIGN MATRIX
% % -----------------------------------------------------------------------
% 
% fprintf('[0] Loading base CAD parameters...\n');
% GEN3_KinematicParameters;
% 
% % Discover POS slots
% clevisFields = fieldnames(vehicle.(manufacturer).kinematics.(axle).clevis);
% allPosSlots  = clevisFields(startsWith(clevisFields, 'POS'));
% allClevisPosSlots = clevisFields(startsWith(clevisFields, 'POS'));
% allClevisPosSlots = allPosSlots;
% uprightFields = fieldnames(vehicle.(manufacturer).kinematics.(axle).upperAArm);
% ubjFields = uprightFields(startsWith(uprightFields, 'UBJ_UPRIGHT_POS'));
% allUbjSlots = 1:length(ubjFields);  % UBJ uses 1-5 indexing
% filterSlots  = @(req) iif(isempty(req), 1:length(allPosSlots), req);
% ubjIdxs = iif(isempty(UBJ_slots), 1:length(allUbjSlots), UBJ_slots);
% rufIdxs = filterSlots(RUF_slots);
% ruaIdxs = filterSlots(RUA_slots);
% rlfIdxs = filterSlots(RLF_slots);
% rlaIdxs = filterSlots(RLA_slots);
% 
% % Convert Y ranges to absolute — independent per point
% rufY_abs = nominal.RUF.Y + sweep.RUF.Y_range;
% ruaY_abs = nominal.RUA.Y + sweep.RUA.Y_range;
% rlfY_abs = nominal.RLF.Y + sweep.RLF.Y_range;
% rlaY_abs = nominal.RLA.Y + sweep.RLA.Y_range;
% 
% nRUF_Y = length(rufY_abs);
% nRUA_Y = length(ruaY_abs);
% nRLF_Y = length(rlfY_abs);
% nRLA_Y = length(rlaY_abs);
% 
% fprintf('    POS slots available: %s\n', strjoin(allPosSlots, ', '));
% fprintf('    RUF Y (abs mm): %s\n', num2str(rufY_abs));
% fprintf('    RUA Y (abs mm): %s\n', num2str(ruaY_abs));
% fprintf('    RLF Y (abs mm): %s\n', num2str(rlfY_abs));
% fprintf('    RLA Y (abs mm): %s\n', num2str(rlaY_abs));
% 
% damperAxial_offsets = sweep.damperAxial_range;
% nDamperAxial = length(damperAxial_offsets);
% nUBJ = length(ubjIdxs);
% 
% % Full factorial
% % Columns: [rufPOS, rufYIdx, ruaPOS, ruaYIdx, rlfPOS, rlfYIdx, rlaPOS, rlaYIdx]
% [g1,g2,g3,g4,g5,g6,g7,g8] = ndgrid(rufIdxs, 1:nRUF_Y, ...
%                                      ruaIdxs, 1:nRUA_Y, ...
%                                      rlfIdxs, 1:nRLF_Y, ...
%                                      rlaIdxs, 1:nRLA_Y);
% designMatrix = [g1(:),g2(:),g3(:),g4(:),g5(:),g6(:),g7(:),g8(:)];
% nTotal       = size(designMatrix, 1);
% 
% fprintf('    Raw combinations:    %d\n', nTotal);
% 
% % -----------------------------------------------------------------------
% %  APPLY GEOMETRIC CONSTRAINTS
% % -----------------------------------------------------------------------
% 
% fprintf('[1] Applying geometric constraints...\n');
% 
% con   = constraints.(axle);
% keep  = true(nTotal, 1);
% 
% for i = 1:nTotal
%     rufPOS = designMatrix(i,1);
%     rufY   = rufY_abs(designMatrix(i,2));
%     ruaPOS = designMatrix(i,3);
%     ruaY   = ruaY_abs(designMatrix(i,4));
%     rlfPOS = designMatrix(i,5);
%     rlfY   = rlfY_abs(designMatrix(i,6));
%     rlaPOS = designMatrix(i,7);
%     rlaY   = rlaY_abs(designMatrix(i,8));
% 
%     % Upper absolute bounds
%     if rufY < con.upper.Y_min || rufY > con.upper.Y_max; keep(i)=false; continue; end
%     if ruaY < con.upper.Y_min || ruaY > con.upper.Y_max; keep(i)=false; continue; end
%     % Upper fore-aft delta
%     if abs(rufY - ruaY) > con.upper.Y_delta; keep(i)=false; continue; end
%     % Upper POS delta
%     if abs(rufPOS - ruaPOS) > con.upper.POS_delta; keep(i)=false; continue; end
% 
%     % Lower absolute bounds
%     if rlfY < con.lower.Y_min || rlfY > con.lower.Y_max; keep(i)=false; continue; end
%     if rlaY < con.lower.Y_min || rlaY > con.lower.Y_max; keep(i)=false; continue; end
%     % Lower fore-aft delta
%     if abs(rlfY - rlaY) > con.lower.Y_delta; keep(i)=false; continue; end
%     % Lower POS delta
%     if abs(rlfPOS - rlaPOS) > con.lower.POS_delta; keep(i)=false; continue; end
% end
% 
% designMatrix = designMatrix(keep, :);
% nRuns        = size(designMatrix, 1);
% fprintf('    Removed %d illegal — %d valid combinations remain\n\n', ...
%         nTotal - nRuns, nRuns);
% 
% %% -----------------------------------------------------------------------
% %  CHECK EXISTING DATABASE
% % -----------------------------------------------------------------------
% 
% varNames = {'RUF_POS', 'RUF_Y_mm', 'RUA_POS', 'RUA_Y_mm', ...
%             'RLF_POS', 'RLF_Y_mm', 'RLA_POS', 'RLA_Y_mm', ...
%             'Camber_deg', 'CamberGain_degPerMm', ...
%             'Toe_deg',    'ToeGain_degPerMm', ...
%             'RC_Height_mm', 'RC_Gain_mmPerMm', ...
%             'Anti_pct', 'MotionRatio'};
% 
% existingCombos = {};
% startRow       = 2;
% 
% if exist(outputFile, 'file')
%     try
%         existingTable = readcell(outputFile, 'Sheet', sheetName);
%         if size(existingTable, 1) >= 2
%             for r = 2:size(existingTable, 1)
%                 key = buildKey(existingTable{r,1}, existingTable{r,2}, ...
%                                existingTable{r,3}, existingTable{r,4}, ...
%                                existingTable{r,5}, existingTable{r,6}, ...
%                                existingTable{r,7}, existingTable{r,8});
%                 existingCombos{end+1} = key;
%             end
%             startRow = size(existingTable, 1) + 1;
%             fprintf('[DB] %d existing rows found.\n', length(existingCombos));
%         end
%     catch
%         fprintf('[DB] Sheet %s not found — creating fresh.\n', sheetName);
%     end
% end
% 
% % Filter already-done combinations
% if ~overwrite && ~isempty(existingCombos)
%     keep = true(nRuns, 1);
%     for i = 1:nRuns
%         key = buildKey( ...
%             allPosSlots{designMatrix(i,1)}, rufY_abs(designMatrix(i,2)), ...
%             allPosSlots{designMatrix(i,3)}, ruaY_abs(designMatrix(i,4)), ...
%             allPosSlots{designMatrix(i,5)}, rlfY_abs(designMatrix(i,6)), ...
%             allPosSlots{designMatrix(i,7)}, rlaY_abs(designMatrix(i,8)));
%         if any(strcmp(existingCombos, key)); keep(i) = false; end
%     end
%     nSkip        = sum(~keep);
%     designMatrix = designMatrix(keep, :);
%     nRuns        = size(designMatrix, 1);
%     fprintf('[DB] Skipping %d existing — %d remain.\n\n', nSkip, nRuns);
% end
% 
% if nRuns == 0
%     fprintf('Nothing to run — all valid combinations already in database.\n');
%     return;
% end
% 
% %% -----------------------------------------------------------------------
% %  SETUP TMP DIRECTORY + SAVE SHARED CONFIG
% % -----------------------------------------------------------------------
% 
% if isempty(TMP_DIR)
%     TMP_DIR = fullfile(pwd, '_tmp_doe');
% end
% if ~exist(TMP_DIR, 'dir'), mkdir(TMP_DIR); end
% delete(fullfile(TMP_DIR, 'chunk_*.mat'));
% delete(fullfile(TMP_DIR, 'results_*.mat'));
% delete(fullfile(TMP_DIR, 'done_*.flag'));
% delete(fullfile(TMP_DIR, 'worker_cfg.mat'));
% 
% doeCfg.manufacturer  = manufacturer;
% doeCfg.axle          = axle;
% doeCfg.CoGHeight     = CoGHeight;
% doeCfg.camberShims   = camberShims;
% doeCfg.UBJ_POS       = UBJ_POS;
% doeCfg.shims         = shims;
% doeCfg.allPosSlots   = allPosSlots;
% doeCfg.allClevisPosSlots = allClevisPosSlots;
% doeCfg.allUbjSlots   = allUbjSlots
% doeCfg.rufY_abs      = rufY_abs;
% doeCfg.ruaY_abs      = ruaY_abs;
% doeCfg.rlfY_abs      = rlfY_abs;
% doeCfg.rlaY_abs      = rlaY_abs;
% doeCfg.varNames      = varNames;
% doeCfg.constraints   = constraints; %#ok<NASGU>
% 
% save(fullfile(TMP_DIR, 'worker_cfg.mat'), 'doeCfg');
% 
% %% -----------------------------------------------------------------------
% %  SERIAL  vs  PARALLEL
% % -----------------------------------------------------------------------
% 
% if strcmp(MODE, 'serial')
% 
%     % ---- SERIAL — call DOE_Worker directly in this MATLAB session ----
%     fprintf('[2] SERIAL mode — running inline...\n\n');
% 
%     workerChunk = designMatrix; %#ok<NASGU>
%     save(fullfile(TMP_DIR, 'chunk_1.mat'), 'workerChunk');
% 
%     DOE_Worker(1, TMP_DIR);
% 
%     R          = load(fullfile(TMP_DIR, 'results_1.mat'));
%     allResults = R.results;
% 
% else
% 
%     % ---- PARALLEL — spawn N_WORKERS separate MATLAB instances ----
%     nWorkers  = min(N_WORKERS, nRuns);
%     chunkSize = ceil(nRuns / nWorkers);
% 
%     fprintf('[2] Splitting %d runs across %d workers...\n', nRuns, nWorkers);
%     for w = 1:nWorkers
%         iStart = (w-1)*chunkSize + 1;
%         iEnd   = min(w*chunkSize, nRuns);
%         workerChunk = designMatrix(iStart:iEnd, :); %#ok<NASGU>
%         save(fullfile(TMP_DIR, sprintf('chunk_%d.mat', w)), 'workerChunk');
%         fprintf('    Worker %d: %d combinations\n', w, iEnd - iStart + 1);
%     end
% 
%     matlabExe   = fullfile(matlabroot, 'bin', 'matlab.exe');
%     projectPath = pwd;
%     winMode     = 'cmd /c';
%     if KEEP_WORKERS_OPEN; winMode = 'cmd /k'; end
% 
%     fprintf('\n[3] Launching %d workers...\n', nWorkers);
%     for w = 1:nWorkers
%         cmd = sprintf( ...
%             'start "DOE Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); DOE_Worker(%d, ''%s'')"" ', ...
%             w, winMode, matlabExe, ...
%             strrep(projectPath, '\', '\\'), ...
%             w, strrep(TMP_DIR, '\', '\\'));
%         system(cmd);
%         fprintf('    Worker %d launched\n', w);
%         pause(2.0);
%     end
% 
%     fprintf('\n[4] Waiting for workers (polling every 30s)...\n\n');
%     while true
%         nDone = sum(arrayfun(@(w) exist(fullfile(TMP_DIR, sprintf('done_%d.flag', w)), 'file'), 1:nWorkers));
%         fprintf('    %s — %d / %d workers done\n', datestr(now,'HH:MM:SS'), nDone, nWorkers);
%         if nDone == nWorkers; break; end
%         pause(30);
%     end
%     fprintf('\n    All workers complete.\n\n');
% 
%     fprintf('[5] Aggregating results...\n');
%     allResults = {};
%     for w = 1:nWorkers
%         rf = fullfile(TMP_DIR, sprintf('results_%d.mat', w));
%         if ~exist(rf, 'file')
%             fprintf('    [WARN] Worker %d results missing\n', w);
%             continue;
%         end
%         R = load(rf);
%         allResults = [allResults; R.results];
%         fprintf('    Worker %d: %d rows\n', w, size(R.results, 1));
%     end
% 
% end
% 
% %% -----------------------------------------------------------------------
% %  WRITE TO EXCEL
% % -----------------------------------------------------------------------
% 
% fprintf('\n[6] Writing to %s -> %s...\n', outputFile, sheetName);
% 
% if startRow == 2
%     writecell(varNames, outputFile, 'Sheet', sheetName, 'Range', 'A1');
% end
% 
% if ~isempty(allResults)
%     writecell(allResults, outputFile, 'Sheet', sheetName, ...
%               'Range', sprintf('A%d', startRow));
% end
% 
% try; formatSheet(outputFile, sheetName, startRow-2+size(allResults,1), length(varNames)); catch; end
% 
% fprintf('\n=================================================\n');
% fprintf('  DOE Complete\n');
% fprintf('  Valid combinations: %d\n', nRuns);
% fprintf('  Results written:    %d\n', size(allResults, 1));
% fprintf('  Output: %s -> %s\n', outputFile, sheetName);
% fprintf('  %s\n', datestr(now, 'HH:MM:SS'));
% fprintf('=================================================\n\n');
% 
% 
% %% ========================================================================
% %  LOCAL FUNCTIONS
% % ========================================================================
% 
% function key = buildKey(rufSlot, rufY, ruaSlot, ruaY, rlfSlot, rlfY, rlaSlot, rlaY)
% % BUILDKEY  Unique string identifier for one DOE combination.
%     key = sprintf('%s|%.1f|%s|%.1f|%s|%.1f|%s|%.1f', ...
%                   rufSlot, rufY, ruaSlot, ruaY, rlfSlot, rlfY, rlaSlot, rlaY);
% end
% 
% function out = iif(cond, a, b)
%     if cond; out = a; else; out = b; end
% end
% 
% function formatSheet(outFile, sheetName, nRows, nCols)
%     if ~ispc; return; end
%     xl = actxserver('Excel.Application'); xl.Visible = false;
%     try
%         wb = xl.Workbooks.Open(fullfile(pwd, outFile));
%         ws = wb.Sheets.Item(sheetName);
%         for c = 1:nCols
%             cell = ws.Range(sprintf('%s1', colLetter(c)));
%             cell.Font.Bold = true; cell.Font.Color = rgb2xl([1 1 1]);
%             cell.Interior.Color = rgb2xl([0.13 0.20 0.40]);
%             cell.HorizontalAlignment = -4108;
%         end
%         for r = 2:nRows+1
%             rng = ws.Range(sprintf('A%d:%s%d', r, colLetter(nCols), r));
%             rng.Interior.Color = rgb2xl(iif(mod(r,2)==0, [0.93 0.95 0.98], [1 1 1]));
%         end
%         ws.Range(sprintf('I2:%s%d', colLetter(nCols), nRows+1)).NumberFormat = '0.0000';
%         ws.Columns.AutoFit();
%         ws.Range('A2').Select(); xl.ActiveWindow.FreezePanes = true;
%         wb.Save(); wb.Close();
%     catch; try; wb.Close(false); catch; end
%     end
%     xl.Quit(); xl.delete();
% end
% 
% function letter = colLetter(n)
%     letter = '';
%     while n > 0
%         r = mod(n-1,26); letter = [char(65+r), letter]; n = floor((n-1)/26);
%     end
% end
% 
% function xlc = rgb2xl(rgb)
%     r=round(rgb(1)*255); g=round(rgb(2)*255); b=round(rgb(3)*255);
%     xlc = r + g*256 + b*65536;
% end

% ========================================================================
%  KinematicSweepFront.m
%  Full Factorial DOE — Front Axle Chassis Pickup Points (Serial / Parallel)
%
%  Design:
%    FUF  — POS slots  x  Y sweep  (discrete + continuous)
%    FUA  — POS slots  x  Y sweep
%    FLF  — POS slots  x  Y sweep
%    FLA  — POS slots  x  Y sweep
%    UBJ  — upright POS slot sweep (5 discrete Z positions)
%    Damper chassis pickup Z — RH adjuster sweep (continuous offset)
%
%  Parallelisation:
%    Master splits valid combinations across N_WORKERS MATLAB instances.
%    Each worker calls DOE_Worker (local function below) on its chunk.
%    Master waits for done_N.flag files, aggregates, writes to Excel.
%
%  Single file — DOE_Worker is a local function at the bottom of this script.
%  Workers call it via:
%    matlab -batch "addpath(genpath('<path>')); DOE_Worker(<id>, '<tmp>')"
%
%  Outputs: VCS26_Kinematic_LookUp.xlsx  ->  sheet 'FKin_DB'
% ========================================================================

%% ========================================================================
%  MASTER ENTRY POINT
%  (workers call DOE_Experiment_worker directly — see bottom of file)
% ========================================================================

clear all; close all; clc;

fprintf('=================================================\n');
fprintf('  DOE Experiment — Front Axle Full Factorial\n');
fprintf('  %s\n', datestr(now, 'HH:MM:SS'));
fprintf('=================================================\n\n');

%% -----------------------------------------------------------------------
%  CONFIGURATION — edit here only
% -----------------------------------------------------------------------

% --- General ---
manufacturer  = 'ford';
axle          = 'rear';
outputFile    = 'VCS26_Kinematic_LookUp.xlsx';
sheetName     = 'RKin_DB';
overwrite     = true;
CoGHeight     = 273;       % mm — used for anti geometry %

% --- Camber shims on upper A-arm ---
% [5219=1.016mm | 5220=1.600mm | 5221=2.540mm | 5222=5.000mm]
% 1 = shim active, 0 = not used
camberShims = [1, 1, 0, 0];

% --- UBJ upright POS slot sweep ---
% [] = all available slots (5 total: ±15mm from nominal), or e.g. [2 3 4] to restrict
UBJ_slots = [];  % empty = sweep all 5 POS slots

% --- Damper chassis pickup sweep (RH adjuster) ---
% Offset applied along the damper axial direction (chassis pickup → rocker pickup)
% Positive = chassis pickup moves away from rocker = effectively longer damper
sweep.damperAxial_range = [0];  % mm offset from nominal along damper axis

% --- Clevis shim stacks (applied before POS offsets) ---
% [1mm | 1.5mm | 2mm | 5mm] — 1 = active, 0 = not used
% Field names are axle-agnostic (UF/UA/LF/LA = Upper Fore/Aft, Lower Fore/Aft)
shims.UF = [0, 0, 0, 0];   % upper fore
shims.UA = [0, 0, 0, 0];   % upper aft
shims.LF = [0, 0, 0, 0];   % lower fore
shims.LA = [0, 0, 0, 0];   % lower aft

% --- POS slot selection ---
% [] = all available slots, or e.g. [1 3 5] to restrict
RUF_slots = [3];
RUA_slots = [1];
RLF_slots = [1];
RLA_slots = [1];

% --- Y sweep — defined as offset from nominal ---
% Nominals (from CAD / regulations)
nominal.RUF.Y = 5;    % mm
nominal.RUA.Y = 5;    % mm
nominal.RLF.Y = 10;   % mm
nominal.RLA.Y = 10;   % mm

% Sweep ranges (relative to nominal) — independent per connection point
% Converted to absolute at build time: abs_Y = nominal + range
sweep.RUF.Y_range = [5];   % abs: [0,  5, 13] mm
sweep.RUA.Y_range = [-3];   % abs: [0,  5, 13] mm
sweep.RLF.Y_range = [-2];   % abs: [0, 10, 22] mm
sweep.RLA.Y_range = [-6];   % abs: [0, 10, 22] mm

% --- Geometric constraints (absolute Y positions) ---
% Upper A-arm
constraints.rear.upper.Y_min     =  0;    % mm  absolute
constraints.rear.upper.Y_max     = 13;    % mm  absolute
constraints.rear.upper.Y_delta   = 13;    % mm  max fore-aft Y difference
constraints.rear.upper.POS_delta = Inf;   % slots — no constraint

% Lower A-arm
constraints.rear.lower.Y_min     =  0;    % mm  absolute
constraints.rear.lower.Y_max     = 22;    % mm  absolute
constraints.rear.lower.Y_delta   = 22;    % mm  max fore-aft Y difference
constraints.rear.lower.POS_delta =  Inf;    % slots max between RLF and RLA

% Front (for reference / future front DOE)
constraints.front.upper.Y_min     =  0;
constraints.front.upper.Y_max     = 10;
constraints.front.upper.Y_delta   =  4;
constraints.front.upper.POS_delta = Inf;

constraints.front.lower.Y_min     =  0;
constraints.front.lower.Y_max     = 20;
constraints.front.lower.Y_delta   =  4;
constraints.front.lower.POS_delta =  2;

% --- Parallel options ---
MODE              = 'serial';  % 'serial' = run inline in this MATLAB session (debug)
                                 % 'parallel' = spawn N_WORKERS separate MATLAB instances
N_WORKERS         = 4;
KEEP_WORKERS_OPEN = false;   % true = worker windows stay open (debug)
TMP_DIR           = '';      % '' = auto -> <pwd>/_tmp_doe

%% -----------------------------------------------------------------------
%  BUILD DESIGN MATRIX
% -----------------------------------------------------------------------

fprintf('[0] Loading base CAD parameters...\n');
GEN3_KinematicParameters;

% Discover POS slots for clevis and UBJ
clevisFields = fieldnames(vehicle.(manufacturer).kinematics.(axle).clevis);
allClevisPosSlots = clevisFields(startsWith(clevisFields, 'POS'));

uprightFields = fieldnames(vehicle.(manufacturer).kinematics.(axle).upperAArm);
ubjFields = uprightFields(startsWith(uprightFields, 'UBJ_UPRIGHT_POS'));
allUbjSlots = 1:length(ubjFields);  % UBJ uses 1-5 indexing

filterSlots  = @(req) iif(isempty(req), 1:length(allClevisPosSlots), req);
fufIdxs = filterSlots(RUF_slots);
fuaIdxs = filterSlots(RUA_slots);
flfIdxs = filterSlots(RLF_slots);
flaIdxs = filterSlots(RLA_slots);

ubjIdxs = iif(isempty(UBJ_slots), 1:length(allUbjSlots), UBJ_slots);

% Convert Y ranges to absolute — independent per point
rufY_abs = nominal.RUF.Y + sweep.RUF.Y_range;
ruaY_abs = nominal.RUA.Y + sweep.RUA.Y_range;
rlfY_abs = nominal.RLF.Y + sweep.RLF.Y_range;
rlaY_abs = nominal.RLA.Y + sweep.RLA.Y_range;

nRUF_Y = length(rufY_abs);
nRUA_Y = length(ruaY_abs);
nRLF_Y = length(rlfY_abs);
nRLA_Y = length(rlaY_abs);

% Damper axial offsets (0 = nominal, units: mm along damper axis)
damperAxial_offsets = sweep.damperAxial_range;
nDamperAxial = length(damperAxial_offsets);
nUBJ = length(ubjIdxs);

fprintf('    Clevis POS slots: %s\n', strjoin(allClevisPosSlots, ', '));
fprintf('    UBJ POS slots (sweep): [%s]\n', num2str(ubjIdxs));
fprintf('    FUF Y (abs mm): %s\n', num2str(rufY_abs));
fprintf('    FUA Y (abs mm): %s\n', num2str(ruaY_abs));
fprintf('    FLF Y (abs mm): %s\n', num2str(rlfY_abs));
fprintf('    FLA Y (abs mm): %s\n', num2str(rlaY_abs));
fprintf('    Damper axial offsets (mm): %s\n', num2str(damperAxial_offsets));

% Full factorial
% Columns: [fufPOS, fufYIdx, fuaPOS, fuaYIdx, flfPOS, flfYIdx, flaPOS, flaYIdx, ubjPOS_idx, damperAxial_idx]
[g1,g2,g3,g4,g5,g6,g7,g8,g9,g10] = ndgrid(  fufIdxs, 1:nRUF_Y, ...
                                            fuaIdxs, 1:nRUA_Y, ...
                                            flfIdxs, 1:nRLF_Y, ...
                                            flaIdxs, 1:nRLA_Y, ...
                                            ubjIdxs, 1:nDamperAxial);
designMatrix = [g1(:),g2(:),g3(:),g4(:),g5(:),g6(:),g7(:),g8(:),g9(:),g10(:)];
nTotal       = size(designMatrix, 1);

fprintf('    Raw combinations:    %d\n', nTotal);

% -----------------------------------------------------------------------
%  APPLY GEOMETRIC CONSTRAINTS
% -----------------------------------------------------------------------

fprintf('[1] Applying geometric constraints...\n');

con   = constraints.(axle);
keep  = true(nTotal, 1);

for i = 1:nTotal
    rufPOS = designMatrix(i,1);
    rufY   = rufY_abs(designMatrix(i,2));
    ruaPOS = designMatrix(i,3);
    ruaY   = ruaY_abs(designMatrix(i,4));
    rlfPOS = designMatrix(i,5);
    rlfY   = rlfY_abs(designMatrix(i,6));
    rlaPOS = designMatrix(i,7);
    rlaY   = rlaY_abs(designMatrix(i,8));
    ubjPOS       = designMatrix(i,9);
    damperAxial  = damperAxial_offsets(designMatrix(i,10));

    % Upper absolute bounds
    if rufY < con.upper.Y_min || rufY > con.upper.Y_max; keep(i)=false; continue; end
    if ruaY < con.upper.Y_min || ruaY > con.upper.Y_max; keep(i)=false; continue; end
    % Upper fore-aft delta
    if abs(rufY - ruaY) > con.upper.Y_delta; keep(i)=false; continue; end
    % Upper POS delta
    if abs(rufPOS - ruaPOS) > con.upper.POS_delta; keep(i)=false; continue; end

    % Lower absolute bounds
    if rlfY < con.lower.Y_min || rlfY > con.lower.Y_max; keep(i)=false; continue; end
    if rlaY < con.lower.Y_min || rlaY > con.lower.Y_max; keep(i)=false; continue; end
    % Lower fore-aft delta
    if abs(rlfY - rlaY) > con.lower.Y_delta; keep(i)=false; continue; end
    % Lower POS delta
    if abs(rlfPOS - rlaPOS) > con.lower.POS_delta; keep(i)=false; continue; end
end

designMatrix = designMatrix(keep, :);
nRuns        = size(designMatrix, 1);
fprintf('    Removed %d illegal — %d valid combinations remain\n\n', ...
        nTotal - nRuns, nRuns);

%% -----------------------------------------------------------------------
%  CHECK EXISTING DATABASE
% -----------------------------------------------------------------------

varNames = {'RUF_POS', 'RUF_Y_mm', 'RUA_POS', 'RUA_Y_mm', ...
            'RLF_POS', 'RLF_Y_mm', 'RLA_POS', 'RLA_Y_mm', ...
            'UBJ_POS', 'DamperAxial_mm', ...
            'Camber_deg', 'CamberGain_degPerMm', ...
            'Toe_deg',    'ToeGain_degPerMm', ...
            'RC_Height_mm', 'RC_Gain_mmPerMm', ...
            'Anti_pct', 'MotionRatio'};

existingCombos = {};
startRow       = 2;

if exist(outputFile, 'file')
    try
        existingTable = readcell(outputFile, 'Sheet', sheetName);
        if size(existingTable, 1) >= 2
            for r = 2:size(existingTable, 1)
                key = buildKey(existingTable{r,1}, existingTable{r,2}, ...
                               existingTable{r,3}, existingTable{r,4}, ...
                               existingTable{r,5}, existingTable{r,6}, ...
                               existingTable{r,7}, existingTable{r,8}, ...
                               existingTable{r,9}, existingTable{r,10}); %#ok<AGROW>
                existingCombos{end+1} = key;
            end
            startRow = size(existingTable, 1) + 1;
            fprintf('[DB] %d existing rows found.\n', length(existingCombos));
        end
    catch
        fprintf('[DB] Sheet %s not found — creating fresh.\n', sheetName);
    end
end

% Filter already-done combinations
if ~overwrite && ~isempty(existingCombos)
    keep = true(nRuns, 1);
    for i = 1:nRuns
        key = buildKey( ...
            allClevisPosSlots{designMatrix(i,1)}, rufY_abs(designMatrix(i,2)), ...
            allClevisPosSlots{designMatrix(i,3)}, ruaY_abs(designMatrix(i,4)), ...
            allClevisPosSlots{designMatrix(i,5)}, rlfY_abs(designMatrix(i,6)), ...
            allClevisPosSlots{designMatrix(i,7)}, flaY_abs(designMatrix(i,8)), ...
            designMatrix(i,9), damperAxial_offsets(designMatrix(i,10)));
        if any(strcmp(existingCombos, key)); keep(i) = false; end
    end
    nSkip        = sum(~keep);
    designMatrix = designMatrix(keep, :);
    nRuns        = size(designMatrix, 1);
    fprintf('[DB] Skipping %d existing — %d remain.\n\n', nSkip, nRuns);
end

if nRuns == 0
    fprintf('Nothing to run — all valid combinations already in database.\n');
    return;
end

%% -----------------------------------------------------------------------
%  SETUP TMP DIRECTORY + SAVE SHARED CONFIG
% -----------------------------------------------------------------------

if isempty(TMP_DIR)
    TMP_DIR = fullfile(pwd, '_tmp_doe');
end
if ~exist(TMP_DIR, 'dir'), mkdir(TMP_DIR); end
delete(fullfile(TMP_DIR, 'chunk_*.mat'));
delete(fullfile(TMP_DIR, 'results_*.mat'));
delete(fullfile(TMP_DIR, 'done_*.flag'));
delete(fullfile(TMP_DIR, 'worker_cfg.mat'));

doeCfg.manufacturer         = manufacturer;
doeCfg.axle                 = axle;
doeCfg.CoGHeight            = CoGHeight;
doeCfg.camberShims          = camberShims;
doeCfg.shims                = shims;
doeCfg.allClevisPosSlots    = allClevisPosSlots;
doeCfg.allUbjSlots          = allUbjSlots;
doeCfg.rufY_abs             = rufY_abs;
doeCfg.ruaY_abs             = ruaY_abs;
doeCfg.rlfY_abs             = rlfY_abs;
doeCfg.rlaY_abs             = rlaY_abs;
doeCfg.damperAxial_offsets  = damperAxial_offsets;
doeCfg.varNames             = varNames;
doeCfg.constraints          = constraints; %#ok<NASGU>

save(fullfile(TMP_DIR, 'worker_cfg.mat'), 'doeCfg');

%% -----------------------------------------------------------------------
%  SERIAL  vs  PARALLEL
% -----------------------------------------------------------------------

if strcmp(MODE, 'serial')

    % ---- SERIAL — call DOE_Worker directly in this MATLAB session ----
    fprintf('[2] SERIAL mode — running inline...\n\n');

    workerChunk = designMatrix; %#ok<NASGU>
    save(fullfile(TMP_DIR, 'chunk_1.mat'), 'workerChunk');

    DOE_Worker(1, TMP_DIR);

    R          = load(fullfile(TMP_DIR, 'results_1.mat'));
    allResults = R.results;

else

    % ---- PARALLEL — spawn N_WORKERS separate MATLAB instances ----
    nWorkers  = min(N_WORKERS, nRuns);
    chunkSize = ceil(nRuns / nWorkers);

    fprintf('[2] Splitting %d runs across %d workers (Front Axle)...\n', nRuns, nWorkers);
    for w = 1:nWorkers
        iStart = (w-1)*chunkSize + 1;
        iEnd   = min(w*chunkSize, nRuns);
        workerChunk = designMatrix(iStart:iEnd, :); %#ok<NASGU>
        save(fullfile(TMP_DIR, sprintf('chunk_%d.mat', w)), 'workerChunk');
        fprintf('    Worker %d: %d combinations\n', w, iEnd - iStart + 1);
    end

    matlabExe   = fullfile(matlabroot, 'bin', 'matlab.exe');
    projectPath = pwd;
    winMode     = 'cmd /c';
    if KEEP_WORKERS_OPEN; winMode = 'cmd /k'; end

    fprintf('\n[3] Launching %d workers...\n', nWorkers);
    for w = 1:nWorkers
        cmd = sprintf( ...
            'start "DOE Worker %d" %s ""%s" -batch "addpath(genpath(''%s'')); DOE_Worker(%d, ''%s'')"" ', ...
            w, winMode, matlabExe, ...
            strrep(projectPath, '\', '\\'), ...
            w, strrep(TMP_DIR, '\', '\\'));
        system(cmd);
        fprintf('    Worker %d launched\n', w);
        pause(2.0);
    end

    fprintf('\n[4] Waiting for workers (polling every 30s)...\n\n');
    while true
        nDone = sum(arrayfun(@(w) exist(fullfile(TMP_DIR, sprintf('done_%d.flag', w)), 'file'), 1:nWorkers));
        fprintf('    %s — %d / %d workers done\n', datestr(now,'HH:MM:SS'), nDone, nWorkers);
        if nDone == nWorkers; break; end
        pause(30);
    end
    fprintf('\n    All workers complete.\n\n');

    fprintf('[5] Aggregating results...\n');
    allResults = {};
    for w = 1:nWorkers
        rf = fullfile(TMP_DIR, sprintf('results_%d.mat', w));
        if ~exist(rf, 'file')
            fprintf('    [WARN] Worker %d results missing\n', w);
            continue;
        end
        R = load(rf);
        allResults = [allResults; R.results];
        fprintf('    Worker %d: %d rows\n', w, size(R.results, 1));
    end

end

%% -----------------------------------------------------------------------
%  WRITE TO EXCEL
% -----------------------------------------------------------------------

fprintf('\n[6] Writing to %s -> %s...\n', outputFile, sheetName);

if startRow == 2
    writecell(varNames, outputFile, 'Sheet', sheetName, 'Range', 'A1');
end

if ~isempty(allResults)
    writecell(allResults, outputFile, 'Sheet', sheetName, ...
              'Range', sprintf('A%d', startRow));
end

try; formatSheet(outputFile, sheetName, startRow-2+size(allResults,1), length(varNames)); catch; end

fprintf('\n=================================================\n');
fprintf('  DOE Complete\n');
fprintf('  Valid combinations: %d\n', nRuns);
fprintf('  Results written:    %d\n', size(allResults, 1));
fprintf('  Output: %s -> %s\n', outputFile, sheetName);
fprintf('  %s\n', datestr(now, 'HH:MM:SS'));
fprintf('=================================================\n\n');


%% ========================================================================
%  LOCAL FUNCTIONS
% ========================================================================

function key = buildKey(fufSlot, fufY, fuaSlot, fuaY, flfSlot, flfY, flaSlot, flaY, ubjPos, damperAxial)
% BUILDKEY  Unique string identifier for one DOE combination.
    key = sprintf('%s|%.1f|%s|%.1f|%s|%.1f|%s|%.1f|%d|%.1f', ...
                  fufSlot, fufY, fuaSlot, fuaY, flfSlot, flfY, flaSlot, flaY, ubjPos, damperAxial);
end

function out = iif(cond, a, b)
    if cond; out = a; else; out = b; end
end

function formatSheet(outFile, sheetName, nRows, nCols)
    if ~ispc; return; end
    xl = actxserver('Excel.Application'); xl.Visible = false;
    try
        wb = xl.Workbooks.Open(fullfile(pwd, outFile));
        ws = wb.Sheets.Item(sheetName);
        for c = 1:nCols
            cell = ws.Range(sprintf('%s1', colLetter(c)));
            cell.Font.Bold = true; cell.Font.Color = rgb2xl([1 1 1]);
            cell.Interior.Color = rgb2xl([0.13 0.20 0.40]);
            cell.HorizontalAlignment = -4108;
        end
        for r = 2:nRows+1
            rng = ws.Range(sprintf('A%d:%s%d', r, colLetter(nCols), r));
            rng.Interior.Color = rgb2xl(iif(mod(r,2)==0, [0.93 0.95 0.98], [1 1 1]));
        end
        ws.Range(sprintf('I2:%s%d', colLetter(nCols), nRows+1)).NumberFormat = '0.0000';
        ws.Columns.AutoFit();
        ws.Range('A2').Select(); xl.ActiveWindow.FreezePanes = true;
        wb.Save(); wb.Close();
    catch; try; wb.Close(false); catch; end
    end
    xl.Quit(); xl.delete();
end

function letter = colLetter(n)
    letter = '';
    while n > 0
        r = mod(n-1,26); letter = [char(65+r), letter]; n = floor((n-1)/26);
    end
end

function xlc = rgb2xl(rgb)
    r=round(rgb(1)*255); g=round(rgb(2)*255); b=round(rgb(3)*255);
    xlc = r + g*256 + b*65536;
end