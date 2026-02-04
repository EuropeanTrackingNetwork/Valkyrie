function [processTbl,metaAligned,processList] = buildProcessTbl(metaTbl,filtFiles,filesTbl)

%BUILDPROCESSTBL (Simplified) Create process table aligned to metadata rows.
% 
% Inputs:
%   metaTbl   : table with raw matched filenames per row.
%               Prefer column 'MatchingfilesRaw'; if missing, uses 'MatchingFiles'.
%   filtFiles : string/cellstr of selected filenames (basename+ext), e.g., CP3/FP3 subset.
%   filesTbl  : table with columns 'NameExt' (basename+ext) and 'FullPath'.
%
% Outputs:
%   processTbl  : table with columns:
%                 Path, FileName, FullPath, MetaRow (row in metaTbl)
%   processList : string array of FullPath, same order as processTbl.
%
% Notes:
%   - Preserves UI order from filtFiles.
%   - Matches filenames case-insensitively on basename+ext (no paths).
%   - If a file appears in multiple metadata rows, the first row wins.


    % ---- Choose raw matches column ----
    rawCol = 'MatchingfilesRaw';
    if ~ismember(rawCol, metaTbl.Properties.VariableNames)
        rawCol = 'MatchingFiles';
    end

    % ----- tiny helpers -----
    norm = @(s) lower(string(strtrim(s)));   % normalize names (basename+ext)
    % convert filtFiles to string vector (UI order preserved)
    if isstring(filtFiles)
        sel = filtFiles(:);
    elseif iscellstr(filtFiles)
        sel = string(filtFiles(:));
    else % char or other -> treat as scalar char
        sel = string({filtFiles});
    end
    procNames = norm(sel);  % UI order

    % ----- build filename -> metadata row map (first row wins) -----
    fileToMeta = containers.Map('KeyType','char','ValueType','int32');
    for r = 1:height(metaTbl)
        v = metaTbl.(rawCol){r};       % each row's list (string/cellstr/char)
        if isstring(v), v = cellstr(v(:)); end
        if ischar(v),   v = {v};       end
        % assume v is a cell now and non-empty due to pre-checks
        for k = 1:numel(v)
            key = char(norm(v{k}));
            if ~isKey(fileToMeta, key)
                fileToMeta(key) = int32(r);
            end
        end
    end

    % ----- map UI names -> FullPath via filesTbl (case-insensitive) -----
    tblNames = norm(filesTbl.NameExt(:));
    [~, loc] = ismember(procNames, tblNames);            % assumed all present
    fullPaths = string(filesTbl.FullPath(loc));

    % ----- compute MetaRow per processed file -----
    metaIdx = zeros(numel(procNames), 1, 'int32');
    for i = 1:numel(procNames)
        metaIdx(i) = fileToMeta(char(procNames(i)));
    end

    % ----- assemble outputs -----
    [folders, names, exts] = arrayfun(@fileparts, cellstr(fullPaths), 'UniformOutput', false);
    processTbl = table( ...
        string(folders), ...
        string(names) + string(exts), ...
        fullPaths, ...
        metaIdx, ...
        'VariableNames', {'Path','FileName','FullPath','MetaRow'} ...
    );

    metaAligned = metaTbl(metaIdx, :);
    processList = fullPaths;

end

