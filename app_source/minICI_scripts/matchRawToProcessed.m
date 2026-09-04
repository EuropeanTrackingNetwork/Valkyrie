function [R, reprocess] = matchRawToProcessed(procInv, rawInv, varargin)
%MATCHRAWTOPROCESSED Pair each already-processed detection file with its raw POD file.
%
%   [R, reprocess] = matchRawToProcessed(procInv, rawU, 'Index', idx)
%
%   procInv   surveyPodFiles output for the processed folders
%   rawInv    surveyPodFiles output for the raw folders -- run it through
%             collapseRawCopies FIRST, or duplicate copies of the same file will
%             show up as competing candidates
%
%   R          one row per (processed file x chosen raw file), with a status
%   reprocess  de-duplicated raw paths to feed to runMinICIBatch
%
%   How a match is decided
%   ----------------------
%   Only the POD serial is reliable across both naming conventions (processed
%   names carry the deployment date, raw names carry whatever date the POD
%   wrote). So:
%
%     1. POD serial must match                                  (hard)
%     2. the raw name's date must fall in a window               (hard)
%          - from the database index when the processed name is found there,
%            which is the deployment's real first/last detection timestamps
%          - otherwise the processed name's own date +/- 'MaxDateOffset'
%     3. surviving candidates are grouped by DEPLOYMENT IDENTITY: the full
%        station token plus the date, e.g. "KF5J 2015 03 11" vs
%        "KF5M 2017 03 06". Note this uses the full token, not the station
%        base -- KF5J and KF5M are different deployments at the same station.
%     4. one group -> matched (or matched_multipart if it has several fileNN
%        parts). Several groups -> the group nearest the processed date wins,
%        reported as matched_nearest so it can be spot-checked. A tie on
%        distance -> ambiguous.
%
%   No candidate in the window means NO MATCH, not a free-for-all
%   ------------------------------------------------------------
%   An earlier version skipped the window filter when nothing fell inside it,
%   which turned "the raw file for this deployment isn't here" into a 30-way
%   ambiguity. Those cases now return "no_raw_in_window" together with the
%   nearest candidate's offset in days, which is the actually useful output:
%   the raw data for that deployment is missing from the searched folders, or
%   filed under a name whose POD serial or date cannot be read.
%
%   Statuses
%       matched             one deployment group, one file
%       matched_multipart   one deployment group, several fileNN parts (all kept)
%       matched_nearest     several groups; nearest to the processed date chosen
%       ambiguous           groups equidistant from the processed date
%       no_raw_in_window    POD serial present on disk but nothing near in time
%       no_candidate        POD serial has no raw file at all
%       no_podid            POD serial unreadable on the processed side
%
%   Two more heuristics apply before grouping:
%     - raw files whose station token contains "TEST" (bench/calibration
%       recordings, e.g. "1695BTEST") are dropped as candidates entirely
%     - the deployment-identity key strips ALL whitespace from the station
%       token, not just repeated runs, so a filename typo like "FF2 J" instead
%       of "FF2J" still collapses into the same deployment group
%
%   Options
%       'Index'          buildDeploymentIndex output; strongly recommended
%       'MaxDateOffset'  fallback half-window when 'Index' has no entry for a
%                        processed file (default 21 days)
%       'WindowPad'      slack around the database window (default 45 days, to
%                        cover power-on before deployment and recovery after)
%       'RawExtensions'  which raw extensions are candidates (default "cp3").
%                        Some collections (e.g. a folder literally named
%                        "CP1 all") store only .cp1 -- check
%                        groupsummary(rawInv(contains(rawInv.root,"..."),:),'ext')
%                        before assuming a mismatch is missing data rather than
%                        an extension that was never searched.
%       'RequireStation' require the station base to agree as well (default
%                        false -- station coding changed between eras, e.g. the
%                        NOVANA numeric codes 8009/8013 vs the older letter
%                        codes, so this will reject valid matches if turned on)
%       'ExcludeStationPattern' regex (case-insensitive) applied to the raw
%                        station token; matches are dropped as candidates
%                        before windowing. Default '(?i)TEST'.
%       'SaveTo'         path for a .csv copy of R
%
%   Part of the minICI back-fill toolset.

opts = struct('Index', [], 'MaxDateOffset', days(21), 'WindowPad', days(45), ...
    'RawExtensions', "cp3", 'RequireStation', false, ...
    'ExcludeStationPattern', "(?i)TEST", 'SaveTo', "");
opts = parseOpts(opts, varargin);

if ~ismember('nCopies', rawInv.Properties.VariableNames)
    warning('matchRawToProcessed:notCollapsed', ...
        ['rawInv does not look like collapseRawCopies output. Duplicate copies ' ...
         'of the same file will compete as candidates. Run collapseRawCopies first.']);
end

raw = rawInv(ismember(lower(rawInv.ext), lower(string(opts.RawExtensions))), :);
if isempty(raw)
    error('matchRawToProcessed:noRawCandidates', ...
        'No raw files with extension(s) %s in the inventory. Present: %s', ...
        strjoin(string(opts.RawExtensions), ', '), strjoin(unique(rawInv.ext), ', '));
