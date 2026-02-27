function tbl2 = filterByReceiverProject(tbl, chosenProject)
chosenProject = strtrim(string(chosenProject));

proj = strtrim(string(tbl.RCV_PROJECT));
proj(strlength(proj)==0 | ismissing(proj) | strcmpi(proj,"nan")) = missing;

keepIdx = (proj == chosenProject);
tbl2 = tbl(keepIdx, :);

if height(tbl2) == 0
    error("Filtering produced 0 rows. Chosen project not found?");
end
end