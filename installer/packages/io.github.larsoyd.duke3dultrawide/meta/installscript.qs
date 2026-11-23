var steamGame = "/.local/share/Steam/steamapps/common/Duke Nukem 3D";
var primaryScreen = "xrandr --query 2>/dev/null | sed -n 's/.* connected primary \\([0-9]*x[0-9]*\\)+.*/\\1/p' | head -n 1";

function Component()
{
    component.loaded.connect(this, Component.prototype.loaded);
}

Component.prototype.loaded = function()
{
    if (!installer.isInstaller())
        return;
    if (installer.addWizardPage(component, "GameDirPage", QInstaller.ReadyForInstallation)) {
        var page = component.userInterface("GameDirPage");
        page.browse.clicked.connect(this, Component.prototype.browse);
        page.gameDir.textChanged.connect(this, Component.prototype.check);
        page.resolution.textChanged.connect(this, Component.prototype.check);
        var guess = installer.value("GameDir", installer.value("HomeDir") + steamGame);
        page.gameDir.text = installer.fileExists(guess + "/bin/duke3d") ? guess : "";
        var screen = installer.execute("/bin/sh", ["-c", primaryScreen]);
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
    var dirOk = dir != "" && installer.fileExists(dir + "/bin/duke3d");
    var problem = resolutionProblem(res);
    page.state.text = dirOk ? "Found the game." : "No bin/duke3d in this folder.";
    page.resState.text = problem;
    gui.pageWidgetByObjectName("DynamicGameDirPage").complete = dirOk && problem == "";
    installer.setValue("GameDir", dirOk ? dir : "");
    installer.setValue("Resolution", problem == "" ? res : "");
}

Component.prototype.createOperations = function()
{
    component.createOperations();
    var dir = installer.value("GameDir");
    if (!dir || !installer.fileExists(dir + "/bin/duke3d"))
        throw new Error("No game folder chosen, or it has no bin/duke3d.");
    var res = installer.value("Resolution", "");
    if (resolutionProblem(res) != "")
        throw new Error(resolutionProblem(res));
    var tool = "@TargetDir@/duke3d-ultrawide";
    var install = [tool, "install", "--game-dir", dir];
    if (res != "")
        install = install.concat(["--resolution", res]);
    component.addOperation.apply(component, ["Execute", "{0}"].concat(install,
        ["UNDOEXECUTE", tool, "uninstall", "--game-dir", dir]));
}
