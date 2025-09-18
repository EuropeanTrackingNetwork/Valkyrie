% Ensure that both datetime and coordinates are in the correct format

function [tbl, errorMsg] = validateMetadata(tbl, minDate, roles, dtFormats)

    % Convert to string
    depField = roles.DeployDate;
    recField = roles.RecoverDate;
    latField = roles.Latitude;
    lonField = roles.Longitude;

    depStrs = string(tbl.(depField));
    recStrs = string(tbl.(recField));
    lats    = string(tbl.(latField));
    lons    = string(tbl.(lonField));

    % Use existing helper functions with arrayfun to check if datetime
    % format is correct
    [errDep, dtDep] = arrayfun(@(s) validateDatetime(s, minDate, dtFormats), depStrs, 'UniformOutput', false);
    [errRec, dtRec] = arrayfun(@(s) validateDatetime(s, minDate, dtFormats), recStrs, 'UniformOutput', false);
    dtDep = vertcat(dtDep{:});
    dtRec = vertcat(dtRec{:});

    % Use existing helper function to check if coordinates are in correct
    % format
    [errCoord] = arrayfun(@(lat,lon) validateCoordinates(lat,lon), lats, lons, 'UniformOutput', false);

    % Collect all error messages
    errorMsgs = [];
    for i = 1:height(tbl)
        if ~isempty(errDep{i})
            errorMsgs = [errorMsgs; "Row " + i + ": DeploymentDateTime - " + errDep{i}];
        end
        if ~isempty(errRec{i})
            errorMsgs = [errorMsgs; "Row " + i + ": RecoveryDateTime - " + errRec{i}];
        end
        if ~isempty(errCoord{i})
            errorMsgs = [errorMsgs; "Row " + i + ": " + errCoord{i}];
        end
    end

    if ~isempty(errorMsgs)
        error(strjoin(errorMsgs, newline));
    end

    % Replace validated columnsdep
    tbl.DeploymentDateTime = dtDep;
    tbl.RecoveryDateTime = dtRec;
end
