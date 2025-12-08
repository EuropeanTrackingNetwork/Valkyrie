
function [errorMsg, formattedDate] = validateDatetime_amb(inputStr, minDate, dtFormats)
% Validate and normalize datetime input, preferring dd/MM when ambiguous.
% Output: UTC datetime with ISO-8601 display yyyy-MM-ddTHH:mm:ssZ.

    errorMsg = "";
    formattedDate = NaT;
    try
        formattedDate.TimeZone = 'UTC'; 
    catch
    end

    s = strtrim(string(inputStr));
    if strlength(s) == 0
        errorMsg = [errorMsg, "- Invalid datetime: empty string."];
        return;
    end

    % ---- 1) Try your non-ambiguous formats first (from JSON) ----
    if isstring(dtFormats) || ischar(dtFormats)
        dtFormats = cellstr(dtFormats);
    end
    for i = 1:numel(dtFormats)
        fmt = dtFormats{i};
        try
            dt = datetime(s, 'InputFormat', fmt, 'TimeZone', 'UTC');
            dt.Format = "yyyy-MM-dd'T'HH:mm:ss'Z'";
            formattedDate = dt;
            if dt < minDate
                errorMsg = [errorMsg, " Check that date is added correctly."];
            end
            return;
        catch
        end
    end

    % ---- 2) Handle Excel-style slash dates; decide dd/MM vs MM/dd by the numbers ----
    % Extract only the date part; don't try to capture time in regex.
    dtTok = regexp(s, '^\s*(\d{1,2})/(\d{1,2})/(\d{4})', 'tokens', 'once');
    if ~isempty(dtTok)
        a = str2double(dtTok{1}); % first component
        b = str2double(dtTok{2}); % second component

        % Decide date order (prefer dd/MM when ambiguous)
        if a <= 12 && b <= 12
            dateFmts = {'dd/MM/uuuu', 'd/M/uuuu', 'MM/dd/uuuu', 'M/d/uuuu'}; % ambiguous -> dd/MM first
        elseif a <= 12 && b > 12
            dateFmts = {'MM/dd/uuuu', 'M/d/uuuu'};                              % clearly MM/dd
        else % a > 12 && b <= 12
            dateFmts = {'dd/MM/uuuu', 'd/M/uuuu'};                              % clearly dd/MM
        end

        % Try multiple time patterns and date-only as candidates.
        % (We don't require them in regex; datetime will accept 1-2 digits for HH/mm/ss with HH/mm/ss tokens.)
        timeParts = { ' HH:mm:ss', ' HH:mm', '' };

        candidates = {};
        for df = 1:numel(dateFmts)
            for tp = 1:numel(timeParts)
                candidates{end+1} = [dateFmts{df} timeParts{tp}]; %#ok<AGROW>
            end
        end

        for j = 1:numel(candidates)
            fmt = candidates{j};
            try
                dt = datetime(s, 'InputFormat', fmt, 'TimeZone', 'UTC');
                dt.Format = "yyyy-MM-dd'T'HH:mm:ss'Z'";
                formattedDate = dt;

                if dt < minDate
                    errorMsg = [errorMsg, " Check that date is added correctly."];
                end
                return;
            catch
            end
        end
    end

    % ---- 3) Excel serial fallback (e.g., "45276.5") ----
    if ~isempty(regexp(s, '^\s*\d+(\.\d+)?\s*$', 'once'))
        val = str2double(s);
        if ~isnan(val)
            try
                dt = datetime(val, 'ConvertFrom', 'excel', 'TimeZone', 'UTC');
                dt.Format = "yyyy-MM-dd'T'HH:mm:ss'Z'";
                formattedDate = dt;

                if dt < minDate
                    errorMsg = [errorMsg, " Check that date is added correctly."];
                end
                return;
            catch
            end
        end
    end

    % ---- 4) Fail with guidance ----
    if isnat(formattedDate)
        try
            formattedDate.TimeZone = 'UTC';
            formattedDate.Format = "yyyy-MM-dd'T'HH:mm:ss'Z'";
        catch
        end
        errorMsg = [errorMsg, "- Invalid datetime format. Please use format: yyyy-MM-ddTHH:mm:ssZ."];
    end
end
