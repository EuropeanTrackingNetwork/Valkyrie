function tbl = createDateTime(tbl, app.Config)

% Collapse date and time columns into ISO 8601 format
% YYYY-mm-ddThh:mm:ssZ

% Prefixes:
specNames = fieldnames(app.Config.MetadataSpec);
isDatetime = cellfun(@(f) isfield(app.Config.MetadataSpec.(f),'Type') && strcmpi(app.Config.MetadataSpec.(f).Type,'Datetime'), specNames); % columns of type Datetime from JSON file
prefixColumns = specNames(isDatetime);
prefixes = string(regexprep(prefixColumns, '^(.*?)(?:_DATE(?:_TIME)?)$', '$1_')); % remove everything after DATE, inclusively

suffixes = ["YEAR", "MONTH", "DAY", "TIME"];  % The four components

for p = prefixes(:).'
    % Build the expected full variable names
    yearVar  = p + suffixes(1);
    monthVar = p + suffixes(2);
    dayVar   = p + suffixes(3);
    timeVar  = p + suffixes(4); % optional

    % If any of these columns are missing from tbl, skip it-- handles optional columns
    if ~all(ismember([yearVar, monthVar, dayVar], tbl.Properties.VariableNames))
        continue 
    end

    % extract strings and zero‑pad MONTH, DAY
    y = string(tbl.(yearVar));
    m = compose("%02d", str2double(tbl.(monthVar)));
    d = compose("%02d", str2double(tbl.(dayVar)));

    hasTime = ismember(timeVar, tbl.Properties.VariableNames); % if it is just date or datetime

    if hasTime
        % Pad time when present
        t_raw = string(tbl.(timeVar));
        hourToken = extractBefore(t_raw, ":"); % Get everything before the first ":"
        needsPad = strlength(hourToken) == 1 & hourToken ~= ""; % Pad hour token if it is a single digit
        t_raw(needsPad) = "0" + t_raw(needsPad);
        t = t_raw;

        % Create ISO 8601 datetime
        dateStrings = y + "-" + m + "-" + d + "T" + t + "Z";
        outVar = p + "DATE_TIME";

        tbl(:, [yearVar, monthVar, dayVar, timeVar]) = []; % remove expanded columns
    else
        % Build date-only (no time)
        dateStrings = y + "-" + m + "-" + d;
        outVar = p + "DATE";

        tbl(:, [yearVar, monthVar, dayVar]) = []; % remove expanded columns
    end

    % put it into tbl, so it now matches the json config
    tbl.(outVar) = dateStrings;
end
