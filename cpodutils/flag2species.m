function [species] = flag2species(flag)

%FLAG2SPECIES Converts a species flag to a string description
switch (flag)
    case 1
        species = 'NBHF';
    case 2
        species = 'DOLPHIN';
    case 3
        species= 'SONAR';
    otherwise
        species='UNKNOWN';
end

end



