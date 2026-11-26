var win = systemInfo.kernelType == "winnt";

function Controller()
{
    if (!installer.isInstaller())
        return;
    if (win)
        installer.setValue("TargetDir", installer.environmentVariable("LOCALAPPDATA") + "/duke3d-megaton-ultrawide-fix");
    if (installer.isCommandLineInstance())
        removeEarlier();
}

function earlierTool()
{
    return installer.value("TargetDir") + "/uninstall-ultrawide-fix" + (win ? ".exe" : "");
}

// an earlier install blocks the target folder, so its own uninstaller puts the game back first
function removeEarlier()
{
    var tool = earlierTool();
    if (!installer.fileExists(tool))
        return;
    installer.execute(tool, ["purge", "--confirm-command"]);
    if (installer.fileExists(tool))
        installer.performOperation("Delete", [tool]);
    installer.performOperation("Rmdir", [installer.value("TargetDir")]);
}

Controller.prototype.IntroductionPageCallback = function()
{
    var page = gui.currentPageWidget();
    if (page == null)
        return;
    var earlier = installer.fileExists(earlierTool()) ?
        "An earlier install of this fix was found. It is removed first, which puts the original game file back " +
        "before the new one is patched.<br><br>" : "";
    page.MessageLabel.setText(
        "This installs a fix for Duke Nukem 3D: Megaton Edition so the game can run at " +
        "resolutions wider than 2560 pixels, such as 3440x1440. It works with the native Linux game " +
        "and with the Windows game, on Windows or through Proton.<br><br>" +
        "It changes the game's own program file in your Steam folder and keeps a copy of the original. " +
        "You can undo it at any time with the uninstaller this setup leaves behind.<br><br>" + earlier +
        "Please quit the game before you continue.");
}

Controller.prototype.TargetDirectoryPageCallback = function()
{
    removeEarlier();
}
