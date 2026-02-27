function cleanedMeta = CleanMetadata(metadata,OutputOrder,DatetimeCols)
%EXPORTCLEANMETADATA Create final metadata table for ETN upload
% Only able to add missing columns if they are not mandatory
% Missing datetime columns are added as NaT (empty datetime)
% Missing non-datetime columns are added as "NaN" strings

% Normalize inputs
DatetimeCols    = upper(string(DatetimeCols)); %only column names that are Type == Datetime
requiredCols = string(OutputOrder); % this will have ALL column names needed - and their correct order


% Normalize existing column names to uppercase
metadata.Properties.VariableNames = upper(string(metadata.Properties.VariableNames));


% Create export table in correct order
nRows = height(metadata);
exportTable = table();

% Reorder columns and add missing columns (non-mandatory cols only)
for i = 1:numel(requiredCols)
    colName = requiredCols(i); % the name of the columns recquired

    % If the current column name is a required column put it into the
    % export table
    if ismember(colName, metadata.Properties.VariableNames) 
        exportTable.(colName) = metadata.(colName);
    else
        
        % If the column is datetime and empty add NaT
        if ismember(colName, DatetimeCols)
            exportTable.(colName) = NaT(nRows, 1);      % empty datetime
        else
            % If the column is NOT datetime but empty add NaN
            exportTable.(colName) = repmat("NaN", nRows, 1); % empty string marker
        end

    end
end


% 2) NEW: Fill empty values even if columns already existed
for i = 1:numel(requiredCols)
    colName = requiredCols(i);
    x = exportTable.(colName);

    if ismember(colName, DatetimeCols)
        % Datetime: empty -> NaT
        if isdatetime(x)
            x(ismissing(x)) = NaT;
            exportTable.(colName) = x;
        else
            % If a datetime column isn't actually datetime (e.g., cell/string),
            % leave it as-is for your earlier datetime validation step.
            % But still clear empty strings to missing so writetable outputs blanks.
            xs = string(x);
            xs(strlength(strtrim(xs))==0 | ismissing(xs) | strcmpi(strtrim(xs),"nan")) = missing;
            exportTable.(colName) = xs;  % will write blanks in CSV
        end

    else
        % Non-datetime: empty -> "NaN"
        xs = string(x);  % works for cellstr, char, numeric, string
        xs(strlength(strtrim(xs))==0 | ismissing(xs)) = "NaN";
        exportTable.(colName) = xs;
    end
end


cleanedMeta = exportTable;
end



