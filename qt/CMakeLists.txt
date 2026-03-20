cmake_minimum_required(VERSION 3.16)
project(DSPiConsole VERSION 1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Platform-specific Qt5 path hints
if(APPLE)
    set(Qt5_DIR "/opt/homebrew/opt/qt@5/lib/cmake/Qt5")
endif()
find_package(Qt5 5.15 REQUIRED COMPONENTS Core Gui Widgets Quick QuickControls2 Qml)

set(DSPI_CORE_DIR "${CMAKE_SOURCE_DIR}/..")

add_executable(DSPiConsole
    src/main.cpp
    src/DSPiBridge.cpp
    src/BodePlotItem.cpp
    src/MeterItem.cpp
    resources.qrc
)

target_include_directories(DSPiConsole PRIVATE
    ${DSPI_CORE_DIR}/include
    src/
)

target_link_libraries(DSPiConsole PRIVATE
    Qt5::Core Qt5::Gui Qt5::Widgets Qt5::Quick Qt5::QuickControls2 Qt5::Qml
    ${DSPI_CORE_DIR}/target/release/libdspi_core.a
)

if(APPLE)
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
    target_link_libraries(DSPiConsole PRIVATE ${LIBUSB_LIBRARIES} pthread dl)

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
