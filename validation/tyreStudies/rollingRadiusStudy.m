% verticalStiffness script
verticalStiffness = readtable("C:\SimEnv\tyreGrowthFzVsRL.csv");
vWheel = linspace(0, 250, 250);
rollingRadius = verticalStiffness.RL;
verticalForce = verticalStiffness.FZ;
wheelSpeed = verticalStiffness.N;
groundVelocity = verticalStiffness.V;
pressure = verticalStiffness.P;
RLvsFZ = polyfit(verticalForce, rollingRadius, 1);
verticalStiffness = verticalStiffness((verticalStiffness.N > 857 && verticalStiffness.N < 1367) || (verticalStiffness.N > 1455 && verticalStiffness.N < 1925))
%%
% verticalStiffness = verticalStiffness((verticalStiffness.N > 857 .* verticalStiffness.N < 1367) + (verticalStiffness.N > 1455 .* verticalStiffness.N < 1925));
temp = (verticalStiffness.N > 857 .* verticalStiffness.N < 1367) + (verticalStiffness.N > 1455 .* verticalStiffness.N < 1925)
groundVelocity((temp >= 1))
%%
rowMask = (verticalStiffness.N > 857 & verticalStiffness.N < 1367) | (verticalStiffness.N > 1455 & verticalStiffness.N < 1925);
verticalStiffness = verticalStiffness(rowMask, :);
%%

RLvsN = polyfit(wheelSpeed, rollingRadius, 1);


RLvsP = polyfit(pressure, rollingRadius, 1);

Cl = 2; 

RLvsFZ(1) * 0 + RLvsFZ(2)

RLvsN(2)

rho = 1.225;

calcedRadius = RLvsP(2) - (RLvsN(1) * vWheel) - (RLvsFZ(1) .* 1/2 .* rho .* vWheel.^2 * (Cl .* 0.45));
%%

% figure
% hold on 
% yyaxis left
% plot(vWheel, calcedRadius)
% yyaxis right
% plot(vWheel, (RLvsN(1) * vWheel*2.09))
% plot(vWheel, (RLvsFZ(1) .* 1/2 .* rho .* (vWheel*2.09).^2 * (Cl .* 0.45)))
% hold off

% pressureVsrollingRadius = verticalStiffness(verticalStiffness.N > 800 & startsWith(T.LastName, 'S'), :);
% 
% plot(wheelSpeed, groundVelocity)
% 
% % polyfit(wheelSpeed, groundVelocity)
% 
% corr(wheelSpeed, groundVelocity)
% 
% mean(wheelSpeed./groundVelocity)
% 


% RPM to m/s

% (wheelSpeed / 60) 

% KPH = RPM * pi * RL * 60 / 1000
% groundVelocity = groundVelocity((temp > 1))
%% Rolling Radius with Respect to Pressure
wheelSpeed = verticalStiffness.N;
groundVelocity = verticalStiffness.V;
figure
% wheelSpeed = wheelSpeed(temp >2)
scatter(wheelSpeed, (0.5 .* groundVelocity .* 1000) ./ (60 .* pi() .* wheelSpeed), [], verticalStiffness.P, 'filled');
colorbar;
ylabel(colorbar, 'Pressure');


%% Rolling Radius with Respect to Vertical Force
wheelSpeed = verticalStiffness.N;
groundVelocity = verticalStiffness.V;
figure
% wheelSpeed = wheelSpeed(temp >2)
scatter(wheelSpeed, (0.5 .* groundVelocity .* 1000) ./ (60 .* pi() .* wheelSpeed), [], verticalStiffness.FZ, 'filled');
colorbar;
ylabel(colorbar, 'Vertical Force');
%% Table look up and poly fit for rolling radius based on pressure
verticalStiffness_Pressure = readtable("C:\SimEnv\tyreGrowthFzVsRL.csv");
% filtering out for load, RPM, IA, 
rowMask = ...
(verticalStiffness_Pressure.FZ < -6000 & verticalStiffness_Pressure.FZ > -6500) & ...
(verticalStiffness_Pressure.N < 1000) & ...
(verticalStiffness_Pressure.IA > -0.5) & ...
(verticalStiffness_Pressure.SA > -0.5) & ...
(verticalStiffness_Pressure.SA < 0.5) ;
verticalStiffnessPressure_FZ_Bin1 = verticalStiffness_Pressure(rowMask, :); 


figure;

% --- Plot Data ---
% Small dots
plot(verticalStiffnessPressure_FZ_Bin1.P, verticalStiffnessPressure_FZ_Bin1.RL, 'b.', 'MarkerSize', 10);


% --- Labels & Title ---
title('Simplifying Tyre Model', 'FontSize', 14, 'FontWeight', 'bold');
xlabel('Pressure [Psi]', 'FontSize', 12);
ylabel('Rolling Radius [cm]', 'FontSize', 12);