end
raw = raw(raw.parsed, :);

if strlength(opts.ExcludeStationPattern) > 0
    isExcluded = ~cellfun(@isempty, regexp(cellstr(raw.station), opts.ExcludeStationPattern, 'once'));
    if any(isExcluded)
        fprintf('excluding %d raw file(s) whose station token matches ''%s'' (e.g. bench tests): %s\n', ...
            sum(isExcluded), opts.ExcludeStationPattern, ...
            strjoin(unique(raw.station(isExcluded)), ', '));
        raw = raw(~isExcluded, :);
    end
end

% deployment identity: station token with ALL whitespace stripped, + date.
% Stripping every space (not just collapsing runs) matters: a filename typo
% like "FF2 J" vs "FF2J" is the same deployment and must land in one group.
raw.depKey = upper(regexprep(raw.station, '\s+', '')) + "|" + string(raw.nameDate, 'yyyy-MM-dd');

useIdx = ~isempty(opts.Index);
if useIdx
    idxNorm = normaliseName(opts.Index.dbFilename);
end

rows = cell(height(procInv),1);
for k = 1:height(procInv)
    P = procInv(k,:);

    if ~P.parsed
        rows{k} = makeRow(P, [], "no_podid", "POD serial unreadable in processed filename", NaT, NaT);
        continue
    end

    cand = raw(raw.podId == P.podId, :);
    if opts.RequireStation
        cand = cand(cand.stationBase == P.stationBase, :);
    end
    if isempty(cand)
        rows{k} = makeRow(P, [], "no_candidate", ...
            "no raw file for POD " + string(P.podId), NaT, NaT);
        continue
    end

    % --- window ----------------------------------------------------------
    winLo = NaT; winHi = NaT; winSrc = "";
    if useIdx
        hit = find(idxNorm == normaliseName(P.name), 1);
        if ~isempty(hit)
            winLo  = opts.Index.firstDatetime(hit) - opts.WindowPad;
            winHi  = opts.Index.lastDatetime(hit)  + opts.WindowPad;
            winSrc = "database window";
        end
    end
    if isnat(winLo) && ~isnat(P.nameDate)
        winLo  = P.nameDate - opts.MaxDateOffset;
        winHi  = P.nameDate + opts.MaxDateOffset;
        winSrc = "processed date +/- " + string(days(opts.MaxDateOffset)) + "d";
    end
    if isnat(winLo)
        rows{k} = makeRow(P, [], "no_raw_in_window", ...
            "processed file has no date and is not in the database index", NaT, NaT);
        continue
    end

    inWin = ~isnat(cand.nameDate) & cand.nameDate >= winLo & cand.nameDate <= winHi;
    if ~any(inWin)
        % the informative failure: say how far off the closest one was
        off = min(abs(days(cand.nameDate - P.nameDate)), [], 'omitnan');
        if isempty(off) || isnan(off)
            note = sprintf('%d raw file(s) for this POD, none with a readable date', height(cand));
        else
            note = sprintf(['%d raw file(s) for this POD, none inside the %s; ' ...
                            'nearest is %.0f days away -- raw data for this deployment ' ...
                            'looks absent from the searched folders'], ...
                            height(cand), winSrc, off);
        end
        rows{k} = makeRow(P, [], "no_raw_in_window", note, winLo, winHi);
        continue
    end
    cand = cand(inWin, :);

    % --- group by deployment identity ------------------------------------
    [gKeys, ~, gi] = unique(cand.depKey);
    if numel(gKeys) == 1
        chosen = cand;
        status = pickPartStatus(chosen);
        note   = sprintf('%s; %s', winSrc, partNote(chosen));
    else
        % nearest deployment group to the processed date
        offByGrp = accumarray(gi, abs(days(cand.nameDate - P.nameDate)), [], @min);
        best = min(offByGrp);
        winners = find(offByGrp == best);
        deprioritizedNote = "";
        if numel(winners) > 1
            % try deprioritizing placeholder-looking station names of the form
            % "CPOD<serial>" -- these restate the POD serial instead of naming
            % a real station, and lose to a genuine station code at the same
            % date distance rather than creating a tie
            isSelfRef = ~cellfun(@isempty, regexpi(cellstr(gKeys(winners)), '^CPOD\d+[A-Z]?\|', 'once'));
            if any(isSelfRef) && ~all(isSelfRef)
                deprioritizedNote = " (deprioritized placeholder-style station: " + ...
                    strjoin(gKeys(winners(isSelfRef)), ", ") + ")";
                winners = winners(~isSelfRef);
            end
        end
        if numel(winners) > 1
            chosen = cand;
            status = "ambiguous";
            note = sprintf(['%d deployment groups equally %.0f days from the processed ' ...
                            'date (%s) -- resolve by hand'], numel(winners), best, ...
                            strjoin(gKeys(winners), " / "));
        else
            chosen = cand(gi == winners, :);
            status = "matched_nearest";
            base   = pickPartStatus(chosen);
            note   = sprintf('nearest of %d groups (%.0f days, %s)%s; %s; other groups: %s', ...
                numel(gKeys), best, base, deprioritizedNote, partNote(chosen), ...
                strjoin(gKeys(setdiff(1:numel(gKeys), winners)), " / "));
        end
    end
    rows{k} = makeRow(P, chosen, status, note, winLo, winHi);
