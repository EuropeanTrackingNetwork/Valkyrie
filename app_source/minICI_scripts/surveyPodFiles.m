function inv = surveyPodFiles(roots, varargin)
%SURVEYPODFILES Inventory files under one or more folders and report naming patterns.
%
%   inv = surveyPodFiles("O:\...\CPODS\DATA\2011-2016")
%   inv = surveyPodFiles([raw1; raw2], 'Extensions', ["cp1","cp3","fp1","fp3"])
%   inv = surveyPodFiles(procFolders, 'Extensions', "csv", 'SaveTo', "inv.mat")
%
%   Run this FIRST, before any matching. Raw POD filenames are not guaranteed to
%   follow the same convention as the processed detection filenames -- that is the
%   whole problem being solved -- so the patterns have to be read off the disk
%   rather than assumed.
%
%   inv is one row per file:
%       path         full path
%       folder       containing folder
%       name         filename without extension
%       ext          lower-case extension, no dot
%       bytes        file size
%       root         which input root it was found under
%       podId, station, stationBase, fileNo, nameDate   (from parsePodName)
%       parsed       true if a POD serial could be read from the name
%
%   Options
%       'Extensions'  extensions to keep, without dots, case-insensitive.
%                     Default ["cp1","cp3","fp1","fp3"]. Pass "csv" for the
%                     processed-output folders, or "*" for everything.
%       'Recursive'   search subfolders (default true)
%       'SaveTo'      path for a .mat (and matching .csv) copy
%       'ProgressFcn' handle called as fcn(fractionOrNaN, message)
%
%   The printed report is the point of this function: it shows how many names
%   parsed, what the unparseable ones look like, which extensions are present,
%   and whether any (podId, fileNo, ext) combination appears in more than one
%   place. Read it before trusting any match built on top of it.
%
%   Part of the minICI back-fill toolset.

opts = struct('Extensions', ["cp1","cp3","fp1","fp3"], 'Recursive', true, ...
    'SaveTo', "", 'ProgressFcn', []);
opts = parseOpts(opts, varargin);

roots = string(roots(:));
keepExt = lower(string(opts.Extensions(:)));
keepAll = any(keepExt == "*");

rows = cell(numel(roots),1);
for r = 1:numel(roots)
    if ~isfolder(roots(r))
        warning('surveyPodFiles:missingFolder', 'Not a folder, skipped: %s', roots(r));
        continue
    end
    reportProgress(opts.ProgressFcn, r/numel(roots), sprintf('Listing %s', roots(r)));

    if opts.Recursive
        d = dir(fullfile(roots(r), '**', '*'));
    else
        d = dir(fullfile(roots(r), '*'));
    end
    d = d(~[d.isdir]);
    if isempty(d), continue, end

    names = string({d.name})';
    [~, base, extDot] = fileparts(names);
    ext = lower(erase(string(extDot), "."));

    if ~keepAll
        sel = ismember(ext, keepExt);
        d = d(sel); names = names(sel); base = string(base(sel)); ext = ext(sel);
    else
        base = string(base);
    end
    if isempty(d), continue, end

    rows{r} = table( ...
        string(fullfile({d.folder}, {d.name}))', ...
        string({d.folder})', ...
        base, ext, [d.bytes]', ...
        repmat(roots(r), numel(d), 1), ...
        'VariableNames', {'path','folder','name','ext','bytes','root'});
end

inv = vertcat(rows{:});
if isempty(inv)
    error('surveyPodFiles:noFiles', ...
        'No files with extension(s) %s found under the given root(s).', strjoin(keepExt, ', '));
end

P = parsePodName(inv.name);
inv.podId       = P.podId;
inv.station     = P.station;
inv.stationBase = P.stationBase;
inv.fileNo      = P.fileNo;
inv.nameDate    = P.nameDate;
inv.parsed      = ~isnan(P.podId);

inv = sortrows(inv, {'podId','nameDate','fileNo'});

printSurvey(inv);

if strlength(opts.SaveTo) > 0
    save(opts.SaveTo, 'inv');
    [p,n] = fileparts(opts.SaveTo);
    writetable(inv, fullfile(p, n + ".csv"));
end
end

% =======================================================================
function printSurvey(inv)
fprintf('\n=== surveyPodFiles: %d file(s) ===\n', height(inv));

