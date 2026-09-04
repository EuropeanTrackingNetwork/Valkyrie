function T = parsePodName(names)
%PARSEPODNAME Break C-POD / detection file names into matchable components.
%
%   T = parsePodName(names)
%
%   Handles every naming variant seen in the Valkyrie data so far:
%       "GB1 2011 06 23 POD1685"            (station + DEPLOYMENT date)
%       "GB1A 2011 06 21 POD1685 file01"    (station + POD-ON date, station suffix)
%       "GB1_2011_11_09_POD1685_file01"     (station + RECOVERY date, underscores)
%
%   Because the date embedded in the name is NOT a consistent quantity
%   (deployment / power-on / recovery), it must never be used as a join key on
%   its own. Only podId and stationBase are treated as reliable; the date is
%   returned for reporting and tie-breaking only.
%
%   Output table columns:
%       raw          original string
%       norm         separators normalised to single spaces
%       station      station token as written, e.g. "GB1A"
%       stationBase  station with trailing letters stripped, e.g. "GB1"
%       podId        numeric POD serial (NaN if absent)
%       fileNo       "fileNN" index (NaN if absent)
%       nameDate     datetime parsed from the yyyy mm dd triple (NaT if absent)
%
%   Part of the minICI back-fill toolset. Called by matchFilesToDeployments.

arguments
    names (:,1) string
end

n    = numel(names);
norm = regexprep(names, '[_\-\.]+', ' ');       % underscores/dashes -> space
norm = regexprep(norm, '\.csv$', '', 'ignorecase');
norm = strtrim(regexprep(norm, '\s+', ' '));

station     = strings(n,1);
stationBase = strings(n,1);
podId       = nan(n,1);
fileNo      = nan(n,1);
nameDate    = NaT(n,1);

for k = 1:n
    s = norm(k);

    % --- POD serial -------------------------------------------------------
    tok = regexp(s, 'POD\s*(\d+)', 'tokens', 'once', 'ignorecase');
    if ~isempty(tok)
        podId(k) = str2double(tok{1});
    end

    % --- file index -------------------------------------------------------
    tok = regexp(s, 'file\s*(\d+)', 'tokens', 'once', 'ignorecase');
    if ~isempty(tok)
        fileNo(k) = str2double(tok{1});
    end

    % --- embedded date ----------------------------------------------------
    tok = regexp(s, '(\d{4})\s(\d{1,2})\s(\d{1,2})', 'tokens', 'once');
    if ~isempty(tok)
        y = str2double(tok{1}); m = str2double(tok{2}); d = str2double(tok{3});
        if y >= 1990 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31
            nameDate(k) = datetime(y, m, d);
        end
    end

    % --- station: everything before the 4-digit year ----------------------
    tok = regexp(s, '^(.*?)\s\d{4}\s', 'tokens', 'once');
    if ~isempty(tok)
        station(k) = strtrim(string(tok{1}));
    else
        parts = split(s, ' ');
        station(k) = parts(1);
    end
    stationBase(k) = upper(regexprep(station(k), '[A-Za-z]+$', ''));
    if stationBase(k) == ""      % station was all letters, keep as-is
        stationBase(k) = upper(station(k));
    end
end

T = table(names, norm, upper(station), stationBase, podId, fileNo, nameDate, ...
    'VariableNames', {'raw','norm','station','stationBase','podId','fileNo','nameDate'});
end
