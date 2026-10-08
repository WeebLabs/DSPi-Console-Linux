cmake_minimum_required(VERSION 3.16)
project(DSPiConsole VERSION 1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Platform-specific Qt5 path hints
if(APPLE)
    set(Qt5_DIR "/opt/homebrew/opt/qt@5/lib/cmake/Qt5")
endif()
find_package(Qt5 5.15 REQUIRED COMPONENTS Core Gui Widgets Quick QuickControls2 Qml Network)

set(DSPI_CORE_DIR "${CMAKE_SOURCE_DIR}/..")

add_executable(DSPiConsole
    src/main.cpp
    src/DSPiBridge.cpp
    src/BodePlotItem.cpp
    src/PeqEditorItem.cpp
    src/RtaController.cpp
    src/RtaViews.cpp
    src/PointerTracker.cpp
    src/SiggenController.cpp
    src/CsController.cpp
    src/FirmwareUpdater.cpp
    src/AutoEqLibrary.cpp
    src/StatsController.cpp
    src/MonitorModel.cpp
    src/ConfigFiles.cpp
    src/MeterItem.cpp
    src/WindowEffects.cpp
    resources.qrc
)

target_include_directories(DSPiConsole PRIVATE
    ${DSPI_CORE_DIR}/include
    src/
)

target_link_libraries(DSPiConsole PRIVATE
    Qt5::Core Qt5::Gui Qt5::Widgets Qt5::Quick Qt5::QuickControls2 Qt5::Qml Qt5::Network
    ${DSPI_CORE_DIR}/target/release/libdspi_core.a
)

if(APPLE)
    # The native Console's system colours, read from AppKit
    enable_language(OBJCXX)
    target_sources(DSPiConsole PRIVATE src/MacSystemColors.mm)
    target_link_libraries(DSPiConsole PRIVATE "-framework AppKit")

    # libusb from Homebrew
    find_library(LIBUSB usb-1.0 HINTS /opt/homebrew/opt/libusb/lib)
    target_include_directories(DSPiConsole PRIVATE /opt/homebrew/opt/libusb/include)
    target_link_libraries(DSPiConsole PRIVATE ${LIBUSB})

    # macOS frameworks required by rusb/libusb
    find_library(IOKIT IOKit)
    find_library(CF CoreFoundation)
    find_library(SEC Security)
    find_library(OBJC objc)
    target_link_libraries(DSPiConsole PRIVATE ${IOKIT} ${CF} ${SEC} ${OBJC}
        "-framework SystemConfiguration")
elseif(UNIX)
    # Linux: libusb via pkg-config, plus pthreads and dl
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(LIBUSB REQUIRED libusb-1.0)
    target_include_directories(DSPiConsole PRIVATE ${LIBUSB_INCLUDE_DIRS})
    target_link_libraries(DSPiConsole PRIVATE ${LIBUSB_LIBRARIES} pthread dl udev)

    # Optional: KDE blur-behind support
    find_package(KF5WindowSystem QUIET)
    if(KF5WindowSystem_FOUND)
        target_link_libraries(DSPiConsole PRIVATE KF5::WindowSystem)
        target_compile_definitions(DSPiConsole PRIVATE HAS_KDE_BLUR)
        message(STATUS "KDE blur-behind support enabled")
    else()
        message(STATUS "KDE Frameworks not found — blur-behind disabled")
    endif()
endif()

# ── Install and packages (Linux) ──
# `cmake --install` lays out a system install; `cpack -G DEB` / `cpack -G RPM`
# build the packages (packaging/linux/build-release.sh runs them).
if(UNIX AND NOT APPLE)
    # The version the app reports, e.g. 1.1.6-beta4
    file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/src/main.cpp _ver REGEX "setApplicationVersion\\(\"[^\"]+\"\\)")
    string(REGEX REPLACE ".*setApplicationVersion\\(\"([^\"]+)\"\\).*" "\\1" DSPI_VERSION "${_ver}")
    # Packages sort a pre-release before its release with ~: 1.1.6~beta4 < 1.1.6
    string(REPLACE "-" "~" DSPI_PKG_VERSION "${DSPI_VERSION}")

    set(PKG ${CMAKE_SOURCE_DIR}/../packaging/linux)
    install(PROGRAMS $<TARGET_FILE:DSPiConsole> DESTINATION bin RENAME dspi-console)
    install(FILES ${PKG}/dspi-console.desktop DESTINATION share/applications)
    install(FILES ${CMAKE_SOURCE_DIR}/dspi-console.svg DESTINATION share/icons/hicolor/scalable/apps)
    install(FILES ${PKG}/io.github.weeblabs.DSPiConsole.metainfo.xml DESTINATION share/metainfo)
    install(FILES ${PKG}/70-dspi.rules DESTINATION lib/udev/rules.d)

    set(CPACK_PACKAGE_NAME dspi-console)
    set(CPACK_PACKAGE_VERSION ${DSPI_PKG_VERSION})
    set(CPACK_PACKAGE_VENDOR "WeebLabs")
    set(CPACK_PACKAGE_CONTACT "WeebLabs <https://github.com/WeebLabs/DSPi-Console-Linux>")
    set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Control application for the DSPi audio processor")
    set(CPACK_PACKAGE_DESCRIPTION "DSPi Console configures and tunes a DSPi, open source DSP firmware for the Raspberry Pi Pico: parametric EQ, crossovers, routing, delay, effects, limiters, control surfaces and firmware updates, applied live over USB.")
    set(CPACK_PACKAGE_HOMEPAGE_URL "https://github.com/WeebLabs/DSPi-Console-Linux")
    set(CPACK_PACKAGING_INSTALL_PREFIX /usr)
    set(CPACK_STRIP_FILES ON)

    # Debian / Ubuntu: library dependencies from dpkg-shlibdeps, plus the QML
    # modules and plugins the binary loads at run time
    set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
    set(CPACK_DEBIAN_PACKAGE_SECTION sound)
    set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
    set(CPACK_DEBIAN_PACKAGE_DEPENDS "qml-module-qtquick2, qml-module-qtquick-window2, qml-module-qtquick-layouts, qml-module-qtquick-controls2, qml-module-qtquick-templates2, qml-module-qtqml, qml-module-qt-labs-settings, qml-module-qt-labs-platform, libqt5svg5 | libqt5svg5t64, qtwayland5")
    set(CPACK_DEBIAN_PACKAGE_RECOMMENDS "kwayland-integration, xdg-desktop-portal, udisks2")
    set(CPACK_DEBIAN_PACKAGE_CONTROL_EXTRA "${PKG}/postinst;${PKG}/postrm")

    # Fedora: library dependencies are found automatically
    set(CPACK_RPM_FILE_NAME RPM-DEFAULT)
    set(CPACK_RPM_PACKAGE_RELEASE 1)
    set(CPACK_RPM_PACKAGE_LICENSE "Unspecified")
    set(CPACK_RPM_PACKAGE_GROUP "Applications/Multimedia")
    set(CPACK_RPM_PACKAGE_URL "https://github.com/WeebLabs/DSPi-Console-Linux")
    set(CPACK_RPM_PACKAGE_REQUIRES "qt5-qtdeclarative, qt5-qtquickcontrols2, qt5-qtsvg, qt5-qtwayland")
    set(CPACK_RPM_PACKAGE_SUGGESTS "kwayland-integration, xdg-desktop-portal, udisks2")
    set(CPACK_RPM_POST_INSTALL_SCRIPT_FILE ${PKG}/postinst)
    set(CPACK_RPM_POST_UNINSTALL_SCRIPT_FILE ${PKG}/postrm)
    # Don't claim ownership of system directories
    set(CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION
        /usr/share/applications /usr/share/icons /usr/share/icons/hicolor /usr/share/icons/hicolor/scalable
        /usr/share/icons/hicolor/scalable/apps /usr/share/metainfo /usr/lib/udev /usr/lib/udev/rules.d)

    include(CPack)
endif()
