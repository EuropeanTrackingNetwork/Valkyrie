% Ensure that both datetime and coordinates are in the correct format
function [tbl, errorMsg] = validateMetadata(tbl, minDate,roles,DatetimeCols)
% This function assumes that all datetimes columns are in ISO-8601 format
% and that all field names have already been checked

% - Validates datetime fields compared to minDate and eachother.
% - Allows empty datetimes for NON-mandatory fields (no error).
% - Validates latitude/longitude ranges.
% - Aggregates per-row error messages; throws error if any issues.
%
% Inputs:
%   tbl            : table
%   minDate        : datetime (UTC)
%   roles          : struct mapping Role -> ColumnName (from JSON)
%   mandatoryFields: string/cell array of mandatory column names (upper)
%
% Output:
%   tbl       : table with datetime fields and coordinate fields
%   errorMsg  : kept for compatibility (empty string)

    errorMsg = "";
    allErrs = strings(0,1);

    
% 1) Check all datetime fields against minDate
    for f = 1:length(DatetimeCols)
        data = tbl.(DatetimeCols(f));
        bad  = data < minDate;

        if any(bad)
            idx = find(bad);
            for i = 1:numel(idx)
                allErrs(end+1) = sprintf("Row %d: %s is earlier than minDate.", ...
                                          idx(i), upper(f));
            end
        end
    end

    % --- 2) Cross-field ordering rules (using roles struct) ---
    deploy     = tbl.(roles.DeployDate);
    activate   = tbl.(roles.ActivationDate);
    recover    = tbl.(roles.RecoverDate);
    validUntil = tbl.(roles.ValidUntilDate);

    if any(deploy > recover)
        allErrs(end+1) = "Deployment date must be before recovery date.";
    end

    if any(activate > recover)
        allErrs(end+1) = "Activation date must be before recovery date.";
    end

    if any(activate > validUntil)
        allErrs(end+1) = "Activation date must be before valid until date.";
    end

    if any(deploy > validUntil)
        allErrs(end+1) = "Deployment date must be before valid until date.";
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
    
            % Change to numeric (double) after validation
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
