function realPk = RawToRealPk(rawPk, IPI, HasExtendedAmps)
% Converts raw amplitude values to real linear peak values.
% Inputs:
% - rawPk: vector of raw amplitude values (e.g., clicksinminute(:,11))
% - IPI: vector of IPIatMax values (+1 already applied)
% - HasExtendedAmps: true/false depending on FPGA version
%
% Output:
% - realPk: vector of real amplitude values

    persistent ClippedPkArr RTC

    % Build ClippedPkArr and RTC only once
    if isempty(ClippedPkArr)
        % Build RTC (RiseTimeConversionArr)
        RTC = zeros(1, 33); % Index from 223 to 255
        for pk = 223:255
            if pk < 232
                RTC(pk - 222) = 32 + (231 - pk) * 4;
            elseif pk < 240
                RTC(pk - 222) = 16 + (239 - pk) * 2;
            else
                RTC(pk - 222) = 255 - pk;
            end
        end

        % Build extended amplitude lookup table
        ClippedPkArr = zeros(256, 256); % [rawPk+1][IPI]
        for ipi = 10:256
            maxAllowed = ipi * 50; % constMaxAmpKHZScaler
            exceeded = false;
            for pk = 223:255
                if ~exceeded
                    val = round((4000 / ipi)^(-0.75) * 10^(5.24 * (RTC(pk - 222)^-0.11)));
                    if val > maxAllowed
                        val = maxAllowed;
                        exceeded = true;
                    end
                else
                    val = maxAllowed;
                end
                val = max(384, val); % constMinPkampAllowed
                ClippedPkArr(pk+1, ipi) = min(maxAllowed, val);
            end
        end
    end

    % Input cleanup
    rawPk = double(rawPk);
    rawPk(rawPk < 2) = 2;  % enforce lower bound
    IPI = double(IPI);

    % Default: use corrected Nick/Java logic for real amplitude
    realPk = rawPk; % initialize output

    if HasExtendedAmps
        % Apply logic: <128 → *2, ≥128 → +128
        realPk(rawPk < 128) = 2 * rawPk(rawPk < 128);
        realPk(rawPk >= 128) = rawPk(rawPk >= 128) + 128;

        % Extended correction for rawPk > 222 and valid IPI range
        extendedMask = rawPk > 222 & IPI >= 10 & IPI <= 256;
        if any(extendedMask)
            realPk(extendedMask) = ClippedPkArr(sub2ind(size(ClippedPkArr), ...
                rawPk(extendedMask) + 1, IPI(extendedMask)));
        end
    else
        % If no extended amps, rawPk is used directly
        realPk = rawPk;
    end
end
