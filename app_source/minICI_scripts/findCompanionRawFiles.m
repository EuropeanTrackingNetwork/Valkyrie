function comp = findCompanionRawFiles(R, rawU, companionExt, varargin)
%FINDCOMPANIONRAWFILES Find a companion raw file (e.g. .cp1) for each matched file.
%
%   comp = findCompanionRawFiles(R, rawU, "cp1")
%   comp = findCompanionRawFiles(R, rawU, ["cp1","fp1"])
%
%   R         matchRawToProcessed output -- the ALREADY-SOLVED hard matching
%             problem (which raw file belongs to which deployment), typically
%             done against .cp3/.fp3
%   rawU      collapseRawCopies output -- must include the companion extension
%             in its inventory, i.e. surveyPodFiles' root folders must actually
%             cover wherever the companion files live. If they were surveyed
%             from different folders than the matched extension, add those
%             folders to the surveyPodFiles call and rebuild rawU BEFORE
%             running this -- no lookup here can find a file the inventory
%             never saw.
%   companionExt  extension(s) to look for, without dots
%
%   Why this is a lookup, not another round of matching
%   ----------------------------------------------------
%   A .cp1 and its corresponding .cp3 are produced from the same physical
%   recording and, by convention, share the same base filename -- only the
%   extension differs. The deployment-matching problem (POD serial + date
%   window + station-token grouping) has already been solved once, against
%   whichever extension matchRawToProcessed used; re-running all of that for a
%   second extension would be redundant and could introduce fresh ambiguity.
%   Instead this joins on the CANONICAL NAME collapseRawCopies already computed
%   (separators normalised, any PART suffix stripped), which collapseRawCopies
%   guarantees is unique per (canonName, ext) pair in rawU -- so this lookup is
%   always 0-or-1 matches, never ambiguous, as long as the naming convention
%   assumption above actually holds for this dataset.
%
%   comp columns
%       procName, matchedPath (the file R resolved to), matchedExt,
%       companionPath, companionExt, companionStatus ("found"/"not_found"),
%       companionNCopies (from rawU -- >1 means duplicate copies of the
%       companion existed and collapseRawCopies picked one; worth knowing
%       before trusting it blindly)
%
%   Options
%       'RequirePodMatch'  extra sanity check: reject a name-based match whose
%                          podId disagrees (default true; should never fire if
%                          canonical names truly correspond 1:1, so if it does
%                          fire, that's worth looking at directly)
%       'SaveTo'           path for a .csv copy of comp
%
%   Part of the minICI back-fill toolset.

opts = struct('RequirePodMatch', true, 'SaveTo', "");
opts = parseOpts(opts, varargin);
companionExt = lower(string(companionExt));

if ~ismember('canonName', rawU.Properties.VariableNames)
    error('findCompanionRawFiles:notCollapsed', ...
        'rawU must be collapseRawCopies output (needs the canonName column).');
end

present = unique(lower(rawU.ext));
missingExt = setdiff(companionExt, present);
if ~isempty(missingExt)
    warning('findCompanionRawFiles:extensionAbsent', ...
        ['Extension(s) %s do not appear ANYWHERE in rawU. Either these files ' ...
         'don''t exist, or the surveyPodFiles root folders never covered where ' ...
         'they live -- check before assuming they''re simply missing.'], ...
         strjoin(missingExt, ', '));
end

resolved = ["matched","matched_multipart","matched_nearest"];
Rr = R(ismember(R.status, resolved) & ~ismissing(R.rawPath), :);

[tf, loc] = ismember(Rr.rawPath, rawU.path);
if ~all(tf)
    warning('findCompanionRawFiles:pathMismatch', ...
        ['%d matched row(s) in R do not appear in rawU by exact path -- was R built ' ...
         'from this same rawU (post-collapseRawCopies)? Those rows are skipped.'], sum(~tf));
end
Rr = Rr(tf, :);
Rr.canonName = rawU.canonName(loc(tf));
Rr.podIdChk  = rawU.podId(loc(tf));

compPool = rawU(ismember(lower(rawU.ext), companionExt), :);

n = height(Rr);
companionPath  = strings(n,1);
companionExtOut= strings(n,1);
companionStat  = strings(n,1);
companionCopies= nan(n,1);

for k = 1:n
    hit = compPool(compPool.canonName == Rr.canonName(k), :);
    if opts.RequirePodMatch && ~isempty(hit)
        badPod = hit.podId ~= Rr.podIdChk(k);
        if any(badPod)
            hit = hit(~badPod, :);
        end
    end
    if isempty(hit)
        companionStat(k) = "not_found";
    else
        if height(hit) > 1
            % should not happen given collapseRawCopies' guarantee -- keep the
            % first deterministically and say so rather than silently picking
            hit = sortrows(hit, 'path');
            companionStat(k) = "unexpected_multiple";
        else
            companionStat(k) = "found";
        end
        companionPath(k)   = hit.path(1);
        companionExtOut(k) = hit.ext(1);
        companionCopies(k) = hit.nCopies(1);
    end
end

comp = table(Rr.procName, Rr.rawPath, Rr.rawExt, companionPath, companionExtOut, ...
    companionStat, companionCopies, ...
    'VariableNames', {'procName','matchedPath','matchedExt','companionPath', ...
                      'companionExt','companionStatus','companionNCopies'});

printSummary(comp, companionExt);

if strlength(opts.SaveTo) > 0
    writetable(comp, opts.SaveTo);
end
end

% =======================================================================
function printSummary(comp, companionExt)
fprintf('\n=== findCompanionRawFiles (looking for: %s) ===\n', strjoin(companionExt, ', '));
disp(groupsummary(comp, 'companionStatus'));

nf = comp(comp.companionStatus == "not_found", :);
if ~isempty(nf)
    fprintf(['\n%d deployment(s) have no companion file in rawU -- either it genuinely\n' ...
             'doesn''t exist, or the survey never covered the folder it lives in\n' ...
             '(up to 10 shown):\n'], height(nf));
    disp(nf(1:min(10,height(nf)), {'procName','matchedPath'}));
end

um = comp(comp.companionStatus == "unexpected_multiple", :);
if ~isempty(um)
    fprintf(['\n!! %d case(s) had more than one companion candidate, which ' ...
             'collapseRawCopies should have prevented -- worth a direct look:\n'], height(um));
    disp(um(:, {'procName','matchedPath','companionPath'}));
end

dup = comp(comp.companionStatus == "found" & comp.companionNCopies > 1, :);
if ~isempty(dup)
    fprintf(['\n%d found companion(s) had duplicate copies collapsed by collapseRawCopies --\n' ...
             'worth spot-checking that the representative it kept is the right one:\n'], height(dup));
    disp(dup(1:min(5,height(dup)), {'procName','companionPath','companionNCopies'}));
end
fprintf('\n');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.SaveTo = string(opts.SaveTo);
end