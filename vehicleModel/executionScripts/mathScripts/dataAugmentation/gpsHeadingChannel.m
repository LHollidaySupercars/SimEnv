function [heading_unwrapped, heading_rate] = gpsHeadingChannel(gpsLatChan, gpsLonChan, hdop)
% gpsHeadingChannel  Computes heading (deg) and heading rate (deg/s) from
%                     GPS lat/lon channels, gates out dropout/bad-fix
%                     samples using a jump-distance check, and unwraps to
%                     avoid 359->0 deg discontinuities.
%
% Inputs:
%   gpsLatChan - struct with fields .data (latitude, deg) and .time (s),
%                e.g. data.GPS_Latitude
%   gpsLonChan - struct with fields .data (longitude, deg) and .time (s),
%                e.g. data.GPS_Longitude
%   hdop       - (optional) vector of HDOP values, same length as lat/lon.
%                Not currently available - pass [] or omit. Wired in for
%                when the HDOP channel exists; will be included in the
%                validity gate automatically once supplied.
%
% Outputs:
%   heading_unwrapped - continuous heading trace in degrees (can exceed
%                        0-360 range, e.g. 720, -45, etc.)
%   heading_rate      - derivative of heading_unwrapped, deg/s. Held at 0
%                        through invalid/dropout samples rather than
%                        spiking.
%
% Example:
%   [hdg, hdgRate] = gpsHeadingChannel(data.GPS_Latitude, data.GPS_Longitude);

    lat = gpsLatChan.data(:);
    lon = gpsLonChan.data(:);
    t   = gpsLatChan.time(:);   % assumes lat/lon time channels are aligned

    N = length(lat);

    useHDOP = nargin >= 3 && ~isempty(hdop);
    if useHDOP
        hdop = hdop(:);
    end

    % Tunable thresholds
    hdopThresh   = 5;      % reject fixes worse than this (once HDOP available)
    jumpThreshM  = 50;     % max plausible distance (m) between samples - TUNE THIS
    R            = 6371000; % Earth radius, m

    % --- Build validity mask ---
    valid = true(N,1);
    valid(1) = ~( (abs(lat(1)) < 1e-6 && abs(lon(1)) < 1e-6) || isnan(lat(1)) || isnan(lon(1)) );

    for i = 2:N
        isZero = (abs(lat(i)) < 1e-6) && (abs(lon(i)) < 1e-6);
        isNaN_ = isnan(lat(i)) || isnan(lon(i));

        isHDOPbad = false;
        if useHDOP
            isHDOPbad = isnan(hdop(i)) || hdop(i) > hdopThresh;
        end

        lastValidIdx = find(valid(1:i-1), 1, 'last');
        if isempty(lastValidIdx)
            isJump = false;
        else
            lat1 = deg2rad(lat(lastValidIdx));
            lat2 = deg2rad(lat(i));
            dLat = lat2 - lat1;
            dLon = deg2rad(lon(i) - lon(lastValidIdx));
            a = sin(dLat/2)^2 + cos(lat1)*cos(lat2)*sin(dLon/2)^2;
            dist = 2*R*atan2(sqrt(a), sqrt(1-a));
            isJump = dist > jumpThreshM;
        end

        valid(i) = ~(isZero || isNaN_ || isHDOPbad || isJump);
    end

    % --- Compute heading only between consecutive VALID fixes ---
    heading_deg = zeros(N,1);

    lastValidIdx = find(valid, 1, 'first');
    if isempty(lastValidIdx)
        error('gpsHeadingChannel:noValidFixes', 'No valid GPS fixes found in input data.');
    end

    for i = 2:N
        if ~valid(i)
            heading_deg(i) = heading_deg(lastValidIdx); % hold last good heading
            continue
        end

        lat1 = deg2rad(lat(lastValidIdx));
        lat2 = deg2rad(lat(i));
        dLon = deg2rad(lon(i) - lon(lastValidIdx));

        y = sin(dLon) * cos(lat2);
        x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
        heading_deg(i) = mod(rad2deg(atan2(y, x)), 360);

        lastValidIdx = i;
    end
    heading_deg(1) = heading_deg(find(valid,1,'first')); % backfill first sample

    % --- Unwrap to remove 359->0 (or 0->359) jumps ---
    heading_unwrapped = unwrap(deg2rad(heading_deg));
    heading_unwrapped = rad2deg(heading_unwrapped);

    % --- Heading rate (derivative), gated so dropouts don't spike it ---
    heading_rate = zeros(N,1);
    for i = 2:N
        dtStep = t(i) - t(i-1);
        if dtStep <= 0 || ~valid(i)
            heading_rate(i) = 0;   % hold flat through dropout, avoid div-by-~0
        else
            heading_rate(i) = (heading_unwrapped(i) - heading_unwrapped(i-1)) / dtStep;
        end
    end

end