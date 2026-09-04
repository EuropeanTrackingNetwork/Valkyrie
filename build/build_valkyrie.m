function build_valkyrie()
% BUILD_VALKYRIE  Compile VALKYRIE.mlapp into a standalone Windows
% executable and installer. Run from anywhere; paths are resolved
% relative to this file's location, so this only works correctly
% if the file stays at <repo root>/build/build_valkyrie.m.
%
% Usage:
%   cd build
%   build_valkyrie
%
% Requires: MATLAB Compiler, MATLAB Compiler SDK (for installer packaging)

    root      = fileparts(fileparts(mfilename('fullpath')));  % repo root
    appSrc    = fullfile(root, 'app_source');
    appFile   = fullfile(appSrc, 'VALKYRIE.mlapp');
    configDir = fullfile(appSrc, 'config');    % nested inside app_source
    helpDir   = fullfile(appSrc, 'helpers');   % nested inside app_source
    gfxDir    = fullfile(appSrc, 'graphics');  % nested inside app_source
    outDir    = 'O:\ValkyrieBuild';   % shared network drive — avoids OneDrive
                                       % file-locking and Windows path-length limits
                                       % during installer packaging, and keeps
                                       % build output accessible to the whole team

    requiredFolders = {appSrc, configDir, helpDir, gfxDir};
    for i = 1:numel(requiredFolders)
        if ~isfolder(requiredFolders{i})
            error('build_valkyrie:missingFolder', ...
                'Expected folder not found: %s', requiredFolders{i});
        end
    end
    if ~isfile(appFile)
        error('build_valkyrie:missingApp', 'App file not found: %s', appFile);
    end

    addpath(appSrc, configDir, helpDir, gfxDir);

    ver = valkyrieVersion();
    fprintf('Building VALKYRIE v%s\n', ver);
    fprintf('  App:     %s\n', appFile);
    fprintf('  Config:  %s\n', configDir);
    fprintf('  Helpers: %s\n', helpDir);
    fprintf('  Graphics: %s\n', gfxDir);

    exeArgs = { ...
        'ExecutableName',  'VALKYRIE', ...
        'ExecutableVersion', ver, ...
        'AdditionalFiles', {configDir, helpDir, gfxDir}, ...
        'OutputDir',        fullfile(outDir, 'exe'), ...
        'Verbose',          'on'};

    % Optional branding assets — only added if present, so the build
    % doesn't fail before these assets exist.
    iconFile   = fullfile(gfxDir, 'icon64.png');
    splashFile = fullfile(gfxDir, 'valkyrieV1.png');
    if isfile(iconFile)
        exeArgs = [exeArgs, {'ExecutableIcon', iconFile}];
    end
    if isfile(splashFile)
        exeArgs = [exeArgs, {'ExecutableSplashScreen', splashFile}];
    end

    % --- compile executable ---
    res = compiler.build.standaloneWindowsApplication(appFile, exeArgs{:});

    % --- package installer ---
    exePath = fullfile(outDir, 'exe', 'VALKYRIE.exe');

    installerArgs = { ...
        'InstallerName',   "VALKYRIE_" + ver + "_Setup", ...
        'ApplicationName', 'VALKYRIE', ...
        'AuthorCompany',   'Aarhus University & VLIZ/European Tracking Network', ...
        'Version',          ver, ...
        'Summary',         'Click detection extraction and harmonization tool', ...
        'RuntimeDelivery', 'installer', ...   % switch to 'web' for a smaller, online-only installer
        'OutputDir',        fullfile(outDir, 'installer')};

    % InstallerIcon is what actually gets used as the icon for the
    % desktop/Start Menu shortcut (see icon_48 -> applicationIcon in
    % compiler.package.installer's source). ExecutableIcon above only
    % affects the .exe's own embedded icon, not the shortcut.
    % Shortcut must point at a file that's actually being packaged
    % (here, the compiled exe) — it is NOT an icon path itself.
    if isfile(iconFile)
        installerArgs = [installerArgs, ...
            {'InstallerIcon', iconFile, ...
             'AddRemoveProgramsIcon', iconFile, ...
             'Shortcut', exePath}];
    end

    compiler.package.installer(res, installerArgs{:});

    fprintf('Done.\n');
    fprintf('  Executable: %s\n', fullfile(outDir, 'exe'));
    fprintf('  Installer:  %s\n', fullfile(outDir, 'installer'));
end