function rep = extractMinICIUpdates(bigCsv, X, outCsv, varargin)
%EXTRACTMINICIUPDATES Pass 2: turn matched minICI files into id_pk / min_ici rows.
%
%   rep = extractMinICIUpdates(bigCsv, X, 'min_ici_updates.csv')
%
%   bigCsv  the full detection export
%   X       crosswalk from matchFilesToDeployments (only status=="matched" is used)
%   outCsv  destination for the update file, written incrementally:
%
%       id_pk,min_ici,deployment_fk,datetime,quality,species,source_file,db_filename
%
%   Only rows that actually carry a min_ici are written -- roughly 2% of the
%   database, since min_ici exists only where number_clicks_filtered > 0. There
%   is nothing to send for the other 98%: they stay NULL.
%
%   Every written row is verified before it is written. number_clicks_filtered
%   and milliseconds must agree between the database row and the minICI row; a
%   disagreement means the crosswalk put the wrong file against the deployment,
%   and those rows are counted and sampled instead of silently written.
%
%   rep fields
%       .targetRows       min_ici values offered by the matched files
%       .written          rows written to outCsv
%       .unmatchedTargets min_ici values with no database row (should be 0)
%       .duplicateKeys    keys hitting more than one id_pk (should be 0)
%       .checkMismatch    rows rejected by the clicks/milliseconds check
%       .samples          example mismatches and unmatched targets
%       .perFile          per-source-file accounting
%
%   Part of the minICI back-fill toolset.

opts = struct('ReadSize', 200000, ...
    'DatetimeFormat', "yyyy-MM-dd HH:mm:ss", ...          % minICI output files
    'BigDatetimeFormat', "", ...                           % novana_bpm export;
    ...                                                     % "" = infer (unsafe for
    ...                                                     % ambiguous dates -- run
    ...                                                     % inspectBigFile first
    ...                                                     % and set explicitly)
    'BigDelimiter', "", ...                                % novana_bpm export; "" = auto
    'CheckColumns', ["number_clicks_filtered","milliseconds"], 'ProgressFcn', [], ...
    'UnmatchedCsv', "");
opts = parseOpts(opts, varargin);

M = X(X.status == "matched", :);
if isempty(M)
    error('extractMinICIUpdates:nothingMatched', 'No rows with status "matched" in the crosswalk.');
end

%% ---- build the target table from the matched output files -------------
tgtKey = strings(0,1); tgtVal = []; tgtChk = []; tgtSrc = strings(0,1); tgtDb = strings(0,1);
for k = 1:height(M)
    reportProgress(opts.ProgressFcn, 0.2*k/height(M), ...
        sprintf('Loading %d/%d: %s', k, height(M), M.newFilename(k)));

    io = detectImportOptions(M.file(k), 'TextType', 'string');
    want = intersect(["datetime","quality","species","min_ici", opts.CheckColumns], ...
        string(io.VariableNames), 'stable');
    io.SelectedVariableNames = cellstr(want);
    io = setvartype(io, {'min_ici'}, 'double');
    T = readtable(M.file(k), io);

    dt = T.datetime;
    if ~isdatetime(dt), dt = datetime(string(dt), 'InputFormat', char(opts.DatetimeFormat)); end

    keepRow = ~ismissing(T.min_ici) ...
        & upper(string(T.species)) == M.species(k) ...
        & dt >= M.dbFirst(k) & dt <= M.dbLast(k);

    if ~any(keepRow), continue, end
    tgtKey = [tgtKey; detectionKey(M.deployment_fk(k), dt(keepRow), T.quality(keepRow), T.species(keepRow))]; %#ok<AGROW>
    tgtVal = [tgtVal; T.min_ici(keepRow)];                       %#ok<AGROW>
    chk = nan(sum(keepRow), numel(opts.CheckColumns));
    for c = 1:numel(opts.CheckColumns)
        if ismember(opts.CheckColumns(c), string(T.Properties.VariableNames))
            chk(:,c) = double(T.(char(opts.CheckColumns(c)))(keepRow));
        end
    end
    tgtChk = [tgtChk; chk];                                      %#ok<AGROW>
    tgtSrc = [tgtSrc; repmat(M.file(k), sum(keepRow), 1)];        %#ok<AGROW>
    tgtDb  = [tgtDb;  repmat(M.dbFilename(k), sum(keepRow), 1)];  %#ok<AGROW>
