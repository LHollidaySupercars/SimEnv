testType = struct()

calspanReadable = readtable("C:\SimEnv\vehicleModel\components\tyre\Cornering Data Files\calspanTestNames.xlsx")

testType.FreeRoll = calspanReadable(contains(calspanReadable.Type, 'FreeRoll', 'IgnoreCase', true), :);
testType.BrkDrv = calspanReadable(contains(calspanReadable.Type, 'BrkDrv', 'IgnoreCase', true), :);
%% Load corner

dataCornering = calspanTyre('C:\SimEnv\vehicleModel\components\tyre\Cornering Data Files\', 'run',...
    'FileTypes', {'.dat'}, ...
    'Save', true, ...
    'SaveFileName', 'calspan_run2017_9_2.mat');

tyreData.FreeRoll = filterTestType(dataCornering, testType.FreeRoll.Test, 'Prefix', 'A_');
%% Load Braking Drive


dataBraking  = calspanTyre('C:\SimEnv\vehicleModel\components\tyre\Braking Data Files\', 'run',...
    'FileTypes', {'.dat'}, ...
    'Save', true, ...
    'SaveFileName', 'calspan_run2017_9_2.mat')

tyreData.BrkDrv = filterTestType(dataBraking, testType.BrkDrv.Test, 'Prefix', 'A_');

save('calspanData_2017_separated.mat','tyreData')

%%


test = 'A_1792run10_Thermal'
data = load('calspanData_2017_separated.mat');
% .tyreData.FreeRoll.(test)
% Check coverage across key variables
figure;
subplot(2,2,1); scatter(data.tyreData.FreeRoll.(test).V, data.tyreData.FreeRoll.(test).FZ, 10, data.tyreData.FreeRoll.(test).FY); 
xlabel('Slip Angle [deg]'); ylabel('Normal Load [N]'); title('Lateral Force Coverage');
colorbar;

subplot(2,2,2); scatter(data.tyreData.FreeRoll.(test).SR, data.tyreData.FreeRoll.(test).FZ, 10, data.tyreData.FreeRoll.(test).FX);
xlabel('Slip Ratio [-]'); ylabel('Normal Load [N]'); title('Longitudinal Force Coverage');
colorbar;

subplot(2,2,3); histogram(data.tyreData.FreeRoll.(test).FZ, 50);
xlabel('Normal Load [N]'); title('Load Distribution');

subplot(2,2,4); histogram(data.tyreData.FreeRoll.(test).IA, 50);
xlabel('Camber [deg]'); title('Camber Distribution');