
function [errorMsg, formattedDate] = validateDatetime_amb(inputStr, minDate, dtFormats)

% Validate and normalize datetime input, preferring dd/MM when ambiguous.
% Output: UTC datetime with ISO-8601 display yyyy-MM-ddTHH:mm:ss'Z'
%
% Empty input returns NaT with no error message (caller decides if that is acceptable).


    errorMsg = "";
    s = strtrim(string(inputStr));

    if strlength(s) == 0
        formattedDate = NaT('TimeZone','UTC');
        return; % no error here — caller decides based on mandatory status
    end

    % Ensure dtFormats is a cell
    if isstring(dtFormats) || ischar(dtFormats)
        dtFormats = cellstr(dtFormats);
    end

    % ---- 1) Try non-ambiguous formats from JSON ----
    for i = 1:numel(dtFormats)
        fmt = dtFormats{i};
        try
            dt = datetime(s, 'InputFormat', fmt, 'TimeZone', 'UTC');

            % ---- Reject unreasonable dates immediately ----
            if year(dt) < 1900
                continue;  % try next format
            end

            dt.Format = "yyyy-MM-dd'T'HH:mm:ss'Z'";
            formattedDate = dt;
            if dt < minDate
                errorMsg = "Date earlier than allowed minimum.";
            end
            return;
        catch
            % try next
        end
    end

    % ---- 2) Handle slash dates (dd/MM vs MM/dd) by numbers ----
    dtTok = regexp(s, '^\s*(\d{1,2})/(\d{1,2})/(\d{4})', 'tokens', 'once');
    if ~isempty(dtTok)
        a = str2double(dtTok{1}); % first component
        b = str2double(dtTok{2}); % second component

        if a <= 12 && b <= 12
            dateFmts = {'MM/dd/uuuu', 'M/d/uuuu'}; % prefer MM/dd
        elseif a <= 12 && b > 12
            dateFmts = {'MM/dd/uuuu', 'M/d/uuuu'};
        else
            dateFmts = {'dd/MM/uuuu', 'd/M/uuuu'};
        end

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
                    errorMsg = "Date earlier than allowed minimum.";
                end
                return;
            catch
                % continue
            end
        end
    end

    % ---- 3) Excel serial fallback ----
    if ~isempty(regexp(s, '^\s*\d+(\.\d+)?\s*$', 'once'))
        val = str2double(s);
        if ~isnan(val)
            try
                dt = datetime(val, 'ConvertFrom', 'excel', 'TimeZone', 'UTC');
                dt.Format = "yyyy-MM-dd'T'HH:mm:ss'Z'";
                formattedDate = dt;
                if dt < minDate
                    errorMsg = "Date earlier than allowed minimum.";
                end
                return;
            catch
                % continue
            end
        end
    end


    % 4) As an extra robustness step, try MATLAB auto-parse (often handles "04-Sep-2022 08:43:00")
    % OBS: This does not work if format is dd/MM/yy HH:mm
    try
        dt = datetime(s, 'TimeZone', 'UTC'); % let MATLAB infer
        dt.Format = "yyyy-MM-dd'T'HH:mm:ss'Z'";
        formattedDate = dt;
        if dt < minDate
            errorMsg = "Date earlier than allowed minimum.";
        end
        return;
    catch
    end

    % ---- 5) Fail with guidance ----
    formattedDate = NaT('TimeZone','UTC');
    errorMsg = "- Invalid datetime format. Please use format: yyyy-MM-ddTHH:mm:ssZ.";
end