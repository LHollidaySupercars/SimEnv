function merged = concat_sessions(sessions)
% CONCAT_SESSIONS  Concatenate a cell array of session structs along their
%                  time axes.
%
% Each subsequent file is straight-appended with a one-sample-period gap.
% No overlap trimming is performed — beacon-60 boundary detection in
% lap_slicer identifies true lap boundaries directly from channel data.
%
% Lap_Number data in each subsequent session is renumbered so it continues
% monotonically from the end of the preceding session, preventing the lap
% collision that would otherwise cause lap_slicer's unique() call to merge
% laps across the file boundary.
%
% INPUT
%   sessions  - {1 x N} cell array of session structs.
%               Each struct has fields named after channels;
%               each field is a struct with .data (double vector) and
%               .time (double vector, seconds from file start).
%
% OUTPUT
%   merged    - single session struct with all channels concatenated.

    merged = sessions{1};
    ch_fields = fieldnames(merged);

    for s = 2:numel(sessions)
        s2 = sessions{s};

        % t_offset = last timestamp in merged + one sample period.
        % Walk ch_fields to find the first channel with a time axis.
        t_offset = 0;
        dt_gap   = 0.02;   % fallback: 50 Hz
        for c = 1:numel(ch_fields)
            fn = ch_fields{c};
            if isfield(merged, fn) && isfield(merged.(fn), 'time') && ...
               numel(merged.(fn).time) > 1
                t_offset = merged.(fn).time(end);
                dt_gap   = median(diff(merged.(fn).time));
                break;
            end
        end
        t_offset = t_offset + dt_gap;

        % Renumber Lap_Number in s2 so it continues from merged with no
        % collisions. Formula: lap_offset = max(merged) + 1 - min(s2)
        % so s2's lowest lap maps directly to max_merged + 1, regardless
        % of whether file 2 starts at 0 or 1.
        if isfield(merged, 'Lap_Number') && isfield(s2, 'Lap_Number') && ...
           ~isempty(merged.Lap_Number.data) && ~isempty(s2.Lap_Number.data)
            lap_max    = max(round(merged.Lap_Number.data));
            lap_min2   = min(round(s2.Lap_Number.data));
            lap_offset = lap_max + 1 - lap_min2;
            s2.Lap_Number.data = s2.Lap_Number.data + lap_offset;
        end

        % Straight append — no trimming.
        for c = 1:numel(ch_fields)
            fn = ch_fields{c};
            if ~isfield(s2, fn), continue; end

            merged.(fn).data = [merged.(fn).data(:); s2.(fn).data(:)];
            merged.(fn).time = [merged.(fn).time(:); s2.(fn).time(:) + t_offset];
        end
    end
end
