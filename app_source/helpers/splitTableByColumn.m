function savedNames = splitTableByColumn(tbl, splitCol, outFolder, filePrefix, app)
%SPLITTABLEBYCOLUMN  Write one CSV per unique value of tbl.(splitCol).
%   Handles the split column being a cell array of char, string array,
%   categorical, or numeric - unique()/comparison logic differs slightly
%   between these so it's handled explicitly rather than assuming one type.

colData = tbl.(splitCol);


groupVals = unique(colData);


nGroups = numel(groupVals);
savedNames = strings(nGroups,1);

for i = 1:nGroups
    if iscell(groupVals)
        val    = groupVals{i};
        mask   = strcmp(colData, val);
        valStr = val;
    else
        val = groupVals(i);
        mask = colData == val;
        if isstring(val) || ischar(val)
            valStr = char(val);
        else
            valStr = num2str(val);
        end
    end

    subset = tbl(mask, :);

    % Sanitise value for use as a filename
    safeName = regexprep(valStr, '[^\w\-]', '_');
    safeName = regexprep(safeName, '_+', '_');

    outName = [filePrefix safeName '.csv'];
    savedNames(i) = outName;

    if nargin > 4 && ~isempty(app)
        app.ProcessingMessage.Value = sprintf('Saving detections file %d of %d...', i, nGroups);
        drawnow;
    end

    writetable(subset, fullfile(outFolder, outName));
end
end