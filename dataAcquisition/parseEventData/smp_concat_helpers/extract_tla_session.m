function [tla, session] = extract_tla_session(stem)
% EXTRACT_TLA_SESSION  Parse stem as TLA_YEAR_SESSION pattern.
% Returns: TLA = three-letter acronym, SESSION = remainder after TLA_YEAR
    parts = strsplit(stem, '_');
    if numel(parts) >= 1, tla = parts{1}; else, tla = stem; end
    if numel(parts) >= 3, session = strjoin(parts(3:end), '_'); else, session = ''; end
end

