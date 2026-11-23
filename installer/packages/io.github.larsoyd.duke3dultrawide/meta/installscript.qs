var steamGame = "/.local/share/Steam/steamapps/common/Duke Nukem 3D";

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
        var guess = installer.value("GameDir", installer.value("HomeDir") + steamGame);
        page.gameDir.text = installer.fileExists(guess + "/bin/duke3d") ? guess : "";
        Component.prototype.check(page.gameDir.text);
    }
}

Component.prototype.browse = function()
{
    var page = component.userInterface("GameDirPage");
    var dir = QFileDialog.getExistingDirectory("Duke Nukem 3D folder", page.gameDir.text);
    if (dir)
        page.gameDir.text = dir;
}

Component.prototype.check = function(dir)
{
    var page = component.userInterface("GameDirPage");
    var ok = dir != "" && installer.fileExists(dir + "/bin/duke3d");
    page.state.text = ok ? "Found the game." : "No bin/duke3d in this folder.";
    gui.pageWidgetByObjectName("DynamicGameDirPage").complete = ok;
    if (ok)
        installer.setValue("GameDir", dir);
}

Component.prototype.createOperations = function()
{
    component.createOperations();
    var dir = installer.value("GameDir");
    if (!dir || !installer.fileExists(dir + "/bin/duke3d"))
        throw new Error("No game folder chosen, or it has no bin/duke3d.");
    var tool = "@TargetDir@/duke3d-ultrawide";
    component.addOperation("Execute", "{0}", tool, "install", "--game-dir", dir,
                           "UNDOEXECUTE", tool, "uninstall", "--game-dir", dir);
}
