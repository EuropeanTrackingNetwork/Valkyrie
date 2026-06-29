function [UniquefileTbl, removedFiles, stationConflicts] = removeFileDuplicates(fileTbl, pairedFiles)
% Function to remove any duplicate files, where the base of the name are
% the same. This means that the station name, datetime and pod ID are
% identical, but something has been added to the end of the name, such as
% PART if the file has been cropped.
% OBS: if what differs is the last part of file0, file 01, file 02, etc.
% then it is not duplicates but instead continued files from the same
% deployment.

% Input:
% the table with a column with FilePaths and NameExt and Bytes
% a list of all the files that belong to a filepair

% Output:
% UniqueFileTbl     : table of kept rows (paired CP/FP 1 & 3 from best variant).
% removedFiles      : table of excluded rows with reason codes and details.
% stationConflicts  : string array of warnings where the same recording
%                     appears under different station name prefixes.
%                     Empty if no conflicts found.

arguments
    fileTbl table
    pairedFiles {mustBeVector} = []
end

% Keep only the files that have been paired
% OBS: this will remove duplicates of the exact same name even if they
% appear across several folders
mask = ismember(string(fileTbl.NameExt), string(pairedFiles));
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

% === Build keys for pair-level deduplication ===

% Extract station prefix: everything before the first space in the filename.
% This prevents files from different stations (e.g. GB4C vs KALF3B) being
% treated as duplicates just because they share the same POD ID and date.
% Lowercased for case-insensitive grouping.
stationPrefix = lower(regexprep(string(T.NameExt), '\s.*$', ''));

% Group of logical pair (ignoring kind 1 vs 3).
% Station prefix is included so GB4C_20120211_1690_01_CP and
% KALF3B_20120211_1690_01_CP are treated as separate groups and neither
% is silently discarded in favour of the other.
T.PairGroupKey = stationPrefix + "_" + T.BaseKey + "_" + T.PodFamily;

% === Warn about cross-station conflicts ===
% If the same BaseKey+PodFamily appears under more than one station prefix,
% the data may be duplicated across differently-named deployments.
% We warn rather than silently discard, since this requires human judgement.
baseGroupKey = T.BaseKey + "_" + T.PodFamily;   % key without station prefix
[~, ~, bgIdx] = unique(baseGroupKey, 'stable');

stationConflicts = strings(0,1);
for g = 1:max(bgIdx)
    rows = find(bgIdx == g);
    prefixes = unique(stationPrefix(rows), 'stable');
    if numel(prefixes) > 1
        stationConflicts(end+1) = strjoin(prefixes, ' / ') + ...
            "  →  " + baseGroupKey(rows(1));
    end
end

if ~isempty(stationConflicts)
    warning(['Possible duplicate recordings under different station names:\n' ...
             repmat('  %s\n', 1, numel(stationConflicts))], ...
             stationConflicts{:});
end

% Variant stem = filename without the trailing ".CP1/.CP3/.FP1/.FP3"
stem = regexprep(string(T.NameExt), '\.(?:CP|FP)[13]$', '', 'ignorecase');
T.PairVariantKey = stem + "_" + T.PodFamily;

% --- Quality metrics per VARIANT (must keep 1 and 3 together) ---
Gv = findgroups(T.PairVariantKey);

% Count how many files per variant
nInVariant = splitapply(@numel, T.NameExt, Gv);

% Ensure both kinds (1 and 3) exist within the variant
hasKinds = splitapply(@(k) all(ismember(["1","3"], unique(string(k)))), T.ExtKind, Gv);

% Pair-level score = sum of NameScore across the two files (lower is better)
sumScore = splitapply(@sum, T.NameScore, Gv);

% Tie-breakers at pair level
sumBytes = splitapply(@(x) sum(x, 'omitnan'), T.Bytes, Gv);           % higher is better
minScore = splitapply(@(x) min(x, [], 'omitnan'), T.NameScore, Gv);   % lower is better

% Tiebreak based on alphabetical earliest name (purely cosmetic)
firstName = splitapply(@(x) string(x(find(~cellfun(@isempty, x), 1, 'first'))), ...
    cellstr(T.NameExt), Gv);

% Carry one representative row index per variant group (for keys)
repIdx = splitapply(@(idx) idx(1), (1:height(T))', Gv);

% Build variant table (each row is one file pair)
Vfull = table( ...
    T.PairVariantKey(repIdx), T.PairGroupKey(repIdx), ...
    nInVariant, hasKinds, sumScore, sumBytes, minScore, firstName, ...
    'VariableNames', ...
    {'PairVariantKey','PairGroupKey','N','HasKinds','SumScore','SumBytes','MinScore','FirstName'} ...
    );

% --- Choose the best variant per PairGroupKey (only among valid 1&3 variants) ---
Vsel = Vfull(Vfull.HasKinds & Vfull.N >= 2, :);

% Sort by quality:
%   1) lower SumScore is better (sum of name scores for the pair)
%   2) higher SumBytes is better (keep the file with most data)
%   3) lower MinScore is better (minimum name score of the pair)
%   4) FirstName alphabetical (stable cosmetic tiebreak)
Vsel = sortrows(Vsel, ...
    {'PairGroupKey','SumScore','SumBytes','MinScore','FirstName'}, ...
    {'ascend'      ,'ascend'  ,'descend' ,'ascend'  ,'ascend'});

