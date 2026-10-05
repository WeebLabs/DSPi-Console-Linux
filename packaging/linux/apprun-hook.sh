# Sourced by the AppImage's AppRun before DSPi Console starts.
# Host platform themes (KDE's, GTK's) aren't bundled and wouldn't load against
# the bundled Qt; the desktop portal gives native file dialogs everywhere.
case "${QT_QPA_PLATFORMTHEME:-}" in
    ""|kde|gtk*|qt5ct|qt6ct) export QT_QPA_PLATFORMTHEME=xdgdesktopportal ;;
esac
