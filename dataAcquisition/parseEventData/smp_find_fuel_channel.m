function ch_name = smp_find_fuel_channel(lap)
% SMP_FIND_FUEL_CHANNEL  Find the fuel-flow channel in a lap struct.
%
% Returns the field name (string) of the fuel-flow channel in lap.channels,
% or '' if none is found.
%
% MoTeC logs "Fuel Flow Used Mass" (g/s). After matlab.lang.makeValidName
% this becomes "Fuel_Flow_Used_Mass".  We also check common alternative names.

ch_name = '';
if ~isstruct(lap) || ~isfield(lap, 'channels')
    return;
end

candidates = { ...
    'Fuel_Flow_Used_Mass', ...   % MoTeC "Fuel Flow Used Mass" → makeValidName
    'FuelFlowUsedMass', ...
    'Fuel_Flow_Mass', ...
    'Fuel_Flow', ...
    'FuelFlow', ...
    'FuelFlowRate', ...
    'Fuel_Flow_Rate', ...
};

ch_fields = fieldnames(lap.channels);

% 1. Exact match first
for k = 1:numel(candidates)
    if isfield(lap.channels, candidates{k})
        ch_name = candidates{k};
        return;
    end
end

% 2. Case-insensitive prefix match: any field whose lower-case name contains
%    both "fuel" and "flow"
ch_lower = lower(ch_fields);
for k = 1:numel(ch_lower)
    if contains(ch_lower{k}, 'fuel') && contains(ch_lower{k}, 'flow')
        ch_name = ch_fields{k};
        return;
    end
end

end
