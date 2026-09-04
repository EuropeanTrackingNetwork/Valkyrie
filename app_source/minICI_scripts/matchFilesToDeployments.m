function X = matchFilesToDeployments(S, idx, varargin)
%MATCHFILESTODEPLOYMENTS Build the crosswalk: minICI output file -> deployment_fk.
%
%   X = matchFilesToDeployments(S, idx)
%   X = matchFilesToDeployments(S, idx, 'WindowTolerance', minutes(2))
%
%   S    output of scanMinICIOutputs
%   idx  output of buildDeploymentIndex
%
%   Filenames are never matched as strings. The date inside a filename is the
%   deployment date on the database side, the POD power-on or recovery date on
%   the file side, and the station code may carry a suffix on one side only
%   ("GB1" vs "GB1A"). Matching therefore uses:
%
%     1. POD serial parsed from both names            (hard requirement)
%     2. the database time window sitting inside the POD file window
%        (the archived exports were trimmed to the in-water period)
%     3. count invariant: number of min_ici values inside the database window
%        == number of click-positive database rows                (confirmation)
%     4. station base equality                                    (tie-break only)
%
%   Every row gets a status. Only 'matched' rows should be fed to
%   extractMinICIUpdates; everything else is a review queue.
%
%       matched              one candidate, window contained, counts agree
%       matched_no_count     one candidate, window contained, counts not checked
%       count_mismatch       one candidate but the count invariant failed
%       ambiguous            more than one candidate survived
%       window_mismatch      POD serial found but no candidate window fits
%       no_candidate         POD serial not present in the index
%       no_podid             POD serial could not be parsed from a filename
%
%   Part of the minICI back-fill toolset.

opts = struct('WindowTolerance', minutes(0), 'RequireStation', false, 'SaveTo', "");
opts = parseOpts(opts, varargin);

% collapse the index to one row per database file (species summed).
% groupsummary applies every method to every data variable (a full cross
% product, not an elementwise pairing), so 'sum' and datetime columns must
% never appear in the same call -- sum(firstDatetime) errors. Numeric sums
% and the datetime range are computed separately and joined back together.
keys = {'deployment_fk','dbFilename'};
fNum = groupsummary(idx, keys, 'sum', {'nRows','nClickPositive'});
fDt  = groupsummary(idx, keys, {'min','max'}, {'firstDatetime','lastDatetime'});
% fDt has min_firstDatetime, max_firstDatetime, min_lastDatetime,
% max_lastDatetime (cross product again); only the two that make sense are kept.
F = innerjoin(fNum, fDt(:, [keys, {'min_firstDatetime','max_lastDatetime'}]), 'Keys', keys);
F = renamevars(F, {'sum_nRows','sum_nClickPositive','min_firstDatetime','max_lastDatetime'}, ...
    {'dbRows','dbClickPositive','dbFirst','dbLast'});
P = parsePodName(F.dbFilename);
F.podId = P.podId; F.stationBase = P.stationBase;

n = height(S);
out = table('Size', [n 16], ...
    'VariableTypes', {'string','string','string','double','string','string','string', ...
                      'datetime','datetime','datetime','datetime','double','double','double','double','string'}, ...
    'VariableNames', {'file','newFilename','species','podId','status','deployment_fk','dbFilename', ...
                      'newFirst','newLast','dbFirst','dbLast','containFrac', ...
                      'dbClickPositive','nICIInWindow','nCandidates','note'});

