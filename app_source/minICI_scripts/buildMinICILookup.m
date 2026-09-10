function L = buildMinICILookup(minICIUpdatesFile, qualityMap)
%BUILDMINICILOOKUP Build the min_ici join lookup once, for reuse across years.
%
%   L = buildMinICILookup("min_ici_updates.csv")
%   L = buildMinICILookup("min_ici_updates.csv", {3,"Hi";2,"Mod";1,"Lo"})
%
%   Reading and key-building min_ici_updates.csv is pure overhead if repeated
%   per yearly file, so addMinICIToYearlyFolder does it once via this and
%   passes the result through 'Lookup'.
%
%   The value strings are pre-formatted here rather than at join time, so the
%   per-year work is just an ismember plus an indexed assignment.
%
%   L fields
%       keys          "deployment_fk|yyyy-MM-dd HH:mm:ss|QUALITYTEXT"
%       valueStrings  the min_ici values, already formatted for output
%       qualCodes     numeric quality codes (default [3 2 1])
%       qualLabels    matching text labels (default ["Hi" "Mod" "Lo"])
%       textCols      which yearly-file columns get quoted on write
%
%   Part of the minICI back-fill toolset.

if nargin < 2 || isempty(qualityMap)
    qualityMap = {3,"Hi"; 2,"Mod"; 1,"Lo"};   % FIXED mapping, confirmed
end

U = readtable(minICIUpdatesFile, 'TextType', 'string');
need = ["deployment_fk","datetime","quality","min_ici"];
missingCols = setdiff(need, string(U.Properties.VariableNames));
if ~isempty(missingCols)
    error('buildMinICILookup:badUpdatesFile', ...
        'minICIUpdatesFile is missing column(s): %s. Is this extractMinICIUpdates'' output?', ...
        strjoin(missingCols, ', '));
end

L = struct();
L.keys = string(U.deployment_fk) + "|" + string(U.datetime) + "|" + string(U.quality);

vals = double(U.min_ici);
L.valueStrings = strings(numel(vals),1);
ok = ~isnan(vals);
L.valueStrings(ok) = compose("%.10g", vals(ok));   % pre-format once, not per year

L.qualCodes  = cell2mat(qualityMap(:,1));
L.qualLabels = string(qualityMap(:,2));

% text columns in the yearly DOI format -- these get quoted on write, the
% rest are written bare, matching that format's selective-quoting convention
L.textCols = ["species","projectcode","projectname","station","mooring_type","receiver"];

% duplicate keys would make the join ambiguous; extractMinICIUpdates already
% guarantees uniqueness per (deployment_fk,datetime,quality), so this is a
% cheap assertion rather than an expected condition
if numel(unique(L.keys)) ~= numel(L.keys)
    warning('buildMinICILookup:duplicateKeys', ...
        ['%d duplicate key(s) in the update file -- ismember will take the first ' ...
         'match for each. Check extractMinICIUpdates output.'], ...
         numel(L.keys) - numel(unique(L.keys)));
end
end