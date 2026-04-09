% aeroData = readtable("PARITY_AERO_MAPS.xlsx",'Sheet','GM');
% 
% aeroData_55RS = aeroData(aeroData.road_spd == 55.5, :);
% sortedTblaeroData_0Roll = sortrows(GMAero_0Roll, {'FRH_mm', 'RRH_mm'});

aeroData = readtable("PARITY_AERO_MAPS.xlsx",'Sheet','Ford');

aeroData_55RS = aeroData(aeroData.road_spd == 55.5, :);
sortedTblaeroData_0Roll = sortrows(GMAero_0Roll, {'FRH_mm', 'RRH_mm'});

%%


% =========================================================
% Bivariate polynomial surface fit: Cz = f(FRH, RRH)
% No toolboxes required — uses core MATLAB only
% =========================================================
% fs_norm = fit([GMAero_0Roll.FRH_mm, GMAero_0Roll.RRH_mm], GMAero_0Roll.CLa_SCz, 'poly33')
% --- 1. Your data (replace with your actual values) ------
% FRH and RRH in mm, Cz as measured/simulated coefficient
FRH = aeroData_55RS.FRH_mm %[20 20 20 25 25 25 30 30 30]';   % front ride height
RRH = aeroData_55RS.RRH_mm;   % rear ride height
Roll = aeroData_55RS.roll_deg;
% Cz  = GMAero_55RS.CLa_SCz;

% =========================================================
% Polynomial surface fit: 8 outputs = f(FRH, RRH, Roll)
% Degree 2 — 10 terms — 8 separate fits
% Produces MoTeC math file output
% =========================================================

% --- 1. Channel names for MoTeC --------------------------
ch_frh  = 'Laser Ride Height Front';
ch_rrh  = 'Laser Ride Height Rear';
ch_roll = 'Roll';

% --- 2. Your data ----------------------------------------
% Replace each column with your actual aeromap data
% FRH  = [20 20 20 20 20 25 25 25 25 25 30 30 30 30 30]';
% RRH  = [25 25 30 30 35 25 25 30 30 35 25 25 30 30 35]';
% Roll = [ 0  2  0  2  0  0  2  0  2  0  0  2  0  2  0]';

% Output columns — replace with your actual data

CDa_SCx  = aeroData_55RS.CDa_SCx;   % replace
CLf_SCzF = aeroData_55RS.CLf_SCzF;   % replace
CLr_SCzR = aeroData_55RS.CLr_SCzR;   % replace
AB_FRT   = aeroData_55RS.AB_FRT;   % replace
EFF      = aeroData_55RS.EFF;   % replace
CSa_Scy  = aeroData_55RS.CSa_Scy;   % replace
CSf_SCyF = aeroData_55RS.CSf_SCyF;   % replace
CSr_SCyR = aeroData_55RS.CSr_SCyR;   % replace

% --- 3. Package outputs and labels -----------------------
outputs = {CDa_SCx, CLf_SCzF, CLr_SCzR, AB_FRT, EFF, CSa_Scy, CSf_SCyF, CSr_SCyR};
names   = {'CDa_SCx','CLf_SCzF','CLr_SCzR','AB_FRT','EFF','CSa_Scy','CSf_SCyF','CSr_SCyR'};

% --- 4. Design matrix (no normalisation) -----------------
X = [ones(size(FRH)), ...
     FRH,       RRH,       Roll, ...
     FRH.^2,    RRH.^2,    Roll.^2, ...
     FRH.*RRH,  FRH.*Roll, RRH.*Roll];

term_labels = {'b1','b2','b3','b4','b5','b6','b7','b8','b9','b10'};
term_desc   = {'intercept','FRH','RRH','Roll','FRH^2','RRH^2','Roll^2','FRH*RRH','FRH*Roll','RRH*Roll'};

% --- 5. Fit all outputs ----------------------------------
fprintf('\n=========================================================\n');
fprintf(' FIT QUALITY SUMMARY\n');
fprintf('=========================================================\n');
fprintf('%-12s   R²        RMSE\n', 'Output');
fprintf('-----------------------------------------\n');

all_beta = zeros(10, length(outputs));

for i = 1:length(outputs)
    y = outputs{i};
    beta = X \ y;
    all_beta(:,i) = beta;

    y_fit     = X * beta;
    residuals = y - y_fit;
    R2   = 1 - sum(residuals.^2) / sum((y - mean(y)).^2);
    RMSE = sqrt(mean(residuals.^2));

    fprintf('%-12s   %.6f  %.6f\n', names{i}, R2, RMSE);
end

% --- 6. Print MoTeC constants ----------------------------
fprintf('\n=========================================================\n');
fprintf(' MOTEC MATH CONSTANTS\n');
fprintf('=========================================================\n\n');

for i = 1:length(outputs)
    fprintf('<!-- %s -->\n', names{i});
    for j = 1:10
        fprintf('<MathConstant Name="%s_%s" Value="%.8f" Unit=""/>\n', ...
            names{i}, term_labels{j}, all_beta(j,i));
    end
    fprintf('\n');
end

% --- 7. Print MoTeC expressions --------------------------
fprintf('\n=========================================================\n');
fprintf(' MOTEC MATH EXPRESSIONS\n');
fprintf('=========================================================\n\n');

for i = 1:length(outputs)
    n = names{i};
    fprintf('<MathExpression Id="%s" DisplayDPS="4" DisplayColorIndex="1" Interpolate="1" Script="\n', n);
    fprintf('  ''%s_b1'' []\n', n);
    fprintf('  + ''%s_b2'' [] * ''%s'' [mm]\n',   n, ch_frh);
    fprintf('  + ''%s_b3'' [] * ''%s'' [mm]\n',   n, ch_rrh);
    fprintf('  + ''%s_b4'' [] * ''%s'' [deg]\n',  n, ch_roll);
    fprintf('  + ''%s_b5'' [] * ''%s'' [mm] * ''%s'' [mm]\n',   n, ch_frh,  ch_frh);
    fprintf('  + ''%s_b6'' [] * ''%s'' [mm] * ''%s'' [mm]\n',   n, ch_rrh,  ch_rrh);
    fprintf('  + ''%s_b7'' [] * ''%s'' [deg] * ''%s'' [deg]\n', n, ch_roll, ch_roll);
    fprintf('  + ''%s_b8'' [] * ''%s'' [mm] * ''%s'' [mm]\n',   n, ch_frh,  ch_rrh);
    fprintf('  + ''%s_b9'' [] * ''%s'' [mm] * ''%s'' [deg]\n',  n, ch_frh,  ch_roll);
    fprintf('  + ''%s_b10'' [] * ''%s'' [mm] * ''%s'' [deg]\n', n, ch_rrh,  ch_roll);
    fprintf('" SampleRate="0" Unit=""/>\n\n');
end