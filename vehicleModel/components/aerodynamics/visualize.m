FordAero = readtable("PARITY_AERO_MAPS.xlsx",'Sheet','FORD');
ToyotaAero = readtable("PARITY_AERO_MAPS.xlsx",'Sheet','TOYOTA');
GMAero = readtable("PARITY_AERO_MAPS.xlsx",'Sheet','GM');

%% Ford

FordData = FordAero((FordAero.roll_deg == 0 & FordAero.yaw_deg == 0), :)
sortedTblFord = sortrows(FordData, {'FRH_mm', 'RRH_mm'})

%% Toyota

ToyotaData = ToyotaAero((ToyotaAero.roll_deg == 0 & ToyotaAero.yaw_deg == 0), :)
sortedTblToyota = sortrows(ToyotaData, {'FRH_mm', 'RRH_mm'})

%% GM

GMAero = GMAero((GMAero.roll_deg == 0 & GMAero.yaw_deg == 0), :)
sortedTblGM = sortrows(GMAero, {'FRH_mm', 'RRH_mm'})

%% Toyota Vs Ford

toyotaVsFord = array2table(sortedTblFord{:,:} - sortedTblToyota{:,:}, ...
    'VariableNames', sortedTblFord.Properties.VariableNames);

%% GM Vs Ford

GMVsFord = array2table(abs(sortedTblGM{:,:}) - abs(sortedTblFord{:,:}), ...
    'VariableNames', sortedTblFord.Properties.VariableNames);

%%

length(unique(sortedTblFord.FRH_mm))
length(unique(sortedTblFord.RRH_mm))
T = delaunay(sortedTblFord.FRH_mm, sortedTblFord.RRH_mm); %
trisurf(T, sortedTblFord.FRH_mm, sortedTblFord.RRH_mm, sortedTblFord.CDa_SCx); %

%% SCx_CDA - Drag

x = sortedTblFord.FRH_mm;
N = length(x)
y = sortedTblFord.RRH_mm;
M = length(y)
z = sortedTblFord.CDa_SCx;
[Xq, Yq] = meshgrid(linspace(min(x), max(x), 30), ...
                    linspace(min(y), max(y), 30)); % N, M are number of points
Zq = griddata(x, y, z, Xq, Yq); 
surf(Xq, Yq, Zq) %

%% SCx_CDA - Aero Efficiency

x = sortedTblFord.FRH_mm;
N = length(x)
y = sortedTblFord.RRH_mm;
M = length(y)
z =  sortedTblFord.EFF;
[Xq, Yq] = meshgrid(linspace(min(x), max(x), 30), ...
                    linspace(min(y), max(y), 30)); % N, M are number of points
Zq = griddata(x, y, z, Xq, Yq); 
surf(Xq, Yq, Zq) %
xlabel('Front Ride Height [mm]')
ylabel('Rear Ride Height [mm]')
zlabel('Aero Efficiency')
%% SCx_CDA - Side Force

x = sortedTblFord.FRH_mm;
N = length(x)
y = sortedTblFord.RRH_mm;
M = length(y)
z = sortedTblFord.CSa_Scy;
[Xq, Yq] = meshgrid(linspace(min(x), max(x), 30), ...
                    linspace(min(y), max(y), 30)); % N, M are number of points
Zq = griddata(x, y, z, Xq, Yq); 
surf(Xq, Yq, Zq) %
xlabel('Front Ride Height [mm]')
ylabel('Rear Ride Height [mm]')
zlabel('side Force [SCy]')


%% SCx_CDA - Side Force Delta Ford / Toyota

x = ToyotaData.FRH_mm;
N = length(x)
y = ToyotaData.RRH_mm;
M = length(y)
z = toyotaVsFord.CSa_Scy;
[Xq, Yq] = meshgrid(linspace(min(x), max(x), 30), ...
                    linspace(min(y), max(y), 30)); % N, M are number of points
Zq = griddata(x, y, z, Xq, Yq); 
surf(Xq, Yq, Zq) %
xlabel('Front Ride Height [mm]')
ylabel('Rear Ride Height [mm]')
zlabel('side Force [SCy]')


%% SCx_CDA - down Force Delta Ford / /gm

x = GMAero.FRH_mm;
N = length(x)
y = GMAero.RRH_mm;
M = length(y)
z = GMVsFord.CLa_SCz;
[Xq, Yq] = meshgrid(linspace(min(x), max(x), 30), ...
                    linspace(min(y), max(y), 30)); % N, M are number of points
Zq = griddata(x, y, z, Xq, Yq); 
surf(Xq, Yq, Zq) %
title('abs GM - Ford, More negative Ford = more downforce')
xlabel('Front Ride Height [mm]')
ylabel('Rear Ride Height [mm]')
zlabel('[SCz]')

%% normalized at 100 kph
velocity = 100;
x = GMAero.FRH_mm;
N = length(x)
y = GMAero.RRH_mm;
M = length(y)
z = GMVsFord.CLa_SCz .* (velocity / 3.6)^2 .* 1.225 .* 0.5 ;
[Xq, Yq] = meshgrid(linspace(min(x), max(x), 30), ...
                    linspace(min(y), max(y), 30)); % N, M are number of points
Zq = griddata(x, y, z, Xq, Yq); 
surf(Xq, Yq, Zq) %
title('abs GM - Ford, More negative Ford == more downforce')
xlabel('Front Ride Height [mm]')
ylabel('Rear Ride Height [mm]')
zlabel('Down Force [N]')

%% normalized at 150 kph
velocity = 150;
x = GMAero.FRH_mm;
N = length(x)
y = GMAero.RRH_mm;
M = length(y)
z = GMVsFord.CLa_SCz .* (velocity / 3.6)^2 .* 1.225 .* 0.5 ;
[Xq, Yq] = meshgrid(linspace(min(x), max(x), 30), ...
                    linspace(min(y), max(y), 30)); % N, M are number of points
Zq = griddata(x, y, z, Xq, Yq); 
surf(Xq, Yq, Zq) %
title('abs GM - Ford, More negative Ford == more downforce')
xlabel('Front Ride Height [mm]')
ylabel('Rear Ride Height [mm]')
zlabel('Down Force [N]')