end

if numel(unique(tgtKey)) ~= numel(tgtKey)
    error('extractMinICIUpdates:duplicateTargets', ...
        ['The matched files produce %d duplicate (deployment,datetime,quality,species) ' ...
         'keys. Two output files are mapped onto overlapping windows of the same ' ...
         'deployment -- fix the crosswalk first.'], numel(tgtKey) - numel(unique(tgtKey)));
end

hitCount   = zeros(numel(tgtKey),1);
depsInPlay = unique(M.deployment_fk);

%% ---- stream the big file ----------------------------------------------
fid = fopen(outCsv, 'w');
if fid < 0, error('extractMinICIUpdates:cannotWrite', 'Cannot open %s', outCsv); end
fprintf(fid, 'id_pk,min_ici,deployment_fk,datetime,quality,species,source_file,db_filename\n');
cleanup = onCleanup(@() fclose(fid));

dsArgs = {'TextType', 'string', 'ReadSize', opts.ReadSize};
if strlength(opts.BigDelimiter) > 0
    dsArgs = [dsArgs, {'Delimiter', char(opts.BigDelimiter)}];
end
ds = tabularTextDatastore(bigCsv, dsArgs{:});
want = ["id_pk","deployment_fk","datetime","species","quality", opts.CheckColumns];
missing = setdiff(want, string(ds.VariableNames));
if ~isempty(missing)
    error('extractMinICIUpdates:missingColumns', 'Column(s) not found: %s', strjoin(missing, ', '));
end
ds.SelectedVariableNames = cellstr(want);

written = 0; nMismatch = 0; nDup = 0; nInScopeClickPos = 0; chunkNo = 0;
mismatchSample = table();

