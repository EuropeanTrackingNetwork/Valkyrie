% Ensure that both datetime and coordinates are in the correct format
function [tbl, errorMsg] = validateMetadata(tbl, minDate, roles, dtFormats)
%VALIDATEMETADATA Validate datetime and coordinate fields in metadata table

    % --- Datetime fields you want to validate ---
    dtRoleNames = {
        'DeployDate'
        'RecoverDate'
        'ActivationDate'
        'ValidUntilDate'
        'BatteryEndDate'
        'DownloadDate'
    };

    % Storage for errors
    allErrs = strings(0,1);

    % --- Loop over datetime roles ---
    for r = 1:numel(dtRoleNames)
        roleName = dtRoleNames{r};
        fieldName = roles.(roleName);

        % Convert to string for validation
        strs = string(tbl.(fieldName));

        % Validate each entry
        [errCell, dt] = arrayfun(@(s) validateDatetime_amb(s, minDate, dtFormats), ...
                             strs, 'UniformOutput', false);

        % Collect results
        tbl.(fieldName) = vertcat(dt{:});

        % Gather error messages

        errStr = vertcat(errCell{:});   % string array
        for i = 1:numel(errCell)
            if strlength(errStr) > 0
                allErrs(end+1) = "Row " + i + ": " + fieldName + " - " + err{i};
            end
        end
    end

    % --- Coordinates (special case with two fields) ---
    latField = roles.Latitude;
    lonField = roles.Longitude;

    lats = string(tbl.(latField));
    lons = string(tbl.(lonField));

    errCoord = arrayfun(@(lat,lon) validateCoordinates(lat,lon), ...
                        lats, lons, 'UniformOutput', false);

    for i = 1:numel(errCoord)
        if ~isempty(errCoord{i})
            allErrs(end+1) = "Row " + i + ": " + errCoord{i};
        end
    end

    % --- Throw error if any found ---
    if ~isempty(allErrs)
        error(strjoin(allErrs,newline));
    end

    errorMsg = ''; % for compatibility
end