fprintf('\nby extension:\n');
disp(groupsummary(inv, 'ext'));

fprintf('by root folder:\n');
disp(groupsummary(inv, 'root'));

nParsed = sum(inv.parsed);
fprintf('POD serial parsed from name : %d of %d (%.1f%%)\n', ...
    nParsed, height(inv), 100*nParsed/height(inv));
fprintf('distinct POD serials        : %d\n', numel(unique(inv.podId(inv.parsed))));
fprintf('names carrying a fileNN part: %d\n', sum(~isnan(inv.fileNo)));
fprintf('names carrying a date       : %d\n', sum(~isnat(inv.nameDate)));
if any(~isnat(inv.nameDate))
    fprintf('date range in names         : %s .. %s\n', ...
        string(min(inv.nameDate), 'yyyy-MM-dd'), string(max(inv.nameDate), 'yyyy-MM-dd'));
end

fprintf('\ndistinct station tokens (up to 25): %s\n', ...
    strjoin(headN(unique(inv.station(inv.station ~= "")), 25), ', '));

fprintf('\nexample names (up to 10):\n');
ex = headN(inv.name, 10);
for k = 1:numel(ex), fprintf('  %s\n', ex(k)); end

bad = inv(~inv.parsed, :);
if ~isempty(bad)
    fprintf('\n!! %d name(s) with no readable POD serial -- these cannot be matched:\n', height(bad));
    ex = headN(bad.name, 10);
    for k = 1:numel(ex), fprintf('  %s\n', ex(k)); end
end

% --- literal duplicates: identical name+ext at more than one path ---------
% This is NOT the same thing as a POD being reused across deployments (below).
% Two files sharing name+ext have no date difference to disambiguate by --
% window-based matching cannot separate them, and they need resolving by hand
% (duplicate copies on disk? a genuine same-day re-record?) before matching.
keyNE = inv.name + "|" + inv.ext;
[~,~,gNE] = unique(keyNE);
cNE = accumarray(gNE, 1);
dupNE = find(cNE > 1);
if ~isempty(dupNE)
    fprintf(['\n!! %d exact name+extension combination(s) appear at more than one path.\n' ...
             '   Date-window matching CANNOT separate these -- check whether they are\n' ...
             '   duplicate copies of the same file (backups, merged folders) or a\n' ...
             '   genuine same-day re-record, before running the matcher:\n'], numel(dupNE));
    shown = 0;
    for g = dupNE(:)'
        if shown >= 10, fprintf('   ... and %d more\n', numel(dupNE)-10); break, end
        rows = inv(gNE == g, :);
        fprintf('   %s.%s  (%d copies):\n', rows.name(1), rows.ext(1), height(rows));
        for r = 1:height(rows)
            fprintf('       %s\n', rows.folder(r));
        end
        shown = shown + 1;
    end
end

% same POD+fileNo reused across different deployments -- expected and normal;
% shown only because filename+fileNo alone cannot disambiguate without a date
% or the database's real deployment window, which is what the matcher uses.
ok = inv(inv.parsed, :);
if ~isempty(ok)
    keyTbl = table(ok.podId, fillmissing(ok.fileNo, 'constant', -1), ok.ext, ...
        'VariableNames', {'podId','fileNo','ext'});
    g = groupsummary(keyTbl, {'podId','fileNo','ext'});
    dupG = g(g.GroupCount > 1, :);
    if ~isempty(dupG)
        fprintf(['\n%d (podId, fileNo, ext) combination(s) recur across the dataset -- this is\n' ...
                 'expected for a POD used on more than one deployment, and is NOT by itself an\n' ...
                 'ambiguous match: matchRawToProcessed narrows by each deployment''s actual\n' ...
                 'date window (from the database index) before deciding. Shown for awareness only:\n'], ...
                 height(dupG));
        disp(headRows(dupG, 10));
    end
end
fprintf('\n');
end

function v = headN(v, n)
v = v(1:min(n, numel(v)));
end

function T = headRows(T, n)
T = T(1:min(n, height(T)), :);
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.SaveTo     = string(opts.SaveTo);
opts.Extensions = string(opts.Extensions);
end

function reportProgress(fcn, frac, msg)
if isempty(fcn), return; end
try, fcn(frac, msg); catch, fprintf('%s\n', msg); end
end