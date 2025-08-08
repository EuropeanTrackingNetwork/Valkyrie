% Script to check if all required columns are present in the metadata table
function checkMetadataColumns(tbl, requiredCols)
    missing = requiredCols(~ismember(requiredCols, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error("Missing required columns: %s", strjoin(missing, ', '));
    end
end
