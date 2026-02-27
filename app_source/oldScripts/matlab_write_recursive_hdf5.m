function matlab_write_recursive_hdf5(filename, location, data)
% Writes a struct into a hdf5 file.
    if isa(data, 'struct')
        fns = fieldnames(data);
        for i = 1:length(fns)
            name = fns{i};
            loc = strcat(location, '/', name);
            field = data.(name);
            matlab_write_recursive_hdf5(filename, loc, field);
        end
    else
        if exist(filename, 'file')
            hdf5write(filename, location, data, 'WriteMode', 'append');
        else
            hdf5write(filename, location, data);
        end
    end
end