while hasdata(ds)
    C = read(ds); chunkNo = chunkNo + 1;

    dep    = string(C.deployment_fk);
    inPlay = ismember(dep, depsInPlay);
    if ~any(inPlay)
        reportProgress(opts.ProgressFcn, NaN, sprintf('Chunk %d: no rows in scope', chunkNo));
        continue
    end
    C = C(inPlay,:); dep = dep(inPlay);

    dt = C.datetime;
    if ~isdatetime(dt)
        raw = string(C.datetime);
        if strlength(opts.BigDatetimeFormat) > 0
            dt = datetime(raw, 'InputFormat', char(opts.BigDatetimeFormat));
        else
            dt = datetime(raw);
        end
    end

    if chunkNo == 1
        raw = string(C.datetime);
        nonEmpty = strlength(strtrim(raw)) > 0;
        badFrac = sum(isnat(dt) & nonEmpty) / max(1, sum(nonEmpty));
        if badFrac > 0.01
            examples = raw(isnat(dt) & nonEmpty);
            error('extractMinICIUpdates:badDatetimeFormat', ...
                ['%.1f%% of datetimes in the first chunk of %s failed to parse. ' ...
                 'Run inspectBigFile(bigCsv) and pass its .dateOrderGuess as ' ...
                 '''BigDatetimeFormat'' explicitly. Example raw value(s): %s'], ...
                100*badFrac, bigCsv, strjoin(examples(1:min(5,numel(examples))), ', '));
        end
    end

    if ismember("number_clicks_filtered", opts.CheckColumns)
        nInScopeClickPos = nInScopeClickPos + sum(double(C.number_clicks_filtered) > 0);
    end

    k = detectionKey(dep, dt, C.quality, C.species);
    [tf, loc] = ismember(k, tgtKey);
    if ~any(tf)
        reportProgress(opts.ProgressFcn, NaN, sprintf('Chunk %d: 0 matches', chunkNo));
        continue
    end

    r = find(tf); t = loc(tf);
    hitCount(t) = hitCount(t) + 1;
    nDup = nDup + sum(hitCount(t) > 1);

    % verification: the database row and the minICI row must agree
    good = true(numel(r),1);
    for c = 1:numel(opts.CheckColumns)
        col = char(opts.CheckColumns(c));
        dbv = double(C.(col)(r));
        newv = tgtChk(t,c);
        cmp = dbv == newv | (isnan(dbv) & isnan(newv));
        good = good & cmp;
    end
    if any(~good)
        nMismatch = nMismatch + sum(~good);
        if height(mismatchSample) < 20
            s = find(~good); s = s(1:min(20-height(mismatchSample), numel(s)));
            mismatchSample = [mismatchSample; table(C.id_pk(r(s)), dep(r(s)), dt(r(s)), ...
                C.quality(r(s)), tgtSrc(t(s)), ...
                'VariableNames', {'id_pk','deployment_fk','datetime','quality','source_file'})]; %#ok<AGROW>
        end
    end

    r = r(good); t = t(good);
    for j = 1:numel(r)
        fprintf(fid, '%s,%.10g,%s,%s,%s,%s,%s,%s\n', ...
            C.id_pk(r(j)), tgtVal(t(j)), dep(r(j)), ...
            string(dt(r(j)), 'yyyy-MM-dd HH:mm:ss'), C.quality(r(j)), C.species(r(j)), ...
            tgtSrc(t(j)), tgtDb(t(j)));
    end
    written = written + numel(r);

    reportProgress(opts.ProgressFcn, NaN, ...
        sprintf('Chunk %d: %d matched (%d written so far)', chunkNo, numel(r), written));
end

%% ---- report ------------------------------------------------------------
rep = struct();
rep.targetRows       = numel(tgtKey);
rep.written          = written;
rep.unmatchedTargets = sum(hitCount == 0);
rep.duplicateKeys    = nDup;
rep.checkMismatch    = nMismatch;
rep.dbClickPositiveInScope = nInScopeClickPos;
rep.samples = struct('checkMismatch', mismatchSample, ...
    'unmatchedTargets', tgtKey(hitCount == 0));

src = unique(tgtSrc);
rep.perFile = table(src, ...
    arrayfun(@(s) sum(tgtSrc == s), src), ...
    arrayfun(@(s) sum(tgtSrc == s & hitCount > 0), src), ...
    'VariableNames', {'source_file','offered','matched'});

if strlength(opts.UnmatchedCsv) > 0 && rep.unmatchedTargets > 0
    writetable(table(tgtKey(hitCount == 0), tgtVal(hitCount == 0), tgtSrc(hitCount == 0), ...
        'VariableNames', {'key','min_ici','source_file'}), opts.UnmatchedCsv);
end

fprintf('\n=== min_ici extraction ===\n');
fprintf('min_ici values offered          : %d\n', rep.targetRows);
fprintf('rows written to %-15s : %d\n', outCsv, rep.written);
fprintf('offered but no database row     : %d   (must be 0)\n', rep.unmatchedTargets);
fprintf('keys hitting >1 id_pk           : %d   (must be 0)\n', rep.duplicateKeys);
fprintf('rejected by clicks/ms check     : %d   (must be 0)\n', rep.checkMismatch);
fprintf('click-positive db rows in scope : %d   (should equal rows written)\n', rep.dbClickPositiveInScope);
end

% =======================================================================
function k = detectionKey(dep, dt, quality, species)
k = string(dep) + "|" + string(dt, 'yyyy-MM-dd HH:mm:ss') + "|" + ...
    upper(string(quality)) + "|" + upper(string(species));
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.CheckColumns      = string(opts.CheckColumns);
opts.DatetimeFormat    = string(opts.DatetimeFormat);
opts.BigDatetimeFormat = string(opts.BigDatetimeFormat);
opts.BigDelimiter      = string(opts.BigDelimiter);
opts.UnmatchedCsv      = string(opts.UnmatchedCsv);
end

function reportProgress(fcn, frac, msg)
if isempty(fcn), return; end
try, fcn(frac, msg); catch, fprintf('%s\n', msg); end
end
