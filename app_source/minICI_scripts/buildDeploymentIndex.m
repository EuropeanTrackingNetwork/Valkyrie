function idx = buildDeploymentIndex(bigCsv, varargin)
%BUILDDEPLOYMENTINDEX Pass 1 over the full detection CSV: one row per source file.
%
%   idx = buildDeploymentIndex(bigCsv)
%   idx = buildDeploymentIndex(bigCsv, 'SaveTo','deployment_index.mat', ...
%                                      'ReadSize',200000, 'ProgressFcn',@(f,m)disp(m))
%
%   Streams the 13 GB export in chunks and reduces it to a compact index --
%   typically a few thousand rows -- which is what every later step joins against.
%   Nothing downstream ever needs to touch the big file again except the final
%   id_pk extraction pass.
%
%   Index columns
%       deployment_fk
%       dbFilename        detections_file_train_duration_filename
%       species
%       nRows             database rows for this file+species
%       nClickPositive    rows with number_clicks_filtered > 0
%                         (== the number of min_ici values this file must receive)
%       nMinICIAlready    rows that already carry a non-null min_ici
%       firstDatetime / lastDatetime
%       podId, station, stationBase, nameDate   (parsed from dbFilename)
%
%   Options
%       'SaveTo'        path for a .mat (and matching .csv) copy of the index
%       'ReadSize'      rows per chunk (default 200000)
%       'FilenameVar'   which filename column to index (default
%                       'detections_file_train_duration_filename')
%       'DatetimeFormat' input format of the datetime column, e.g. 'M/d/yyyy
%                       HH:mm' or 'yyyy-MM-dd HH:mm:ss'. Default "" lets MATLAB
%                       infer it, which is NOT safe for day/month-ambiguous
%                       dates -- run inspectBigFile(bigCsv) first and pass its
%                       .dateOrderGuess explicitly rather than relying on
%                       inference or on a format seen through Excel, which
%                       reformats dates to your locale's display and cannot be
%                       trusted as the on-disk format.
%       'Delimiter'     field delimiter. Default "" lets the datastore
%                       auto-detect it; set explicitly only if
%                       inspectBigFile(bigCsv) disagrees with auto-detection.
%       'ProgressFcn'   handle called as fcn(fractionOrNaN, message)
%
%   The first chunk is checked for unparseable datetimes and the function
%   errors out immediately if more than 1% fail, rather than silently dropping
%   rows -- a wrong 'DatetimeFormat' should never pass quietly.
%
%   Part of the minICI back-fill toolset.

opts = struct('SaveTo', "", 'ReadSize', 200000, ...
    'FilenameVar', "detections_file_train_duration_filename", ...
    'DatetimeFormat', "", 'Delimiter', "", 'ProgressFcn', []);
opts = parseOpts(opts, varargin);

fnVar = char(opts.FilenameVar);

dsArgs = {'TextType', 'string', 'ReadSize', opts.ReadSize};
if strlength(opts.Delimiter) > 0
    dsArgs = [dsArgs, {'Delimiter', char(opts.Delimiter)}];
end
ds = tabularTextDatastore(bigCsv, dsArgs{:});
want = {'deployment_fk','datetime','species','number_clicks_filtered','min_ici', fnVar};
missing = setdiff(want, ds.VariableNames);
if ~isempty(missing)
    error('buildDeploymentIndex:missingColumns', ...
        'Column(s) not found in %s: %s', bigCsv, strjoin(missing, ', '));
end
ds.SelectedVariableNames = want;

totalBytes = max(1, getfield(dir(bigCsv), 'bytes'));   %#ok<GFLD>
acc = table();
seenBytes = 0; chunkNo = 0;

