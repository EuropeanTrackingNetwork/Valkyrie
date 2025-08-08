% Ensure that both datetime and coordinates are in the correct format

function tbl = validateAndFormatMetadata(tbl)
    % Parse datetime fields
    tbl.DeploymentDateTime = datetime(tbl.DeploymentDateTime, 'InputFormat', '', 'TimeZone', 'UTC');
    tbl.RecoveryDateTime = datetime(tbl.RecoveryDateTime, 'InputFormat', '', 'TimeZone', 'UTC');

    % Validate coordinates
    if any(~isfinite(tbl.Latitude)) || any(~isfinite(tbl.Longitude))
        error('Invalid Latitude or Longitude values.');
    end
end
