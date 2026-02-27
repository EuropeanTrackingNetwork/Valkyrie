
% checkMetadataColumns
% Validates and prepares metadata for export using JSON fields from the app:
%   - app.MandatoryFields : string/cell array of mandatory column names
%   - app.OutputOrder     : string/cell array of full export order (mandatory + optional)
%
% Behavior:
%   1) Column names are normalized to UPPER for matching.
%   2) Checks presence of all mandatory columns; errors if any are missing.
%   3) Checks mandatory columns have no empty values; errors if empties found.
%   4) Adds any missing NON-mandatory (optional) columns as empty strings (NaN if string and empty if datetime).
%   5) Reorders columns to exactly match app.OutputOrder.
%
% Returns:
%   tblOut : table ready for export (ordered, with optional columns added if needed)


function [tblOut, all_identical, uniqueProjects] = checkMetadataColumns(tbl, requiredCols, OutputOrder, DateTimeCols)


    emptyMarker = "Na";
    % Normalize names to upper for consistent matching
    tbl.Properties.VariableNames = upper(string(tbl.Properties.VariableNames));
    mandatory   = upper(string(requiredCols));
    outputOrder = upper(string(OutputOrder));
    DateTimeCols = upper(string(DateTimeCols));

    present = string(tbl.Properties.VariableNames);


    % --- 1) Mandatory presence ---
    % Is empty if all are there!
    missingMandatory = mandatory(~ismember(mandatory, present));

    % --- 2) Mandatory empty checks  ---
    % check that all mandatory columns have information in them
    emptyMandatory = strings(0,1);

    for i = 1:numel(mandatory)
        col = mandatory(i);
        if ismember(col, present)
                c = tbl.(col);
                
            if isstring(c) % if it is an empty string
                cc = strtrim(c);
                isEmpty = (cc == "" | ismissing(cc) | strcmpi(cc,"nan"));
            elseif iscellstr(c) % if it is an empty cell
                cc = strtrim(string(c));
                isEmpty = (cc == "" | ismissing(cc) | strcmpi(cc,"nan"));
            elseif iscell(c)
                isEmpty = false(size(c));
                for k = 1:numel(c)
                    v = c{k};
                    if ismissing(v)
                        isEmpty(k) = true;
                    elseif isstring(v) && (strlength(strtrim(v))==0 || strcmpi(strtrim(v),"nan"))
                        isEmpty(k) = true;
                    end
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

    % Throw errors if there are issues with the mandatory columsn
    issues = strings(0,1);
    if ~isempty(missingMandatory)
        issues(end+1) = "Missing mandatory columns: " + strjoin(missingMandatory, ', ');
    end

    if ~isempty(emptyMandatory)
        issues(end+1) = "Mandatory columns contain empty values: " + strjoin(emptyMandatory, ', ');
    end

    if ~isempty(issues)
        error(strjoin(issues, newline));
    end


    % ---- 3) Add missing NON-mandatory columns as empty (no error) ----
    present = string(tbl.Properties.VariableNames); %refreshes
    optional = setdiff(outputOrder, mandatory, 'stable');
    missingOptional = optional(~ismember(optional, present));

    for i = 1:numel(missingOptional)
        col = missingOptional(i);
        if ismember(col,DateTimeCols)
            tbl.(col) = NaT(height(tbl), 1); %empty datetime
        else
            tbl.(col) = repmat(emptyMarker, height(tbl), 1); % empty marker
        end
    end

    % ---- 4) Reorder to exact OutputOrder & drop extras ----
    %     % (All mandatory are present, optional now added as needed)
    tblOut = tbl(:, outputOrder);


   % --- 5) Standardise empty values in OPTIONAL columns that already exist ---
    for i = 1:numel(optional)
        col = optional(i);

        if ismember(col, DateTimeCols)
            % ensure empties are empty datetime
            if isdatetime(tblOut.(col))
                tblOut.(col)(ismissing(tblOut.(col))) = NaT;
            else
                % if it isn't datetime yet, leave type as-is, but make blanks truly missing
                x = string(tblOut.(col));
                x(strlength(strtrim(x))==0 | ismissing(x) | strcmpi(strtrim(x),"nan")) = missing;
                tblOut.(col) = x;  % writes blank cells in CSV
            end
        else
            % non-datetime: set empty/missing to "NaN"
            x = string(tblOut.(col));
            x(strlength(strtrim(x))==0 | ismissing(x)) = emptyMarker;
            tblOut.(col) = x;
        end
    end

    % --- 6) Check that all values in RCV_PROJECT are uniqe ---

    proj = string(tblOut.RCV_PROJECT);
    proj = strtrim(proj);
    
    % Treat blanks / missing / "NaN" as missing
    proj(strlength(proj)==0 | ismissing(proj) | strcmpi(proj,"nan")) = missing;
    
    uniqueProjects = unique(proj(~ismissing(proj)), 'stable');
    
    if isempty(uniqueProjects)
        error("RCV_PROJECT contains no valid values.");
    end
    
    all_identical = (isscalar(uniqueProjects));

end

