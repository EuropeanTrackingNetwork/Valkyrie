function UniquefileTbl = removeFileDuplicates(fileTbl, pairedFiles)
% Function to remove any duplicate files, where the base of the name are
% the same. This means that the station name, datetime and pod ID are
% identical, but something has been added to the end of the name, such as
% PART if the file has been cropped. 
% OBS: if what differs is the last part of file0, file 01, file 02, etc.
% then it is not duplicates but instead continued files from the same
% deployment. 

% Keep only the files that have been paired
mask = ismember(fileTbl.NameExt, pairedFiles);
T = fileTbl(mask, :);

% Run parser on filenames
P = parsePODFilenames(T.NameExt);

% Attach parsed fields
T.BaseKey   = P.BaseKey;
T.PairKey   = P.PairKey;
T.PodFamily = P.PodFamily;
T.ExtKind   = P.ExtKind;
T.HasPART   = P.HasPART;
T.HasSoft   = P.HasSoft;
T.NameScore = P.NameScore;

% Ensure Bytes column exists
if ~ismember("Bytes", T.Properties.VariableNames)
    T.Bytes = NaN(height(T),1);
end

% Sort rows in this order:
%   1) PairKey
%   2) NameScore  (lower = better filename)
%   3) Bytes      (higher = better file)
T = sortrows(T, ...
    {'PairKey','NameScore','Bytes'}, ...
    {'ascend','ascend','descend'});


% Keep one representative per pair key:
[~, ia] = unique(T.PairKey, 'stable');
UniquefileTbl = T(ia, :);

end