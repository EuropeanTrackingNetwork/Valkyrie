function rep = addMinICIToYearlyDataset(yearlyFile, minICIUpdatesFile, outFile, varargin)
%ADDMINICITOYEARLYDATASET Add a MIN_ICI column to an existing yearly DOI dataset file.
%
%   rep = addMinICIToYearlyDataset("NOVANA_dataset_2011.csv", "min_ici_updates.csv", ...
%       "NOVANA_dataset_2011_with_minici.csv")
%
%   For a whole folder of yearly files, use addMinICIToYearlyFolder, which
%   loads the lookup ONCE and reuses it across every year -- much faster than
%   calling this per file.
%
%   This does NOT generate the yearly file from scratch -- novana-bpm.csv does
%   not contain station/latitude/longitude/mooring_type/receiver/deploy_date_time/
%   recover_date_time/valid_data_until_datetime, so those columns cannot be
%   built here. This takes an EXISTING yearly file (produced by whatever
%   process already generates these for DOI purposes) and adds MIN_ICI to it;
%   every other column and value is passed through unchanged.
%
%   Structural notes about this format, different from every other deliverable
%   in this project
%   ------------------------------------------------------------------------
%   - ONE ROW PER MINUTE, not one per (minute, quality class) -- unlike
%     novana-bpm and everything derived from it in this toolset.
%   - 'quality' is numeric: 3=Hi, 2=Mod, 1=Lo, a FIXED mapping (confirmed by
%     the person running this, not inferred). Since it's fixed, knowing a
%     row's own quality number is enough to know which quality class's
%     min_ici to look up for it.
%   - Selective quoting: text columns quoted, numeric/date columns are not --
%     the OPPOSITE of novana-bpm.csv's quote-everything convention. MIN_ICI is
%     written unquoted, consistent with the other numeric columns here, empty
%     (not "NaN") where no value exists.
%   - A small fraction of 'time' values are date-only (e.g. "2011-06-29"
%     instead of a full timestamp) -- treated as midnight. Count reported.
%
%   - Deduplication: the underlying database has confirmed full-row
%     duplication for at least 3 deployments (found and verified earlier in
%     this project). Since the generator now covers ALL deployments, not just
%     the 174 this project specifically checked, duplicate rows are collapsed
%     generally here rather than only for the known cases -- 'Deduplicate'
%     (default true) removes exact full-row duplicates before the join, so
%     the yearly dataset is clean even where the database itself isn't.
%
%   PERFORMANCE: the join is fully vectorised (one ismember over string keys),
%   not a per-row map lookup. An earlier version looped over every row, which
%   at ~1M rows/year across many years was the dominant cost by a wide margin.
%   Deduplication uses MATLAB's built-in table row-uniqueness (unique(T,'rows')),
%   also vectorised, not a per-row comparison.
%
%   rep fields
%       totalRows, duplicateRowsRemoved, rowsFilled, dateOnlyTimeCount,
%       unmatchedQualityCodes, seconds
%
%   Options
%       'Lookup'       pre-built lookup struct from buildMinICILookup, to avoid
%                      re-reading min_ici_updates.csv for every year. When
%                      supplied, minICIUpdatesFile is ignored (pass "" for it).
%       'Deduplicate'  remove exact full-row duplicates before the join
%                      (default true)
%       'QualityMap'   Nx2 cell array overriding the default {3,"Hi";2,"Mod";1,"Lo"}
%       'Delimiter'    output delimiter (default ",")
%
%   Part of the minICI back-fill toolset.

opts = struct('Lookup', [], 'Deduplicate', true, 'QualityMap', [], 'Delimiter', ",");
opts = parseOpts(opts, varargin);
tStart = tic;

if isempty(opts.Lookup)
    L = buildMinICILookup(minICIUpdatesFile, opts.QualityMap);
else
    L = opts.Lookup;
end

%% ---- read the yearly file, preserving text exactly ----------------------
io = detectImportOptions(yearlyFile, 'TextType', 'string');
io.VariableTypes(:) = {'string'};   % preserve exact text; prevents numeric
                                     % auto-detection silently reformatting
                                     % values like 0.0 -> 0 on write-back
T = readtable(yearlyFile, io);

need = ["deployment_fk","time","quality"];
missingCols = setdiff(need, string(T.Properties.VariableNames));
if ~isempty(missingCols)
    error('addMinICIToYearlyDataset:badYearlyFile', ...
        '%s is missing column(s): %s.', yearlyFile, strjoin(missingCols, ', '));
end

nBeforeDedup = height(T);
if opts.Deduplicate
    T = unique(T, 'rows', 'stable');   % vectorised full-row uniqueness, not a loop
end
duplicateRowsRemoved = nBeforeDedup - height(T);

n = height(T);

% normalise time to a full timestamp for the join key, WITHOUT altering the
% original column that gets written back out
rawTime = T.time;
dateOnly = strlength(rawTime) == 10;
timeForKey = rawTime;
timeForKey(dateOnly) = rawTime(dateOnly) + " 00:00:00";

% quality number -> text, vectorised
qualNum  = double(T.quality);
qualText = strings(n,1);
[inMap, mapLoc] = ismember(qualNum, L.qualCodes);
qualText(inMap) = L.qualLabels(mapLoc(inMap));

%% ---- the join: one vectorised ismember, no per-row loop -----------------
key = T.deployment_fk + "|" + timeForKey + "|" + qualText;
[tf, loc] = ismember(key, L.keys);
tf = tf & inMap;          % a row with an unmapped quality code can't match

minIci = strings(n,1);
minIci(tf) = L.valueStrings(loc(tf));
T.MIN_ICI = minIci;

%% ---- write, matching this format's selective quoting -------------------
writeSelectiveQuoteCsv(outFile, T, L.textCols, opts.Delimiter);

%% ---- report -----------------------------------------------------------
rep = struct();
rep.totalRows             = n;
rep.duplicateRowsRemoved  = duplicateRowsRemoved;
rep.rowsFilled            = sum(tf);
rep.dateOnlyTimeCount     = sum(dateOnly);
rep.unmatchedQualityCodes = sum(~inMap);
rep.seconds               = toc(tStart);
end

% =======================================================================
function writeSelectiveQuoteCsv(outFile, T, textCols, delim)
cols = string(T.Properties.VariableNames);
isText = ismember(cols, textCols);

fid = fopen(outFile, 'w');
if fid < 0, error('Cannot open %s for writing', outFile); end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>

fwrite(fid, strjoin("""" + cols + """", delim) + newline, 'char');

n = height(T);
colStrs = strings(n, numel(cols));
for c2 = 1:numel(cols)
    v = T.(cols(c2));
    if ~isstring(v), v = string(v); end
    v(ismissing(v)) = "";
    if isText(c2)
        isEmpty = (v == "");
        q = """" + replace(v, """", """""") + """";
        q(isEmpty) = "";
        colStrs(:,c2) = q;
    else
        colStrs(:,c2) = v;   % numeric/date columns unquoted, matching this format
    end
end
rowStr = colStrs(:,1);
for c2 = 2:size(colStrs,2)
    rowStr = rowStr + delim + colStrs(:,c2);
end
fwrite(fid, strjoin(rowStr, newline) + newline, 'char');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.Delimiter = string(opts.Delimiter);
end