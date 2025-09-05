% Ensure that both datetime and coordinates are in the correct format

function tbl = validateMetadata(tbl, minDate)
    % Convert to string
    depStrs = string(tbl.DeploymentDateTime);
    recStrs = string(tbl.RecoveryDateTime);
    lats    = string(tbl.Latitude);
    lons    = string(tbl.Longitude);

    % Use existing helper functions with arrayfun to check if datetime
    % format is correct
    [errDep, dtDep] = arrayfun(@(s) validateDatetime(s, minDate), depStrs, 'UniformOutput', false);
    [errRec, dtRec] = arrayfun(@(s) validateDatetime(s, minDate), recStrs, 'UniformOutput', false);
    dtDep = vertcat(dtDep{:});
    dtRec = vertcat(dtRec{:});

    % Use existing helper function to check if coordinates are in correct
    % format
    [~, ~, errCoord] = arrayfun(@(lat,lon) validateCoordinates(lat,lon), lats, lons, 'UniformOutput', false);

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
        error(join(errorMsgs, newline));
    end

    % Replace validated columns
    tbl.DeploymentDateTime = dtDep;
    tbl.RecoveryDateTime = dtRec;
end