for k = 1:n
    out.file(k)        = S.file(k);
    out.newFilename(k) = S.newFilename(k);
    out.species(k)     = S.species(k);
    out.podId(k)       = S.podId(k);
    out.newFirst(k)    = S.firstDatetime(k);
    out.newLast(k)     = S.lastDatetime(k);
    out.nICIInWindow(k)= NaN;

    if isnan(S.podId(k))
        out.status(k) = "no_podid";
        out.note(k)   = "could not parse POD serial from '" + S.newFilename(k) + "'";
        continue
    end

    cand = F(F.podId == S.podId(k), :);
    if opts.RequireStation
        cand = cand(cand.stationBase == S.stationBase(k), :);
    end
    out.nCandidates(k) = height(cand);
    if isempty(cand)
        out.status(k) = "no_candidate";
        out.note(k)   = "no database file with POD " + string(S.podId(k));
        continue
    end

    % --- containment of the database window in the POD file window --------
    tol   = opts.WindowTolerance;
    lo    = max(cand.dbFirst, S.firstDatetime(k) - tol);
    hi    = min(cand.dbLast,  S.lastDatetime(k)  + tol);
    span  = cand.dbLast - cand.dbFirst;
    ovl   = max(hi - lo, seconds(0));
    frac  = ovl ./ max(span, eps);
    frac(span == 0) = double(ovl(span == 0) >= 0);

    keep = frac >= 0.999;
    if ~any(keep)
        [bestFrac, b] = max(frac);
        out.status(k)      = "window_mismatch";
        out.deployment_fk(k)= cand.deployment_fk(b);
        out.dbFilename(k)  = cand.dbFilename(b);
        out.dbFirst(k)     = cand.dbFirst(b);
        out.dbLast(k)      = cand.dbLast(b);
        out.containFrac(k) = bestFrac;
        out.note(k)        = sprintf('best candidate covers only %.3f of its window', bestFrac);
        continue
    end
    cand = cand(keep,:); frac = frac(keep);

    % --- tie-break on station base, then on count invariant ---------------
    if height(cand) > 1
        sameStation = cand.stationBase == S.stationBase(k);
        if sum(sameStation) == 1
            cand = cand(sameStation,:); frac = frac(sameStation);
        end
    end

    iciTimes = S.iciTimes{k};
    counts = nan(height(cand),1);
    if ~isempty(iciTimes)
        for c = 1:height(cand)
            counts(c) = sum(iciTimes >= cand.dbFirst(c) & iciTimes <= cand.dbLast(c));
        end
        agree = counts == cand.dbClickPositive;
        if height(cand) > 1 && sum(agree) == 1
            cand = cand(agree,:); frac = frac(agree); counts = counts(agree);
        end
    end

    if height(cand) > 1
        out.status(k)      = "ambiguous";
        out.deployment_fk(k)= strjoin(cand.deployment_fk, ";");
        out.dbFilename(k)  = strjoin(cand.dbFilename, ";");
        out.containFrac(k) = max(frac);
        out.note(k)        = sprintf('%d candidates survived; resolve by hand', height(cand));
        continue
    end

    out.deployment_fk(k)   = cand.deployment_fk(1);
    out.dbFilename(k)      = cand.dbFilename(1);
    out.dbFirst(k)         = cand.dbFirst(1);
    out.dbLast(k)          = cand.dbLast(1);
    out.containFrac(k)     = frac(1);
    out.dbClickPositive(k) = cand.dbClickPositive(1);
    out.nICIInWindow(k)    = counts(1);

    if isnan(counts(1))
        out.status(k) = "matched_no_count";
        out.note(k)   = "count invariant not checked (iciTimes not retained)";
    elseif counts(1) == cand.dbClickPositive(1)
        out.status(k) = "matched";
        out.note(k)   = "";
    else
        out.status(k) = "count_mismatch";
        out.note(k)   = sprintf('%d min_ici values in window vs %d click-positive db rows', ...
            counts(1), cand.dbClickPositive(1));
    end
end

% --- warn about overlapping database files within one deployment ---------
X = out;
[~,~,g] = unique(F.deployment_fk);
for gi = reshape(unique(g),1,[])
    sub = F(g == gi, :);
    if height(sub) > 1
        sub = sortrows(sub, 'dbFirst');
        if any(sub.dbFirst(2:end) <= sub.dbLast(1:end-1))
            warning('matchFilesToDeployments:overlap', ...
                ['deployment %s has database files with overlapping time ranges; ' ...
                 'the (deployment,datetime,quality,species) key is not unique there'], ...
                sub.deployment_fk(1));
        end
    end
end

printSummary(X);
if strlength(opts.SaveTo) > 0
    writetable(X, opts.SaveTo);
end
end

% =======================================================================
function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.SaveTo = string(opts.SaveTo);
end

function printSummary(X)
fprintf('\n=== crosswalk ===\n');
disp(groupsummary(X, 'status'));
bad = X(X.status ~= "matched", :);
if ~isempty(bad)
    fprintf('%d row(s) need review:\n', height(bad));
    disp(bad(:, {'newFilename','species','status','note'}));
end
end
