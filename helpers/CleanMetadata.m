function cleanedMeta = CleanMetadata(metadata,OutputOrder)
%EXPORTCLEANMETADATA Create final metadata table for ETN upload

requiredCols = string(OutputOrder);


% Normalize existing column names to uppercase
metadata.Properties.VariableNames = upper(string(metadata.Properties.VariableNames));

% Create export table in correct order
exportTable = table();
for i = 1:numel(requiredCols)
    colName = requiredCols(i);
    if ismember(colName, metadata.Properties.VariableNames)
        exportTable.(colName) = metadata.(colName);
    else
        % Add empty column if missing
        exportTable.(colName) = repmat({''}, height(metadata), 1);
    end
end

cleanedMeta = exportTable;
end



