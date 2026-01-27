function filesTbl = createFileTable(filePaths)
% Fucntion that takes the filepaths of all selected files and transforms it
% into a table with only the files that are unique (if filename and byte
% size are the same only one pair of files are kept)

% Normalize to string column vector
filePaths = string(filePaths(:));

% === 2) Get info & deduplicate (keep uniques) ===
% Safer than cellfun(@dir,...) since dir on full file path returns scalar struct
info = arrayfun(@(fp) dir(fp), filePaths);
name = string({info.name})';
bytes = [info.bytes]';

% Build a robust signature for uniqueness (case-insensitive name + size)
sig = lower(name) + "|" + string(bytes);
[~, ia] = unique(sig, 'stable');

% Keep track of duplicates if you need them
%dupIdx = setdiff(1:numel(filePaths), ia);
%duplicateFiles = filePaths(dupIdx);

% Keep only uniques
uniqPaths  = filePaths(ia);
uniqNames  = name(ia);
uniqBytes  = bytes(ia);

% === 3) Build a mapping table we will reuse later ===
NameExt = uniqNames;                   % already "name.ext" from dir
FullPath = uniqPaths;
Bytes = uniqBytes;
filesTbl = table(FullPath, NameExt, Bytes);
end