function col = get_colour(cfg, key, mode)
% GET_COLOUR  Look up a colour from the SMP colour config.
%
% Usage:
%   col = get_colour(cfg, 'Ford',      'manufacturer')  % [0.00 0.31 0.65]
%   col = get_colour(cfg, 'Chev',      'manufacturer')  % [1.00 0.84 0.00]
%   col = get_colour(cfg, 'S. Jones',  'driver')        % fallback if unknown
%
% Inputs:
%   cfg   - struct from smp_colours()
%   key   - string to look up
%   mode  - 'manufacturer' or 'driver'
%
% Output:
%   col   - [R G B] double row vector in [0,1] range

    if nargin < 3, mode = 'manufacturer'; end

    % Sanitise key for use as struct fieldname
    safe_key = matlab.lang.makeValidName(key);

    table = cfg.(mode);

    if isfield(table, safe_key)
        col = table.(safe_key);
    else
        col = cfg.fallback;
        % Uncomment to see warnings for unmapped entries:
        % fprintf('[get_colour] No %s colour for "%s" — using fallback.\n', mode, key);
    end
end