% Pick best per group
[~, iaBest] = unique(Vsel.PairGroupKey, 'stable');
bestVariantKeys = Vsel.PairVariantKey(iaBest);

% Keep rows belonging to the winning variant(s) with ext-kind 1 or 3
isKind13  = ismember(T.ExtKind, ["1","3"]);
keepMask  = ismember(T.PairVariantKey, bestVariantKeys) & isKind13;
Out       = T(keepMask, :);

% Final sort
Out = sortrows(Out, {'PairGroupKey','ExtKind','NameScore','Bytes'}, ...
    {'ascend'      ,'ascend' ,'ascend'   ,'descend'});

% === Build 'removedFiles' report ===
Rem = T(~keepMask, :);

% Join variant metrics onto removed rows
Rem = outerjoin(Rem, Vfull, ...
    'Keys', {'PairVariantKey','PairGroupKey'}, ...
    'Type', 'left', ...
    'MergeKeys', true);

% Also join best metrics per PairGroupKey for explanation
B = Vsel(iaBest, :);
B.Properties.VariableNames = {'PairVariantKey_Best','PairGroupKey','Best_N','Best_HasKinds', ...
    'Best_SumScore','Best_SumBytes','Best_MinScore','Best_FirstName'};
B.BestVariantName = regexprep(string(B.PairVariantKey_Best), '_(?:CP|FP)$', '', 'ignorecase');
Rem = outerjoin(Rem, B, 'Keys', 'PairGroupKey', ...
    'Type', 'left', 'MergeKeys', true);

% Reason codes
invalidExt = ~(Rem.ExtKind == "1" | Rem.ExtKind == "3");
notPair13  = ~invalidExt & (Rem.HasKinds == 0 | Rem.N < 2);
worseVar   = ~invalidExt & ~notPair13;

Reason = strings(height(Rem),1);
Reason(invalidExt) = "INVALID_EXTKIND";
Reason(notPair13)  = "NOT_PAIR_13";
Reason(worseVar)   = "WORSE_VARIANT";

% ReasonDetail strings
ReasonDetail = strings(height(Rem),1);

ReasonDetail(invalidExt) = "Extension kind not recognized as '1' or '3'.";

idxNP = find(notPair13);
for k = idxNP(:)'
    ReasonDetail(k) = sprintf('Variant lacks both kinds (N=%d, HasKinds=%d).', ...
        safeInt(Rem.N(k)), safeInt(Rem.HasKinds(k)));
end

idxWV = find(worseVar);
for k = idxWV(:)'
    ReasonDetail(k) = sprintf(['Dedup by pair: this variant SumScore=%g, SumBytes=%g, MinScore=%g; ' ...
        'best variant "%s" SumScore=%g, SumBytes=%g, MinScore=%g.'], ...
        safeNum(Rem.SumScore(k)), safeNum(Rem.SumBytes(k)), safeNum(Rem.MinScore(k)), ...
        char(Rem.BestVariantName(k)), ...
        safeNum(Rem.Best_SumScore(k)), safeNum(Rem.Best_SumBytes(k)), safeNum(Rem.Best_MinScore(k)));
end

% Assemble removedFiles report table
removedFiles = table( ...
    Rem.FullPath, Rem.NameExt, Rem.PodFamily, Rem.ExtKind, ...
    Rem.PairGroupKey, Rem.PairVariantKey, ...
    Rem.NameScore, Rem.Bytes, ...
    Rem.N, Rem.HasKinds, Rem.SumScore, Rem.SumBytes, Rem.MinScore, ...
    Rem.BestVariantName, Rem.Best_SumScore, Rem.Best_SumBytes, Rem.Best_MinScore, ...
    Reason, ReasonDetail, ...
    'VariableNames', { ...
        'FullPath','NameExt','PodFamily','ExtKind', ...
        'PairGroupKey','PairVariantKey', ...
        'NameScore','Bytes', ...
        'VariantN','VariantHasKinds','VariantSumScore','VariantSumBytes','VariantMinScore', ...
        'BestVariantName','BestSumScore','BestSumBytes','BestMinScore', ...
        'Reason','ReasonDetail' ...
    });

UniquefileTbl = Out;

end


% --- local helpers ---
function v = safeNum(x)
if isempty(x) || isnan(x), v = NaN; else, v = x; end
end
function v = safeInt(x)
if isempty(x) || isnan(x), v = 0; else, v = x; end
end
