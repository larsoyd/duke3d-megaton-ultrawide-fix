function Controller()
{
    if (systemInfo.kernelType == "winnt" && installer.isInstaller())
        installer.setValue("TargetDir", installer.environmentVariable("LOCALAPPDATA") + "/duke3d-megaton-ultrawide-fix");
}

Controller.prototype.IntroductionPageCallback = function()
{
    var page = gui.currentPageWidget();
    if (page == null)
        return;
    page.MessageLabel.setText(
        "This installs a fix for Duke Nukem 3D: Megaton Edition so the game can run at " +
        "resolutions wider than 2560 pixels, such as 3440x1440. It works with the native Linux game " +
        "and with the Windows game, on Windows or through Proton.<br><br>" +
        "It changes the game's own program file in your Steam folder and keeps a copy of the original. " +
        "You can undo it at any time with the uninstaller this setup leaves behind.<br><br>" +
        "Please quit the game before you continue.");
}
