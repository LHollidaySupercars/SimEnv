function C = colours()
% COLOURS  Manufacturer and driver colour lookup for SMP Supercars reports.
%
% Usage:
%   C = colours();
%   c = C.manufacturer('Ford');          % [R G B]
%   c = C.manufacturer('Chev');
%   c = C.manufacturer('Toyota');
%   c = C.driver('van Gisbergen');       % [R G B]  (if defined below)
%   c = C.get('Ford');                   % tries manufacturer, then driver, then fallback
%
% To add a driver colour:
%   Add a line in the DRIVER COLOURS block below.
%   Key is the driver's last name, case-insensitive.
%
% Ford   = Blue
% Chev   = Yellow
% Toyota = Red

    % ------------------------------------------------------------------
    %  MANUFACTURER COLOURS
    % ------------------------------------------------------------------
    MFG = struct();
    MFG.ford        = [0.00  0.27  0.68];   % Ford Blue
    MFG.chev        = [0.95  0.80  0.00];   % Chevrolet Yellow
    MFG.chevrolet   = [0.95  0.80  0.00];   % alias
    MFG.toyota      = [0.85  0.10  0.10];   % Toyota Red
    MFG.holden      = [0.95  0.80  0.00];   % legacy alias → Chev yellow
    MFG.mustang     = MFG.ford;             % vehicle_id alias
    MFG.camaro      = MFG.chev;
    MFG.camry       = MFG.toyota;

    % ------------------------------------------------------------------
    %  DRIVER COLOURS
    %  Add entries here. Key = last name, lower case.
    %  e.g.  DRV.mostert = [0.20  0.55  0.90];
    % ------------------------------------------------------------------
    DRV = struct();
    % DRV.mostert       = [0.20  0.55  0.90];
    % DRV.vangisbergen  = [0.10  0.65  0.30];
    % DRV.reynolds      = [0.90  0.40  0.10];

    % ------------------------------------------------------------------
    %  Fallback palette — cycles when no match found
    % ------------------------------------------------------------------
    FALLBACK = [
        0.12  0.47  0.71;   % muted blue
        0.90  0.33  0.05;   % burnt orange
        0.20  0.63  0.17;   % green
        0.65  0.14  0.55;   % purple
        0.55  0.34  0.29;   % brown
        0.80  0.47  0.74;   % lavender
        0.50  0.50  0.50;   % grey
    ];
    fallback_idx = 0;

    % ------------------------------------------------------------------
    %  Exposed lookup functions
    % ------------------------------------------------------------------
    C.manufacturer = @manufacturer_colour;
    C.driver       = @driver_colour;
    C.get          = @get_colour;

    % ------------------------------------------------------------------
    function rgb = manufacturer_colour(name)
        key = lower(strtrim(name));
        % Strip common suffixes/prefixes to find base manufacturer
        key = regexprep(key, '\s+(gen|generation|v8|supercar|mustang|camaro|camry).*$', '');
        key = strtrim(key);
        if isfield(MFG, key)
            rgb = MFG.(key);
        else
            % Try first word only (e.g. "Ford Mustang" → "ford")
            parts = strsplit(key);
            if numel(parts) > 1 && isfield(MFG, parts{1})
                rgb = MFG.(parts{1});
            else
                rgb = next_fallback();
                % Uncomment to debug unmatched manufacturers:
                % warning('colours: unknown manufacturer "%s" — using fallback.', name);
            end
        end
    end

    function rgb = driver_colour(name)
        % Try last name first, then full sanitised name
        key = lower(strtrim(name));
        parts = strsplit(key);
        last  = parts{end};
        last  = regexprep(last, '[^a-z]', '');  % strip punctuation
        if isfield(DRV, last)
            rgb = DRV.(last);
        elseif isfield(DRV, regexprep(key,'[^a-z]',''))
            rgb = DRV.(regexprep(key,'[^a-z]',''));
        else
            rgb = next_fallback();
        end
    end

    function rgb = get_colour(label)
        % Try manufacturer → driver → fallback
        key = lower(strtrim(label));
        key_clean = regexprep(key, '\s+(gen|generation|v8).*$', '');
        if isfield(MFG, key_clean) || isfield(MFG, strsplit(key_clean){1})
            rgb = manufacturer_colour(label);
        elseif isfield(DRV, regexprep(key,'[^a-z]',''))
            rgb = driver_colour(label);
        else
            rgb = next_fallback();
        end
    end

    function rgb = next_fallback()
        fallback_idx = mod(fallback_idx, size(FALLBACK,1)) + 1;
        rgb = FALLBACK(fallback_idx, :);
    end

end
