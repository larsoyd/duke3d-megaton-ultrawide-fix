var win = systemInfo.kernelType == "winnt";
var gameExes = ["/bin/duke3d", "/bin/duke3d.exe"];
var linuxScreen = "x=$(xrandr --query 2>/dev/null); { echo \"$x\" | sed -n 's/.* connected primary \\([0-9]*x[0-9]*\\)+.*/\\1/p'; echo \"$x\" | sed -n 's/.* connected \\([0-9]*x[0-9]*\\)+.*/\\1/p'; } | head -n 1";
var windowsScreen = "Get-CimInstance Win32_VideoController | Where-Object CurrentHorizontalResolution | " +
    "Select-Object -First 1 | ForEach-Object { '' + $_.CurrentHorizontalResolution + 'x' + $_.CurrentVerticalResolution }";
var primaryScreen = win ? ["powershell", ["-NoProfile", "-NonInteractive", "-Command", windowsScreen]]
                        : ["/bin/sh", ["-c", linuxScreen]];

function hasGame(dir)
{
    for (var i = 0; i < gameExes.length; i++) {
        if (dir != "" && installer.fileExists(dir + gameExes[i]))
            return true;
    }
    return false;
}

function steamGuess()
{
    var steam = installer.value("HomeDir") + "/.local/share/Steam";
    if (win) {
        steam = installer.value("HKEY_CURRENT_USER\\Software\\Valve\\Steam\\SteamPath", "");
        if (steam == "")
            steam = installer.environmentVariable("ProgramFiles(x86)") + "/Steam";
    }
    return steam + "/steamapps/common/Duke Nukem 3D";
}

function Component()
{
    component.loaded.connect(this, Component.prototype.loaded);
}

Component.prototype.loaded = function()
{
    if (!installer.isInstaller())
        return;
    installer.setDefaultPageVisible(QInstaller.ComponentSelection, false);
    installer.setDefaultPageVisible(QInstaller.StartMenuSelection, false);
    if (installer.addWizardPage(component, "GameDirPage", QInstaller.ReadyForInstallation)) {
        var page = component.userInterface("GameDirPage");
        page.browse.clicked.connect(this, Component.prototype.browse);
        page.gameDir.textChanged.connect(this, Component.prototype.check);
        page.resolution.textChanged.connect(this, Component.prototype.check);
        var guess = installer.value("GameDir", steamGuess());
        page.gameDir.text = hasGame(guess) ? guess : "";
        var screen = installer.execute(primaryScreen[0], primaryScreen[1]);
        page.resolution.text = installer.value("Resolution", screen ? String(screen[0]).trim() : "");
        Component.prototype.check();
    }
}

Component.prototype.browse = function()
{
    var page = component.userInterface("GameDirPage");
    var dir = QFileDialog.getExistingDirectory("Duke Nukem 3D folder", page.gameDir.text);
    if (dir)
        page.gameDir.text = dir;
}

function resolutionProblem(res)
{
    if (res == "")
        return "";
    var m = /^(\d+)x(\d+)$/.exec(res);
    if (!m)
        return "Use WIDTHxHEIGHT, for example 3440x1440.";
    var w = parseInt(m[1], 10), h = parseInt(m[2], 10);
    if (w < 320 || h < 200 || w > 8192 || h > 1600)
        return "The game supports up to 8192 wide and 1600 high.";
    return "";
}

Component.prototype.check = function()
{
    var page = component.userInterface("GameDirPage");
    var dir = page.gameDir.text;
    var res = page.resolution.text.trim();
    var dirOk = hasGame(dir);
    var problem = resolutionProblem(res);
    page.state.text = dirOk ? "Found the game." : "This folder has no bin/duke3d or bin/duke3d.exe.";
    page.resState.text = problem;
    gui.pageWidgetByObjectName("DynamicGameDirPage").complete = dirOk && problem == "";
    installer.setValue("GameDir", dirOk ? dir : "");
    installer.setValue("Resolution", problem == "" ? res : "");
}

Component.prototype.createOperations = function()
{
    component.createOperations();
    var dir = installer.value("GameDir");
    if (!hasGame(dir))
        throw new Error("No game folder chosen, or it has no bin/duke3d or bin/duke3d.exe.");
    var res = installer.value("Resolution", "");
    if (resolutionProblem(res) != "")
        throw new Error(resolutionProblem(res));
    var tool = "@TargetDir@/duke3d-ultrawide" + (win ? ".exe" : "");
    var install = [tool, "install", "--game-dir", dir];
    if (res != "")
        install = install.concat(["--resolution", res]);
    component.addOperation.apply(component, ["Execute", "{0}"].concat(install,
        ["UNDOEXECUTE", tool, "uninstall", "--game-dir", dir]));
}
