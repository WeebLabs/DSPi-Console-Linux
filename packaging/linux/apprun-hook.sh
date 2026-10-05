# Sourced by the AppImage's AppRun before DSPi Console starts, after
# linuxdeploy's Qt hook (whose gtk2 choice for GNOME isn't bundled).
# Host platform themes (KDE's, GTK's) wouldn't load against the bundled Qt;
# the desktop portal gives native file dialogs everywhere.
export QT_QPA_PLATFORMTHEME=xdgdesktopportal
