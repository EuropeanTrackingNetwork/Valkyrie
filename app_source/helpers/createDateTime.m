
function tbl = createDateTime(tbl, Config)
 
% Collapse date and time columns into ISO 8601 format
% YYYY-mm-ddThh:mm:ssZ
 
    % --- Input guards -----------------------------------------------------
    if ~istable(tbl)
        error('createDateTime:badTable', ...
            'Internal error: the metadata was not read as a table.');
    end
 
    if ~isstruct(Config) || ~isscalar(Config) || ~isfield(Config, 'MetadataSpec') ...
            || ~isstruct(Config.MetadataSpec)
        error('createDateTime:badConfig', ...
            ['The app configuration (metadata_validation.json) was not loaded, ' ...
             'so the metadata cannot be checked.\nPlease restart VALKYRIE. ' ...
             'If the problem persists, send the session log to the developers.']);
    end
 
% Prefixes:
specNames = fieldnames(Config.MetadataSpec);
isDatetime = cellfun(@(f) isfield(Config.MetadataSpec.(f),'Type') && strcmpi(Config.MetadataSpec.(f).Type,'Datetime'), specNames); % columns of type Datetime from JSON file
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
 
    % extract strings and zero-pad MONTH, DAY
    y = string(tbl.(yearVar));
    m = compose("%02d", str2double(tbl.(monthVar)));
    d = compose("%02d", str2double(tbl.(dayVar)));
 
    hasTime = ismember(timeVar, tbl.Properties.VariableNames); % if it is just date or datetime
 
    if hasTime
        % Pad time when present
        t_raw = string(tbl.(timeVar));
 
        % Add 0 to hour if needed
        hourToken = extractBefore(t_raw, ":"); % Get everything before the first ":"
        needsHourPad = strlength(hourToken) == 1 & hourToken ~= ""; % Pad hour token if it is a single digit
        t_raw(needsHourPad) = "0" + t_raw(needsHourPad);
 
        % Add seconds if missing
        % % Counts the colons; "HH:mm" has 1 and "HH:mm:ss" has 2
        cCount = count(t_raw, ":");
        needsSecPad = cCount == 1;
        t_raw(needsSecPad) = t_raw(needsSecPad)+":00";
 
        % final padded time
        t = t_raw;
 
        % Create ISO 8601 datetime
        dateStrings = y + "-" + m + "-" + d + "T" + t + "Z";
        outVar = p + "DATE_TIME";
 
        dateTime = localToDatetime(dateStrings, outVar);
 
        tbl(:, [yearVar, monthVar, dayVar, timeVar]) = []; % remove expanded columns
 
    else
        % Build date-only (no time)
        dateStrings = y + "-" + m + "-" + d + "T00:00:00Z";
        outVar = p + "DATE";
 
        dateTime = localToDatetime(dateStrings, outVar);
 
        tbl(:, [yearVar, monthVar, dayVar]) = []; % remove expanded columns
 
    end
 
    % put it into tbl, so it now matches the json config
    tbl.(outVar) = dateTime;
end
 
end
 
 
function dt = localToDatetime(dateStrings, columnLabel)
% Convert the assembled ISO strings, and report WHICH rows are unusable
% rather than failing with an opaque conversion error.
 
    try
        dt = datetime(dateStrings, "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'", "TimeZone", "UTC");
    catch
        dt = NaT(numel(dateStrings), 1, 'TimeZone', 'UTC');
        for k = 1:numel(dateStrings)
            try
                dt(k) = datetime(dateStrings(k), "InputFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'", "TimeZone", "UTC");
            catch
                % leave as NaT, reported below
            end
        end
    end
 
    bad = isnat(dt) & ~ismissing(dateStrings) & strlength(dateStrings) > 0 ...
        & ~contains(dateStrings, "NaN", 'IgnoreCase', true);
 
    if any(bad)
        idx = find(bad);
        nShow = min(numel(idx), 10);
        detail = compose("  row %d: %s", idx(1:nShow), dateStrings(idx(1:nShow)));
        more = "";
        if numel(idx) > nShow
            more = newline + sprintf("  ... and %d more row(s)", numel(idx) - nShow);
        end
        error('createDateTime:badDatetime', ...
            "%s could not be built for %d row(s). Expected YEAR, MONTH, DAY (and TIME as HH:mm or HH:mm:ss):%s%s%s", ...
            columnLabel, numel(idx), newline, strjoin(detail, newline), more);
    end
end