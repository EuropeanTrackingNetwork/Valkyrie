function [rawU, dupReport] = collapseRawCopies(rawInv, varargin)
%COLLAPSERAWCOPIES Reduce duplicate copies and cropped variants to one file each.
%
%   [rawU, dupReport] = collapseRawCopies(raw)
%   [rawU, dupReport] = collapseRawCopies(raw, 'FolderPreference', ["NOVANA_2017-21","RawData"])
%
%   The raw folders hold the same POD file in several places (backups, merged
%   collections) and sometimes a cropped export alongside the original, marked
%   with a trailing "PART 179d 1m"-style suffix. Both inflate the candidate
%   count during matching without adding real alternatives: in the surveyed
%   data, 101 of 158 ambiguous processed files had candidates that were all the
%   *same filename* in different folders.
%
%   This collapses each set to one representative before matching, so the
%   remaining candidates are genuinely different deployments.
%
%   Files are grouped by canonical name + extension, where the canonical name
%   has separators normalised and any trailing PART suffix removed. Within a
%   group the representative is chosen by, in order:
%
%     1. uncropped over cropped (unless 'PreferPart' is true)
%     2. 'FolderPreference' -- first matching pattern wins
%     3. largest file
%     4. alphabetical path, so the result is deterministic
%
%   rawU adds these columns to the inventory:
%       canonName    normalised name with any PART suffix stripped
%       isPart       true if this file's own name carried a PART suffix
%       nCopies      how many files collapsed into this row
%       nPartCopies  how many of those were cropped variants
%       allPaths     every path in the group, ";"-joined
%
%   dupReport is one row per collapsed group with more than one member.
%
%   Options
%       'FolderPreference'  substrings matched against the full path, earlier =
%                           preferred. Default [] (no folder preference).
%       'PreferPart'        keep the cropped variant instead (default false)
%       'SaveTo'            path for a .mat (and .csv) copy of rawU
%
%   Part of the minICI back-fill toolset.

opts = struct('FolderPreference', strings(0,1), 'PreferPart', false, 'SaveTo', "");
opts = parseOpts(opts, varargin);
pref = string(opts.FolderPreference(:));

% --- canonical name -------------------------------------------------------
norm = upper(strtrim(regexprep(regexprep(rawInv.name, '[_\-\.]+', ' '), '\s+', ' ')));
partPat = '\s+PART\s+.*$';
isPart  = ~cellfun(@isempty, regexpi(cellstr(norm), partPat, 'once'));
canon   = string(regexprep(cellstr(norm), partPat, '', 'ignorecase'));

T = rawInv;
T.canonName = canon;
T.isPart    = isPart(:);
T.grpKey    = canon + "|" + lower(T.ext);

% --- preference score per row --------------------------------------------
folderScore = zeros(height(T),1) + numel(pref) + 1;   % unlisted folders rank last
for p = numel(pref):-1:1
    hit = contains(T.path, pref(p), 'IgnoreCase', true);
    folderScore(hit) = p;
end

[keys, ~, g] = unique(T.grpKey);
nG = numel(keys);

keepIdx  = zeros(nG,1);
nCopies  = zeros(nG,1);
nPart    = zeros(nG,1);
allPaths = strings(nG,1);

for k = 1:nG
    rows = find(g == k);
    nCopies(k) = numel(rows);
    nPart(k)   = sum(T.isPart(rows));
    allPaths(k)= strjoin(sort(T.path(rows)), ";");

    sub = rows;
    % 1. cropped vs uncropped
    if opts.PreferPart
        want = sub(T.isPart(sub));
    else
        want = sub(~T.isPart(sub));
    end
    if ~isempty(want), sub = want; end
    % 2. folder preference
    if numel(sub) > 1
        best = min(folderScore(sub));
        sub = sub(folderScore(sub) == best);
    end
    % 3. largest file
    if numel(sub) > 1
        [~, b] = max(T.bytes(sub));
        sub = sub(b);
    end
    % 4. deterministic fallback
    if numel(sub) > 1
        [~, b] = min(T.path(sub));
        sub = sub(b);
    end
    keepIdx(k) = sub(1);
end

rawU = T(keepIdx, :);
rawU.nCopies     = nCopies;
rawU.nPartCopies = nPart;
rawU.allPaths    = allPaths;
rawU.grpKey      = [];
rawU = sortrows(rawU, {'podId','nameDate','fileNo'});

dupReport = rawU(rawU.nCopies > 1, ...
    {'canonName','ext','nCopies','nPartCopies','path','allPaths'});

printSummary(T, rawU, dupReport, pref);

if strlength(opts.SaveTo) > 0
    save(opts.SaveTo, 'rawU');
    [p,n] = fileparts(opts.SaveTo);
    writetable(rawU, fullfile(p, n + ".csv"));
end
end

% =======================================================================
function printSummary(T, rawU, dupReport, pref)
fprintf('\n=== collapseRawCopies ===\n');
fprintf('files in            : %d\n', height(T));
fprintf('distinct real files : %d\n', height(rawU));
fprintf('collapsed away      : %d (%.1f%%)\n', ...
    height(T)-height(rawU), 100*(height(T)-height(rawU))/max(1,height(T)));
fprintf('cropped (PART) files: %d, of which kept as the only copy: %d\n', ...
    sum(T.isPart), sum(rawU.isPart));
if ~isempty(pref)
    fprintf('folder preference   : %s\n', strjoin(pref, ' > '));
else
    fprintf(['folder preference   : none set -- representative chosen by size then path.\n' ...
             '                      Pass ''FolderPreference'' if one collection is authoritative.\n']);
end

if ~isempty(dupReport)
    fprintf('\ngroups with more than one copy: %d (up to 5 shown)\n', height(dupReport));
    for k = 1:min(5, height(dupReport))
        fprintf('  %s.%s  (%d copies, %d cropped)\n', ...
            dupReport.canonName(k), dupReport.ext(k), ...
            dupReport.nCopies(k), dupReport.nPartCopies(k));
    end
end
fprintf('\n');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.SaveTo           = string(opts.SaveTo);
opts.FolderPreference = string(opts.FolderPreference);
end