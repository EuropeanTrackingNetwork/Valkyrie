function info = inspectBigFile(bigCsv, varargin)
%INSPECTBIGFILE Peek at the raw bytes of the export before trusting a delimiter
%or datetime format for it.
%
%   info = inspectBigFile(bigCsv)
%   info = inspectBigFile(bigCsv, 'NumLines', 2000)
%
%   Reads the file with fopen/fgetl -- never through a table parser, so nothing
%   is pre-interpreted -- and reports what's actually on disk. This exists
%   because a delimiter or date format only ever seen through an Excel
%   copy-paste cannot be trusted: pasting cells into a text editor always comes
%   out tab-separated regardless of the source file's real delimiter, and Excel
%   reformats dates to your locale's short-date display, which may not match
%   what's stored in the file at all.
%
%   Costs a few KB of reads regardless of the file's total size -- safe to run
%   on the full 13 GB export.
%
%   info fields
%       .delimiter          the character that appears a constant number of
%                            times across every sampled line (tab/comma/
%                            semicolon), or "" if none does
%       .header             header line split on that delimiter
%       .datetimeColumn     name of the field that looks like the datetime column
%       .sampleDatetimes    a few raw datetime strings from that column, verbatim
%       .dateOrderGuess     "yyyy-MM-dd" (ISO, unambiguous), "M/d/yyyy",
%                            "d/M/yyyy", or "ambiguous" -- inferred from actually
%                            finding a token >12 in one position across the
%                            sample, never assumed
%       .hasSeconds         whether the time part carries seconds
%       .rawLines           header + first few data lines, verbatim, with the
%                            guessed delimiter made visible as "|"
%
%   Always look at .sampleDatetimes and .rawLines yourself before trusting
%   .dateOrderGuess -- "ambiguous" means every sampled date had both components
%   <=12 and the order genuinely cannot be inferred from the data; every other
%   verdict is only as good as the sample it was drawn from.
%
%   Part of the minICI back-fill toolset.

opts = struct('NumLines', 2000);
opts = parseOpts(opts, varargin);

fid = fopen(bigCsv, 'r');
if fid < 0, error('inspectBigFile:cannotOpen', 'Cannot open %s', bigCsv); end
cleanup = onCleanup(@() fclose(fid));

lines = strings(opts.NumLines, 1);
n = 0;
while n < opts.NumLines
    l = fgetl(fid);
    if ~ischar(l), break, end
    n = n + 1;
    lines(n) = string(l);
end
lines = lines(1:n);
if n < 2
    error('inspectBigFile:tooFewLines', 'Fewer than 2 lines read from %s', bigCsv);
end

%% ---- delimiter: the char with a constant count across every line ------
candidates = ["\t", ",", ";"];
counts = zeros(numel(candidates), n);
for c = 1:numel(candidates)
    counts(c,:) = count(lines, candidates(c));
end
consistent = counts(:,1) > 0 & all(counts == counts(:,1), 2);
if any(consistent)
    d = candidates(find(consistent, 1));
else
    % fall back to whichever is most common and least variable
    variability = std(double(counts), 0, 2) ./ max(1, mean(double(counts), 2));
    [~, b] = min(variability);
    d = candidates(b);
    warning('inspectBigFile:inconsistentDelimiter', ...
        ['No delimiter appears the same number of times on every sampled line ' ...
         '(ragged rows, embedded newlines, or a mixed file?). Guessing "%s" -- ' ...
         'verify against .rawLines before trusting it.'], displayDelim(d));
end
info.delimiter = d;

header = split(lines(1), d);
header = unquote(strtrim(header));
info.header = header;

%% ---- find the datetime column ------------------------------------------
dtCol = find(strcmpi(header, "datetime"), 1);
if isempty(dtCol)
    dtCol = find(contains(header, "date", 'IgnoreCase', true), 1);
end
if isempty(dtCol)
    warning('inspectBigFile:noDatetimeColumn', 'No column looked like a datetime field.');
    info.datetimeColumn = "";
    info.sampleDatetimes = strings(0,1);
    info.dateOrderGuess = "unknown";
    info.hasSeconds = NaN;