% --- Formatting ---
grid on;
% legend('Series 1', 'Location', 'best');
set(gca, 'FontSize', 11);
xlim([min(x) max(x)]);
% ylim([-1 1]);  % uncomment to set manual y limits

%% Limited 50 4000-5000 N
% verticalStiffness_Pressure = readtable("C:\SimEnv\tyreGrowthFzVsRL.csv");
% filtering out for load, RPM, IA, 
rowMask = ...
(verticalStiffness_Pressure.FZ < -4000 & verticalStiffness_Pressure.FZ > -5000) & ...
(verticalStiffness_Pressure.N < 1000) & ...
(verticalStiffness_Pressure.IA > -0.5) & ...
(verticalStiffness_Pressure.SA > -0.5) & ...
(verticalStiffness_Pressure.SA < 0.5) ;
verticalStiffnessPressure_FZ_Bin2 = verticalStiffness_Pressure(rowMask, :); 


figure;

% --- Plot Data ---
% Small dots
hold on
plot(verticalStiffnessPressure_FZ_Bin1.P, verticalStiffnessPressure_FZ_Bin1.RL, 'b.', 'MarkerSize', 5);
plot(verticalStiffnessPressure_FZ_Bin2.P, verticalStiffnessPressure_FZ_Bin2.RL, 'r.', 'MarkerSize', 5);
hold off

% --- Labels & Title ---
title('Simplifying Tyre Model', 'FontSize', 14, 'FontWeight', 'bold');
xlabel('Pressure [Psi]', 'FontSize', 12);
ylabel('Rolling Radius [cm]', 'FontSize', 12);

