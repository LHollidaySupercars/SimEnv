function proto = br2_protocol_get(name)
% BR2_PROTOCOL_GET  Return a BR2 beacon protocol definition struct by name.
%
% USAGE:
%   proto = br2_protocol_get('standard')   % default — original track protocol
%   proto = br2_protocol_get('TAS2025')    % TAS 2025 season protocol
%
% OUTPUT FIELDS:
%   proto.name       (string)  Canonical protocol name
%   proto.variant    (string)  Detection algorithm: 'standard' | 'simple_pulse'
%   proto.idle       (double)  Value during normal running (no crossing)
%   proto.sf_pulse   (double)  Value emitted at S/F line crossing
%   proto.pitin      (double)  Value emitted on pit-in
%   proto.pitout     (double)  Value emitted on pit-out (= idle for simple_pulse)
%
% TO ADD A NEW PROTOCOL:
%   1. Add a new 'case' block below.
%   2. Set variant to 'standard' or 'simple_pulse'.
%   3. No other files need changing — lap_slicer picks up the new case
%      automatically via opts.br2_protocol = '<name>'.
%
% PROTOCOL REFERENCE:
%
%   'standard'    (default)
%     Values:  900 = garage/pit hold, 996 = running, 999 = approaching S/F
%              1500 = S/F crossing discriminator
%     Pit-in:  996 → 999 → 900 (no 1500 after 999)
%     Pit-out: 900 hold ends → 999 → 1500 → 996
%     S/F:     999 → 1500 → 996
%
%   'TAS2025'   (Tas 2025 season)
%     Values:  900 = idle/garage, 996 = S/F pulse, 999 = pit-in/out marker
%     S/F:     900 → 996 → 900  (996 is the crossing pulse, very brief)
%     Pit-in:  900 → 999         (stays at 999 while in pit lane)
%     Pit-out: 999 → 900

    if nargin < 1 || isempty(name)
        name = 'standard';
    end

    switch lower(strtrim(name))

        case 'standard'
            proto.name     = 'standard';
            proto.variant  = 'standard';   % existing multi-value detection loop
            proto.idle     = 996;
            proto.sf_pulse = 1500;
            proto.pitin    = 999;
            proto.pitout   = 900;

        case 'tas2025'
            proto.name     = 'TAS2025';
            proto.variant  = 'simple_pulse';
            proto.idle     = 900;
            proto.sf_pulse = 996;
            proto.pitin    = 999;
            proto.pitout   = 900;   % pit-out = return to idle

        otherwise
            error('br2_protocol_get: unknown protocol ''%s''. Known: standard, TAS2025.', name);
    end
end
