%% ========================================================================
% PHASE 7 - AUGMENT DATA WITH SIMULINK MODEL
%  ========================================================================

% ---- Load vehicle kinematic parameters ----
GEN3_KinematicParameters_simulink;   % populates 'vehicle' in the workspace
% Resolve the Chevrolet/chevrolet case-duplicate before it collides
% on Windows' case-insensitive filesystem during bus generation.
if isfield(vehicle, 'Chevrolet') && isfield(vehicle, 'chevrolet')
    vehicle = rmfield(vehicle, 'Chevrolet');   % keep lowercase, drop the dupe
    % (swap which one you remove if the model actually references 'Chevrolet')
end
% ---- Config ----
chanList = {'Steering_Angle', 'Ground_Speed', 'Acceleration_Y_Filt', ...
            'Wheel_Speed_Front_Left', 'Wheel_Speed_Front_Right'};

com_path  = 'E:\2026\E07_TSV\_HOL\teamData\Q21\04_GVR\PAY_2026_Q21.ld';
modelName = 'V8_mdl';

params.rTyreFront = 320;
params.rTyreRear  = 330;
params.mass       = 1350;
params.RAD2DEG_V  = 180/pi;
params.vehicle    = vehicle;

% ---- Build channel input bus (base workspace, before sim compiles) ----
build_aug_input_bus(chanList, 'AugInputBus');


% ---- Build vehicle bus: clear stale workspace state + file, rebuild fresh ----
evalin('base', 'clearvars -regexp ^VehicleBus$|^slBus');

f = which('VehicleBus.m');
if ~isempty(f)
    delete(f);
end

Simulink.Bus.createObject(params.vehicle, 'VehicleBus');   % writes VehicleBus.m
cellInfo = VehicleBus();                                    % returns cell array of definitions
Simulink.Bus.cellToObject(cellInfo);                         % actually populates slBus* objects

% Root object comes back auto-named (e.g. slBus85) — find it and rename to VehicleBus.
allSlBus = who('-regexp', '^slBus\d+$');
rootMask = cellfun(@(n) isempty(regexp(n, '_', 'once')), allSlBus);
rootName = allSlBus{rootMask};
assignin('base', 'VehicleBus', evalin('base', rootName));

% Sanity check: confirm the bus actually exists and is a real Simulink.Bus
b = evalin('base', 'VehicleBus');
assert(isa(b, 'Simulink.Bus') && numel(b.Elements) > 1, ...
    ['VehicleBus was not instanti' ...
'ated correctly in the base workspace.']);

% ---- Load .ld file ----
aug_data      = motec_ld_reader(com_path, {});
aug_data.info = motec_ld_info(com_path, false);
preNames      = fieldnames(aug_data);

% ---- Run sim ----
simOut = run_sim_augment(modelName, aug_data, chanList, params);
[aug_data, newChannels] = extract_new_sim_channels(aug_data, simOut, preNames);

fprintf('New channel(s): %s\n', strjoin(newChannels, ', '));

% aug_data now has new channels stamped write_to_ld=true.
% Paste existing ld_ch collection loop + ld_add_channel + movefile here.


%% ===================== Local functions ==================================

function simOut = run_sim_augment(modelName, aug_data, chanList, params)
    ds = build_sim_input_dataset(aug_data, chanList);

    simIn = Simulink.SimulationInput(modelName);
    pNames = fieldnames(params);
    for pi = 1:numel(pNames)
        simIn = simIn.setVariable(pNames{pi}, params.(pNames{pi}));
    end
    simIn  = simIn.setExternalInput(ds);
    simOut = sim(simIn);
end

function ds = build_sim_input_dataset(chan, chanList)
    % Bus input format per MathWorks docs: a struct whose fields are
    % timeseries objects, field names matching bus element names exactly.
    % That struct becomes the single Dataset element for the bus Inport.
    
    busData = struct();
    
    for i = 1:numel(chanList)
        name = chanList{i};
        t = chan.(name).time(:);
        v = chan.(name).data(:);
    
        mono = [true; diff(t) > 0];
        t = t(mono);
        v = v(mono);
    
        ts = timeseries(v, t, 'Name', name);
        ts.DataInfo.Interpolation = tsdata.interpolation('linear');
    
        busData.(name) = ts;
    end
    
    ds = Simulink.SimulationData.Dataset;
    ds = ds.addElement(busData, 'Road Input');   % struct-of-timeseries, one Dataset element
end


function busObj = build_aug_input_bus(chanList, busName)
    if nargin < 2 || isempty(busName)
        busName = 'AugInputBus';
    end
    
    elems(numel(chanList), 1) = Simulink.BusElement;
    for i = 1:numel(chanList)
        elems(i).Name       = chanList{i};
        elems(i).DataType   = 'double';
        elems(i).Dimensions = 1;
        elems(i).Complexity = 'real';
    end
    
    busObj = Simulink.Bus;
    busObj.Elements = elems;
    
    assignin('base', busName, busObj);
    fprintf('Bus object "%s" built with %d element(s): %s\n', ...
        busName, numel(chanList), strjoin(chanList, ', '));
end


function [aug_data, newChannels] = extract_new_sim_channels(aug_data, simOut, preNames)
    newChannels = {};

    outputFields = {'bicycleModel', 'bicycleModel1'};  % adjust to match what's actually populated
    for oi = 1:numel(outputFields)
        of = outputFields{oi};
        if ~isprop(simOut, of), continue; end

        s = simOut.(of);
        if ~isfield(s, 'signals'), continue; end

        for si = 1:numel(s.signals)
            name = s.signals(si).label;
            if isempty(name), name = sprintf('%s_%d', of, si); end

            if isfield(aug_data, name), continue; end  % pass-through, skip

            ch.data        = s.signals(si).values(:);
            ch.time        = s.time(:);
            ch.units       = '';
            ch.sample_rate = 1 / mean(diff(s.time));
            ch.raw_name    = name;
            ch.write_to_ld = true;
            ch.overwrite   = false;

            aug_data.(name) = ch;
            newChannels{end+1} = name; %#ok<AGROW>
        end
    end
end