else
    info.datetimeColumn = header(dtCol);
    nData = min(n-1, 500);
    samples = strings(nData,1);
    for k = 1:nData
        parts = split(lines(k+1), d);
        if numel(parts) >= dtCol
            samples(k) = unquote(strtrim(parts(dtCol)));
        end
    end
    samples = samples(strlength(samples) > 0);
    info.sampleDatetimes = samples(1:min(10, numel(samples)));

    [info.dateOrderGuess, info.hasSeconds] = inferDateOrder(samples);
end

%% ---- raw lines with the delimiter made visible -------------------------
nShow = min(5, n);
info.rawLines = strrep(lines(1:nShow), d, "|");

printSummary(info, bigCsv);
end

% =======================================================================
function [order, hasSeconds] = inferDateOrder(samples)
if isempty(samples)
    order = "unknown"; hasSeconds = NaN; return
end

% split "date time" on the first space
firstTok = strings(numel(samples),1); timeTok = strings(numel(samples),1);
for k = 1:numel(samples)
    p = split(samples(k), " ");
    firstTok(k) = p(1);
    if numel(p) > 1, timeTok(k) = p(2); end
end

hasSeconds = mean(count(timeTok, ":") >= 2) > 0.5;

% ISO check: first token starts with a 4-digit year
isIso = ~cellfun(@isempty, regexp(firstTok, '^\d{4}-\d{1,2}-\d{1,2}$', 'once'));
if mean(isIso) > 0.5
    order = "yyyy-MM-dd";
    return
end

% otherwise expect d/M/yyyy or M/d/yyyy (also tolerate '-' as the separator)
tok = regexp(firstTok, '^(\d{1,2})[/\-](\d{1,2})[/\-]\d{2,4}$', 'tokens', 'once');
tok = tok(~cellfun(@isempty, tok));
if isempty(tok)
    order = "unknown"; return
end
a = cellfun(@(t) str2double(t{1}), tok);
b = cellfun(@(t) str2double(t{2}), tok);

firstOver12  = sum(a > 12);
secondOver12 = sum(b > 12);

if firstOver12 > 0 && secondOver12 == 0
    order = "d/M/yyyy";       % first component must be the day
elseif secondOver12 > 0 && firstOver12 == 0
    order = "M/d/yyyy";       % second component must be the day
elseif firstOver12 > 0 && secondOver12 > 0
    order = "inconsistent";   % different rows disagree -- mixed file, investigate
else
    order = "ambiguous";      % every sampled value <=12 in both positions
end
end

function s = displayDelim(d)
if d == "\t", s = "TAB"; else, s = d; end
end

function s = unquote(s)
%UNQUOTE Strip a single layer of matching leading/trailing quote characters.
%The real export quotes every field ("id_pk","deployment_fk",...), which
%breaks the ISO-date regex anchor ('^\d{4}...') if left in place.
s = regexprep(s, '^"(.*)"$', '$1');
s = regexprep(s, "^'(.*)'$", '$1');
end

function printSummary(info, bigCsv)
fprintf('\n=== inspectBigFile: %s ===\n', bigCsv);
fprintf('delimiter        : %s\n', displayDelim(info.delimiter));
fprintf('columns          : %d\n', numel(info.header));
fprintf('datetime column  : %s\n', info.datetimeColumn);
fprintf('date order guess : %s\n', info.dateOrderGuess);
if info.dateOrderGuess == "ambiguous"
    fprintf(['                   every sampled date had both components <=12; ' ...
             'order cannot be inferred from this sample. Widen NumLines or\n' ...
             '                   check a known deployment date by hand.\n']);
elseif info.dateOrderGuess == "inconsistent"
    fprintf(['                   different rows implied different orders -- ' ...
             'this looks like a mixed-format file. Investigate before proceeding.\n']);
end
if ~isnan(info.hasSeconds)
    fprintf('has seconds      : %s\n', string(info.hasSeconds));
end
fprintf('sample datetimes : %s\n', strjoin(info.sampleDatetimes, ' | '));
fprintf('\nraw lines (delimiter shown as |):\n');
for k = 1:numel(info.rawLines)
    fprintf('  %s\n', info.rawLines(k));
end
fprintf('\n');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
end
