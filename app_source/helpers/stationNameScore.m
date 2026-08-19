% =========================================================================
function score = stationNameScore(stationName, fnameNorm)
% STATIONNAMESCORE
% Returns a [0,1] similarity score between a metadata STATION_NAME and a
% (already-lowercased) filename string.
%
% Strategy — two checks, best score wins:
%
%   1) COMPACT match: strip all separators from the station name and look
%      for it as a substring in the filename. This handles short codes like
%      "FB 1" -> "fb1", "GB 2" -> "gb2", or "Anholt E" -> "anholte".
%      Score = 1.0 if found, 0 otherwise.
%
%   2) WORD match: split station name on separators, look for each token
%      (any length) in the filename, return fraction found. This catches
%      longer names like "Anholt East" where compacting gives "anholteast"
%      which may not appear verbatim in the filename.
%
% The higher of the two scores is returned, so short codes and long names
% are both handled well.
%
% Examples:
%   "FB1"       vs "fb1_pod123 2024 05 01"       -> 1.0 (compact hit)
%   "FB 1"      vs "fb1_pod123 2024 05 01"       -> 1.0 (compact hit)
%   "FB1a"      vs "fb1a_pod123 2024 05 01"      -> 1.0 (compact hit)
%   "Anholt E"  vs "anholte_pod123 2024 05 01"   -> 1.0 (compact hit)
%   "Anholt East" vs "anholt_pod123 2024 05 01"  -> 0.5 (word: "anholt" found, "east" not)
%   "GB2"       vs "fb1_pod123 2024 05 01"       -> 0.0 (neither match)

    stnNorm = lower(char(stationName));

    % --- Score 1: compact (remove all separators, match as substring) ---
    compact      = regexprep(stnNorm, '[^a-z0-9]', '');   % keep only alphanumeric
    if ~isempty(compact)
        compactScore = double(contains(fnameNorm, compact));
    else
        compactScore = 0;
    end

    % --- Score 2: word-level fraction ---
    words     = strsplit(stnNorm, {' ', '-', '_', '.'});
    words     = words(strlength(words) >= 1);   % keep all tokens, even single chars
    if isempty(words)
        wordScore = 0;
    else
        hits = 0;
        for w = 1:numel(words)
            if contains(fnameNorm, words{w})
                hits = hits + 1;
            end
        end
        wordScore = hits / numel(words);
    end

    score = max(compactScore, wordScore);
end
