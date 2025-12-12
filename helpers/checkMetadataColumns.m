
% checkMetadataColumns
% Validates and prepares metadata for export using JSON fields from the app:
%   - app.MandatoryFields : string/cell array of mandatory column names
%   - app.OutputOrder     : string/cell array of full export order (mandatory + optional)
%
% Behavior:
%   1) Column names are normalized to UPPER for matching.
%   2) Checks presence of all mandatory columns; errors if any are missing.
%   3) Checks mandatory columns have no empty values; errors if empties found.
%   4) Adds any missing NON-mandatory (optional) columns as empty strings.
%   5) Reorders columns to exactly match app.OutputOrder.
%
% Returns:
%   tblOut : table ready for export (ordered, with optional columns added if needed)


function tblOut = checkMetadataColumns(tbl, requiredCols, OutputOrder)


    % Normalize names to upper for consistent matching
    tbl.Properties.VariableNames = upper(string(tbl.Properties.VariableNames));
    mandatory   = upper(string(requiredCols));
    outputOrder = upper(string(OutputOrder));

    present = string(tbl.Properties.VariableNames);


    % --- 1) Mandatory presence ---
    % empty if all are there!
    missingMandatory = mandatory(~ismember(mandatory, present));


    % --- 2) OutputOrder presence + exact order ---
    missingOrderCols = outputOrder(~ismember(outputOrder, present));


    % --- 3) Mandatory empty checks (no type parsing here) ---
    emptyMandatory = strings(0,1);
    for i = 1:numel(mandatory)
        col = mandatory(i);
        if ismember(col, present)
                c = tbl.(col);
            if isstring(c)
                isEmpty = (c == "" | ismissing(c));
            elseif iscellstr(c)
                isEmpty = cellfun(@(x) isempty(x), c);
            elseif iscell(c)
                isEmpty = false(size(c));
                for k = 1:numel(c)
                    v = c{k};
                    isEmpty(k) = (ismissing(v) || (ischar(v) && isempty(v)));
                end
            elseif isnumeric(c)
                isEmpty = isnan(c);
            elseif isdatetime(c)
                isEmpty = isnat(c);
            else
                isEmpty = ismissing(c);
            end
            if any(isEmpty)
                emptyMandatory(end+1) = col;
            end
        end
    end

    issues = strings(0,1);
    if ~isempty(missingMandatory)
        issues(end+1) = "Missing mandatory columns: " + strjoin(missingMandatory, ', ');
    end
    if ~isempty(missingOrderCols)
        issues(end+1) = "Missing OutputOrder columns: " + strjoin(missingOrderCols, ', ');
    end
    if ~isempty(emptyMandatory)
        issues(end+1) = "Mandatory columns contain empty values: " + strjoin(emptyMandatory, ', ');
    end

    if ~isempty(issues)
        error(strjoin(issues, newline));
    end


    % ---- 4) Add missing NON-mandatory columns as empty (no error) ----
    optional = setdiff(outputOrder, mandatory, 'stable');
    missingOptional = optional(~ismember(optional, present));
    for i = 1:numel(missingOptional)
        % Add empty string column with correct height
        tbl.(missingOptional(i)) = repmat("", height(tbl), 1);
    end

    % ---- 5) Reorder to exact OutputOrder & drop extras ----
    %     % (All mandatory are present, optional now added as needed)
    tblOut = tbl(:, outputOrder);

end