end

R = vertcat(rows{:});

good = ismember(R.status, ["matched","matched_multipart","matched_nearest"]) & ~ismissing(R.rawPath);
reprocess = unique(R.rawPath(good));

printSummary(R, reprocess, useIdx, opts);

if strlength(opts.SaveTo) > 0
    writetable(R, opts.SaveTo);
end
end

% =======================================================================
function s = pickPartStatus(chosen)
if height(chosen) == 1
    s = "matched";
elseif numel(unique(chosen.fileNo)) == height(chosen) && all(~isnan(chosen.fileNo))
    s = "matched_multipart";
else
    s = "ambiguous";
end
end

function n = partNote(chosen)
if height(chosen) == 1
    n = "single file";
else
    fn = chosen.fileNo(~isnan(chosen.fileNo));
    n = sprintf('%d parts (file%s)', height(chosen), strjoin(compose("%02d", fn)', "/"));
end
end

function T = makeRow(P, cand, status, note, winLo, winHi)
if isempty(cand)
    n = 1;
    rawPath = string(missing); rawName = string(missing); rawExt = string(missing);
    rawDate = NaT; rawFileNo = NaN; nCopies = NaN;
else
    n = height(cand);
    rawPath = cand.path; rawName = cand.name; rawExt = cand.ext;
    rawDate = cand.nameDate; rawFileNo = cand.fileNo;
    if ismember('nCopies', cand.Properties.VariableNames)
        nCopies = cand.nCopies;
    else
        nCopies = nan(n,1);
    end
end

T = table( ...
    repmat(P.path, n, 1), repmat(P.name, n, 1), ...
    repmat(P.podId, n, 1), repmat(P.stationBase, n, 1), repmat(P.nameDate, n, 1), ...
    rawPath, rawName, rawExt, rawDate, rawFileNo, nCopies, ...
    repmat(string(status), n, 1), repmat(string(note), n, 1), ...
    repmat(winLo, n, 1), repmat(winHi, n, 1), ...
    'VariableNames', {'procPath','procName','podId','stationBase','procDate', ...
                      'rawPath','rawName','rawExt','rawDate','rawFileNo','rawNCopies', ...
                      'status','note','windowLo','windowHi'});
end

function s = normaliseName(s)
s = upper(strtrim(regexprep(regexprep(string(s), '[_\-\.]+', ' '), '\s+', ' ')));
end

function printSummary(R, reprocess, useIdx, opts)
fprintf('\n=== matchRawToProcessed ===\n');
if ~useIdx
    fprintf(['NOTE: no ''Index'' supplied -- every window came from the processed\n' ...
             '      filename date +/- %g days. Pass the buildDeploymentIndex output.\n'], ...
             days(opts.MaxDateOffset));
end

[uProc, ia] = unique(R.procName);
byProc = table(uProc, R.status(ia), 'VariableNames', {'procName','status'});
fprintf('\nby status (unique processed files):\n');
disp(groupsummary(byProc, 'status'));

resolved = ["matched","matched_multipart","matched_nearest"];
nProc = numel(uProc);
nOk   = numel(unique(R.procName(ismember(R.status, resolved))));
fprintf('processed files        : %d\n', nProc);
fprintf('  resolved             : %d\n', nOk);
fprintf('  needing review       : %d\n', nProc - nOk);
fprintf('raw files to reprocess : %d\n', numel(reprocess));

sub = R(R.status == "matched_nearest", :);
if ~isempty(sub)
    [~, ja] = unique(sub.procName);
    fprintf(['\n%d file(s) matched by nearest-date across several deployment groups.\n' ...
             'These are the ones worth spot-checking first:\n'], numel(ja));
    disp(sub(ja(1:min(10,numel(ja))), {'procName','rawName','note'}));
end

missingRaw = R(R.status == "no_raw_in_window", :);
if ~isempty(missingRaw)
    [~, ja] = unique(missingRaw.procName);
    fprintf(['\n%d processed file(s) have no raw file in window -- likely missing raw data\n' ...
             'rather than a matching failure (up to 10 shown):\n'], numel(ja));
    disp(missingRaw(ja(1:min(10,numel(ja))), {'procName','note'}));
end

other = R(ismember(R.status, ["ambiguous","no_candidate","no_podid"]), :);
if ~isempty(other)
    [~, ja] = unique(other.procName);
    fprintf('\n%d file(s) still need manual resolution:\n', numel(ja));
    disp(other(ja(1:min(10,numel(ja))), {'procName','status','note'}));
end
fprintf('\n');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.SaveTo        = string(opts.SaveTo);
opts.RawExtensions = string(opts.RawExtensions);
end