while hasdata(ds)
    C = read(ds);
    chunkNo = chunkNo + 1;

    dt = C.datetime;
    if ~isdatetime(dt)
        raw = string(dt);
        if strlength(opts.DatetimeFormat) > 0
            dt = datetime(raw, 'InputFormat', char(opts.DatetimeFormat));
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
            error('buildDeploymentIndex:badDatetimeFormat', ...
                ['%.1f%% of datetimes in the first chunk failed to parse. Run ' ...
                 'inspectBigFile(bigCsv) and pass its .dateOrderGuess as ' ...
                 '''DatetimeFormat'' explicitly -- do not rely on inference or ' ...
                 'on a format read off an Excel paste. Example raw value(s): %s'], ...
                100*badFrac, strjoin(examples(1:min(5,numel(examples))), ', '));
        end
    end

    fn   = string(C.(fnVar));
    sp   = upper(string(C.species));
    dep  = string(C.deployment_fk);
    ncf  = double(C.number_clicks_filtered);
    hasI = ~ismissing(C.min_ici);
    if isstring(C.min_ici)                 % NULLs exported as "" or "NULL"
        hasI = strlength(strtrim(C.min_ici)) > 0 & ~strcmpi(strtrim(C.min_ici), "NULL") ...
             & ~strcmpi(strtrim(C.min_ici), "NaN");
    end

    G = table(dep, fn, sp, dt, double(ncf > 0), double(hasI), ...
        'VariableNames', {'deployment_fk','dbFilename','species','dt','clickPos','hasICI'});

    part = groupAggregate(G);

    acc = [acc; part];   %#ok<AGROW>
    if height(acc) > 200000      % keep the accumulator small
        acc = rollup(acc);
    end

    seenBytes = seenBytes + sum(strlength(fn)) + 120*height(C);   % rough
    frac = min(0.99, seenBytes/totalBytes);
    reportProgress(opts.ProgressFcn, frac, ...
        sprintf('Indexing chunk %d (~%.1f%%), %d file/species groups so far', ...
        chunkNo, 100*frac, height(unique(acc(:,{'deployment_fk','dbFilename','species'})))));
end

idx = rollup(acc);

% --- parse the database-side filename into matchable components ----------
P = parsePodName(idx.dbFilename);
idx.podId       = P.podId;
idx.station     = P.station;
idx.stationBase = P.stationBase;
idx.nameDate    = P.nameDate;

idx = sortrows(idx, {'podId','firstDatetime'});
reportProgress(opts.ProgressFcn, 1, sprintf('Index built: %d rows', height(idx)));

if strlength(opts.SaveTo) > 0
    save(opts.SaveTo, 'idx');
    [p,n] = fileparts(opts.SaveTo);
    writetable(idx, fullfile(p, n + ".csv"));
end
end

% =======================================================================
function part = groupAggregate(G)
%GROUPAGGREGATE Per-chunk reduction of the raw rows in G to one row per
%(deployment_fk,dbFilename,species). groupsummary applies every method to
%every data variable it is given (a full cross product, not an elementwise
%pairing), so 'sum' and datetime columns must never appear in the same call
%-- sum(datetime) errors. Numeric sums and the datetime range are therefore
%computed in two separate calls and joined back together.
keys = {'deployment_fk','dbFilename','species'};

gNum = groupsummary(G, keys, 'sum', {'clickPos','hasICI'});
gDt  = groupsummary(G, keys, {'min','max'}, {'dt'});   % -> min_dt, max_dt

part = innerjoin(gNum, gDt(:, [keys, {'min_dt','max_dt'}]), 'Keys', keys);
end

function out = rollup(acc)
%ROLLUP Merge partial per-chunk aggregates in acc into one row per group.
% Same split-then-join approach as groupAggregate, for the same reason.
keys = {'deployment_fk','dbFilename','species'};

gNum = groupsummary(acc, keys, 'sum', {'GroupCount','sum_clickPos','sum_hasICI'});
gDt  = groupsummary(acc, keys, {'min','max'}, {'min_dt','max_dt'});
% gDt has min_min_dt, max_min_dt, min_max_dt, max_max_dt (cross product of
% the two methods over the two columns); only the two that make sense are kept.

out = innerjoin(gNum, gDt(:, [keys, {'min_min_dt','max_max_dt'}]), 'Keys', keys);
out = renamevars(out, ...
    {'sum_GroupCount','sum_sum_clickPos','sum_sum_hasICI','min_min_dt','max_max_dt'}, ...
    {'nRows','nClickPositive','nMinICIAlready','firstDatetime','lastDatetime'});
out.GroupCount = [];
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.SaveTo         = string(opts.SaveTo);
opts.FilenameVar    = string(opts.FilenameVar);
opts.DatetimeFormat = string(opts.DatetimeFormat);
opts.Delimiter      = string(opts.Delimiter);
end

function reportProgress(fcn, frac, msg)
if isempty(fcn), return; end
try
    fcn(frac, msg);
catch
    fprintf('%s\n', msg);
end
end
