function cfg = smp_colours()
% SMP_COLOURS  Central colour definitions for all SMP report plots.
%
% Returns a struct with:
%   cfg.manufacturer   - colours keyed by manufacturer string
%   cfg.driver         - colours keyed by driver name (populate as needed)
%   cfg.fallback       - colour used when no match found
%
% Usage:
%   cfg = smp_colours();
%   col = cfg.manufacturer.Ford;         % [R G B]
%   col = get_colour(cfg, 'Ford', 'manufacturer');

    % ------------------------------------------------------------------ %
    %  Manufacturer colours
    % ------------------------------------------------------------------ %
    %  Ford     - Blue
    %  Chev     - Yellow
    %  Toyota   - Red
    % ------------------------------------------------------------------ %
    cfg.manufacturer.Ford   = [0.00  0.31  0.65];   % Ford Blue
    cfg.manufacturer.Chev   = [1.00  0.84  0.00];   % Chevrolet Yellow
    cfg.manufacturer.Toyota = [0.85  0.10  0.10];   % Toyota Red

    % Aliases — add more as needed
    cfg.manufacturer.Chevrolet   = cfg.manufacturer.Chev;
    cfg.manufacturer.Holden      = cfg.manufacturer.Chev;   % legacy alias
    cfg.manufacturer.Mustang     = cfg.manufacturer.Ford;
    cfg.manufacturer.Camaro      = cfg.manufacturer.Chev;
    cfg.manufacturer.Camry       = cfg.manufacturer.Toyota;
    cfg.manufacturer.GR_Supra    = cfg.manufacturer.Toyota;

    % ------------------------------------------------------------------ %
    %  Driver colours  — populate when drivers are confirmed
    %
    %  Format: cfg.driver.('Driver Name') = [R G B];
    %  e.g.:   cfg.driver.('S. van Gisbergen') = [0.2 0.6 1.0];
    % ------------------------------------------------------------------ %
    cfg.driver = struct();   % empty for now — add entries here

    % ------------------------------------------------------------------ %
    %  Fallback colour (grey) when no match found
    % ------------------------------------------------------------------ %
    cfg.fallback = [0.55  0.55  0.55];
end


% ======================================================================= %
%  HELPER — call this anywhere you need a colour
% ======================================================================= %
% function col = get_colour(cfg, key, mode)
%   mode: 'manufacturer' or 'driver'
%   Returns [R G B] or cfg.fallback if key not found.
%
% This is defined as a standalone function in get_colour.m (see below).
