% Ensure that both datetime and coordinates are in the correct format
function [tbl, errorMsg] = validateMetadata(tbl, minDate, roles, dtFormats, mandatoryFields)
% - Validates datetime fields in roles using dtFormats and minDate.
% - Allows empty datetimes for NON-mandatory fields (no error).
% - Validates latitude/longitude ranges.
% - Aggregates per-row error messages; throws error if any issues.
%
% Inputs:
%   tbl            : table
%   minDate        : datetime (UTC)
%   roles          : struct mapping Role -> ColumnName (from JSON)
%   dtFormats      : cell array of input formats (from JSON)
%   mandatoryFields: string/cell array of mandatory column names (upper)
%
% Output:
%   tbl       : table with datetime fields normalized to UTC (ISO-8601 format for display)
%   errorMsg  : kept for compatibility (empty string)

    errorMsg = "";

    % Normalize inputs
    if ischar(mandatoryFields) || isstring(mandatoryFields)
        mandatoryFields = string(mandatoryFields);
    end
    mandatoryFields = upper(mandatoryFields);

    presentCols = string(tbl.Properties.VariableNames);
    presentColsU = upper(presentCols);

    % Helper to find actual table column name by case-insensitive match
    function nm = actualName(nameFromRoles)
        candU = upper(string(nameFromRoles));
        idx = find(presentColsU == candU, 1, 'first');
        if isempty(idx)
            nm = string.empty;
        else
            nm = presentCols(idx);
        end
    end

    % --- Datetime roles to validate ---
    dtRoleNames = {
        'DeployDate'
        'RecoverDate'
        'ActivationDate'
        'ValidUntilDate'
        'BatteryEndDate'
        'DownloadDate'
    };

    allErrs = strings(0,1);

    % Ensure dtFormats is a cellstr
    if isstring(dtFormats) || ischar(dtFormats)
        dtFormats = cellstr(dtFormats);
    end

    for r = 1:numel(dtRoleNames)
        roleName = dtRoleNames{r};
        if ~isfield(roles, roleName)
            continue; % role not used in this config
        end

        fieldName = actualName(roles.(roleName));
        if isempty(fieldName)
            continue; % column not present (likely optional and absent)
        end

        colMandatory = ismember(upper(fieldName), mandatoryFields);
        colData = tbl.(fieldName);

        % 1) If already datetime: set timezone + display format; validate minDate.
        if isdatetime(colData)
            if isempty(colData.TimeZone)
                colData.TimeZone = 'UTC';
            else
                colData.TimeZone = 'UTC'; % normalize to UTC per your config
            end
            colData.Format = "yyyy-MM-dd'T'HH:mm:ss'Z'";

            % Min date check
            bad = colData < minDate;
            if any(bad)
                idx = find(bad);
                for ii = 1:min(numel(idx), height(tbl))
                    allErrs(end+1) = "Row " + idx(ii) + ": " + upper(fieldName) + ...
                                     " - Date earlier than allowed minimum.";
                end
            end

            tbl.(fieldName) = colData;
            continue;
        end

        % 2) Otherwise, treat as text and parse row-wise
        svals = string(colData);
        n = numel(svals);
        parsed = NaT(n,1,'TimeZone','UTC');

        for i = 1:n
            s = strtrim(svals(i));

            % Allow empty if NOT mandatory
            if strlength(s) == 0 && ~colMandatory
                parsed(i) = NaT('TimeZone','UTC');
                continue;
            end

            [errStr, dt] = validateDatetime_amb(s, minDate, dtFormats);

            if ~isnat(dt)
                parsed(i) = dt; % already in UTC with ISO display
            end

            if strlength(errStr) > 0
                allErrs(end+1) = "Row " + i + ": " + upper(fieldName) + " - " + errStr;
            end
        end

        tbl.(fieldName) = parsed;
    end


    % --- Coordinates ---
    if isfield(roles, 'Latitude') && isfield(roles, 'Longitude')
        latField = actualName(roles.Latitude);
        lonField = actualName(roles.Longitude);
    
        if ~isempty(latField) && ~isempty(lonField)
            lats = string(tbl.(latField));
            lons = string(tbl.(lonField));
    
            errCoord = arrayfun(@(lat,lon) validateCoordinates(lat,lon), ...
                                lats, lons, 'UniformOutput', false);
    
            for i = 1:numel(errCoord)
                if ~isempty(errCoord{i})
                    allErrs(end+1) = "Row " + i + ": " + errCoord{i};
                end
            end
    
            % >>> NEW: coerce to numeric (double) after validation <<<
            latNum = str2double(lats);
            lonNum = str2double(lons);
            % Keep invalids as NaN (they will already have produced errors)
            tbl.(latField) = latNum;
            tbl.(lonField) = lonNum;
        end
    end


    % Throw aggregated error if any
    if ~isempty(allErrs)
        error(strjoin(allErrs, newline));
    end
end
