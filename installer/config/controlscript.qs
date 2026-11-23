function Controller()
{
}

Controller.prototype.IntroductionPageCallback = function()
{
    var page = gui.currentPageWidget();
    if (page == null)
        return;
    page.MessageLabel.setText(
        "This installs a fix for Duke Nukem 3D: Megaton Edition on Linux so the game can run at " +
        "resolutions wider than 2560 pixels, such as 3440x1440.<br><br>" +
        "It changes the game's own program file in your Steam folder and keeps a copy of the original. " +
        "You can undo it at any time with the uninstaller this setup leaves in your home folder.<br><br>" +
        "Please quit the game before you continue.");
}