% polyfit(

% --- Formatting ---
grid on;
% legend('Series 1', 'Location', 'best');
set(gca, 'FontSize', 11);
% xlim([min(x) max(x)]);
% ylim([-1 1]);  % uncomment to set manual y limits

%%
% --- Fit linear model to each bin ---
pFit_Bin1 = polyfit(verticalStiffnessPressure_FZ_Bin1.P, verticalStiffnessPressure_FZ_Bin1.RL, 1);
pFit_Bin2 = polyfit(verticalStiffnessPressure_FZ_Bin2.P, verticalStiffnessPressure_FZ_Bin2.RL, 1);

% --- Generate smooth fit lines ---
P_range = linspace(23, 31, 100);
RL_fit_Bin1 = polyval(pFit_Bin1, P_range);
RL_fit_Bin2 = polyval(pFit_Bin2, P_range);

% --- Plot data + fits ---
figure; hold on; grid on;
plot(verticalStiffnessPressure_FZ_Bin1.P, verticalStiffnessPressure_FZ_Bin1.RL, 'r.', 'MarkerSize', 5);
plot(verticalStiffnessPressure_FZ_Bin2.P, verticalStiffnessPressure_FZ_Bin2.RL, 'b.', 'MarkerSize', 5);
plot(P_range, RL_fit_Bin1, 'r-', 'LineWidth', 2);
plot(P_range, RL_fit_Bin2, 'b-', 'LineWidth', 2);

title('Simplifying Tyre Model');
xlabel('Pressure [Psi]');
ylabel('Rolling Radius [cm]');
legend('FZ 4000-5000N', 'FZ 6000-6500N', 'Fit Bin1', 'Fit Bin2', 'Location', 'northwest');

% --- Print coefficients ---
fprintf('Bin1 (4000-5000N): RL = %.4f * P + %.4f\n', pFit_Bin1(1), pFit_Bin1(2));
fprintf('Bin2 (6000-6500N): RL = %.4f * P + %.4f\n', pFit_Bin2(1), pFit_Bin2(2));

%% Surface fit
% --- Build combined arrays with FZ column ---
P_all  = [verticalStiffnessPressure_FZ_Bin1.P;  verticalStiffnessPressure_FZ_Bin2.P];
RL_all = [verticalStiffnessPressure_FZ_Bin1.RL; verticalStiffnessPressure_FZ_Bin2.RL];
FZ_all = [repmat(-4500, length(verticalStiffnessPressure_FZ_Bin1.P), 1);   % mid of 4000-5000
          repmat(-6250, length(verticalStiffnessPressure_FZ_Bin2.P), 1)];  % mid of 6000-6500

% --- Linear surface fit: RL = a0 + a1*P + a2*FZ ---
X = [ones(size(P_all)), P_all, FZ_all];
coeffs = X \ RL_all;

fprintf('RL = %.4f + %.4f*P + %.6f*FZ\n', coeffs(1), coeffs(2), coeffs(3));

% --- Plot ---
figure; hold on; grid on;
plot3(verticalStiffnessPressure_FZ_Bin1.P, repmat(-4500, length(verticalStiffnessPressure_FZ_Bin1.P),1), verticalStiffnessPressure_FZ_Bin1.RL, 'r.', 'MarkerSize', 5);
plot3(verticalStiffnessPressure_FZ_Bin2.P, repmat(-6250, length(verticalStiffnessPressure_FZ_Bin2.P),1), verticalStiffnessPressure_FZ_Bin2.RL, 'b.', 'MarkerSize', 5);

[P_grid, FZ_grid] = meshgrid(linspace(23,31,30), linspace(-7000,-3500,30));
RL_grid = coeffs(1) + coeffs(2)*P_grid + coeffs(3)*FZ_grid;
surf(P_grid, FZ_grid, RL_grid, 'FaceAlpha', 0.4);

xlabel('Pressure [Psi]'); ylabel('FZ [N]'); zlabel('Rolling Radius [cm]');
title('Tyre Rolling Radius Model');

% --- R-squared ---
RL_pred = X * coeffs;
SS_res = sum((RL_all - RL_pred).^2);
SS_tot = sum((RL_all - mean(RL_all)).^2);
fprintf('R² = %.4f\n', 1 - SS_res/SS_tot);

%% Interaction term for a better fit

% RL = a0 + a1*P + a2*FZ + a3*P*FZ
X = [ones(size(P_all)), P_all, FZ_all, P_all.*FZ_all];

%% Attempt for Centrifugal 

% Bin2: 6000-6500N
rowMask_Bin2 = ...
    (verticalStiffness_Pressure.FZ < -6000 & verticalStiffness_Pressure.FZ > -6500) & ...
    (verticalStiffness_Pressure.IA > -0.5) & ...
    (verticalStiffness_Pressure.SA > -0.5) & ...
    (verticalStiffness_Pressure.SA < 0.5);
verticalStiffnessPressure_FZ_Bin2 = verticalStiffness_Pressure(rowMask_Bin2, :);  % was wrongly named Bin3

% Bin3: 4000-5000N
rowMask_Bin3 = ...
    (verticalStiffness_Pressure.FZ < -4000 & verticalStiffness_Pressure.FZ > -5000) & ...
    (verticalStiffness_Pressure.IA > -0.5) & ...
    (verticalStiffness_Pressure.SA > -0.5) & ...
    (verticalStiffness_Pressure.SA < 0.5);
verticalStiffnessPressure_FZ_Bin3 = verticalStiffness_Pressure(rowMask_Bin3, :);


% --- Build combined arrays with FZ column ---
P_all  = [verticalStiffnessPressure_FZ_Bin2.P;  verticalStiffnessPressure_FZ_Bin3.P];
RL_all = [verticalStiffnessPressure_FZ_Bin2.RL; verticalStiffnessPressure_FZ_Bin3.RL];
FZ_all = [repmat(-4500, length(verticalStiffnessPressure_FZ_Bin2.P), 1);   % mid of 4000-5000
          repmat(-6250, length(verticalStiffnessPressure_FZ_Bin3.P), 1)];  % mid of 6000-6500

RC_all = [verticalStiffnessPressure_FZ_Bin2.N; verticalStiffnessPressure_FZ_Bin3.N];  % must match length
% --- Linear surface fit: RL = a0 + a1*P + a2*FZ ---
X = [ones(size(P_all)), P_all, FZ_all, RC_all];
coeffs = X \ RL_all;

fprintf('RL = %.4f + %.4f*P + %.6f*FZ + %.4f*RC\n', ...
        coeffs(1), coeffs(2), coeffs(3), coeffs(4));

% --- R-squared ---
RL_pred = X * coeffs;
SS_res = sum((RL_all - RL_pred).^2);
SS_tot = sum((RL_all - mean(RL_all)).^2);
fprintf('R² = %.4f\n', 1 - SS_res/SS_tot);


% --- Plot ---
figure; hold on; grid on;
plot3(verticalStiffnessPressure_FZ_Bin1.P, repmat(-4500, length(verticalStiffnessPressure_FZ_Bin1.P),1), verticalStiffnessPressure_FZ_Bin1.RL, 'r.', 'MarkerSize', 5);
plot3(verticalStiffnessPressure_FZ_Bin2.P, repmat(-6250, length(verticalStiffnessPressure_FZ_Bin2.P),1), verticalStiffnessPressure_FZ_Bin2.RL, 'b.', 'MarkerSize', 5);

[P_grid, FZ_grid] = meshgrid(linspace(23,31,30), linspace(-7000,-3500,30));
RL_grid = coeffs(1) + coeffs(2)*P_grid + coeffs(3)*FZ_grid;
surf(P_grid, FZ_grid, RL_grid, 'FaceAlpha', 0.4);

xlabel('Pressure [Psi]'); ylabel('FZ [N]'); zlabel('Rolling Radius [cm]');
title('Tyre Rolling Radius Model');

% --- R-squared ---
RL_pred = X * coeffs;
SS_res = sum((RL_all - RL_pred).^2);
SS_tot = sum((RL_all - mean(RL_all)).^2);
fprintf('R² = %.4f\n', 1 - SS_res/SS_tot);

%% Interaction term for a better fit

% RL = a0 + a1*P + a2*FZ + a3*P*FZ
X = [ones(size(P_all)), P_all, FZ_all, P_all.*FZ_all];