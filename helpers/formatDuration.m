%Helper function to change date time duration to a string format

function outStr = formatDuration(dur)
    if isempty(dur) || isnan(days(dur))
        outStr = "NaN";
        return
    end

    % Take only the first value if multiple are given
    dur = dur(1);

    d = floor(days(dur));
    h = floor(hours(dur - days(d)));
    m = floor(minutes(dur - days(d) - hours(h)));

    outStr = sprintf('%d days, %d hours, %d minutes', d, h, m);
end
