function S = scanMinICIOutputs(folderOrFiles, varargin)
%SCANMINICIOUTPUTS Summarise minICI output files so they can be matched cheaply.
%
%   S = scanMinICIOutputs("C:\minici_out")
%   S = scanMinICIOutputs(fileList, 'KeepICITimes', false)
%
%   Reads only the six columns needed for matching, and returns one row per
%   (output file x species):
%
%       file             full path
%       newFilename      the 'filename' value written inside the file
%       species
%       nRows            rows in the file for this species
%       nICI             rows with a non-missing min_ici
%       firstDatetime / lastDatetime
%       iciTimes         datetimes carrying a min_ici (cell, 1 datetime vector)
%       podId, station, stationBase, nameDate  (parsed from newFilename)
%
%   iciTimes is what lets matchFilesToDeployments run the count invariant
%   "number of min_ici values inside the database window == number of
%   click-positive database rows", which is the check that catches a
%   mis-assigned deployment. Pass 'KeepICITimes',false to save memory and skip it.
%
%   Part of the minICI back-fill toolset.

opts = struct('KeepICITimes', true, 'DatetimeFormat', "yyyy-MM-dd HH:mm:ss", ...
    'SaveTo', "", 'ProgressFcn', []);
opts = parseOpts(opts, varargin);

files = resolveFiles(folderOrFiles);
if isempty(files)
    error('scanMinICIOutputs:noFiles', 'No CSV files found.');
end

rows = cell(numel(files),1);
for k = 1:numel(files)
    reportProgress(opts.ProgressFcn, k/numel(files), ...
        sprintf('Scanning %d/%d: %s', k, numel(files), files(k)));

    want = {'filename','datetime','quality','species','min_ici','number_clicks_filtered'};
    io = detectImportOptions(files(k), 'TextType', 'string');
    sel = intersect(want, io.VariableNames, 'stable');
    io.SelectedVariableNames = sel;
    io = setvartype(io, intersect({'min_ici'}, sel), 'double');
    T = readtable(files(k), io);

    dt = T.datetime;
    if ~isdatetime(dt)
        dt = datetime(string(dt), 'InputFormat', char(opts.DatetimeFormat));
    end
    dt.Format = 'yyyy-MM-dd HH:mm:ss';

    sp  = upper(string(T.species));
    ici = ~ismissing(T.min_ici);

    for s = reshape(unique(sp), 1, [])
        m = sp == s;
        r = table(files(k), string(T.filename(find(m,1))), s, sum(m), sum(ici & m), ...
            min(dt(m)), max(dt(m)), ...
            'VariableNames', {'file','newFilename','species','nRows','nICI', ...
                              'firstDatetime','lastDatetime'});
        if opts.KeepICITimes
            r.iciTimes = {sort(dt(ici & m))};
        else
            r.iciTimes = {datetime.empty};
        end
        rows{k} = [rows{k}; r];
    end
end

S = vertcat(rows{:});
P = parsePodName(S.newFilename);
S.podId       = P.podId;
S.station     = P.station;
S.stationBase = P.stationBase;
S.nameDate    = P.nameDate;
S = sortrows(S, {'podId','firstDatetime'});

if strlength(opts.SaveTo) > 0
    save(opts.SaveTo, 'S');
end
end

% =======================================================================
function files = resolveFiles(x)
x = string(x);
if numel(x) == 1 && isfolder(x)
    d = dir(fullfile(x, '*.csv'));
    files = string(fullfile({d.folder}, {d.name}))';
else
    files = x(:);
end
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.SaveTo         = string(opts.SaveTo);
opts.DatetimeFormat = string(opts.DatetimeFormat);
end

function reportProgress(fcn, frac, msg)
if isempty(fcn), fprintf('%s\n', msg); return; end
try, fcn(frac, msg); catch, fprintf('%s\n', msg); end
end
