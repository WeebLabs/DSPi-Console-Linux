cmake_minimum_required(VERSION 3.16)
project(DSPiConsole VERSION 1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(Qt5_DIR "/opt/homebrew/opt/qt@5/lib/cmake/Qt5")
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

# libusb (required by rusb in the Rust core library)
find_library(LIBUSB usb-1.0 HINTS /opt/homebrew/opt/libusb/lib)
target_include_directories(DSPiConsole PRIVATE /opt/homebrew/opt/libusb/include)
target_link_libraries(DSPiConsole PRIVATE ${LIBUSB})

# macOS frameworks required by rusb/libusb
if(APPLE)
    find_library(IOKIT IOKit)
    find_library(CF CoreFoundation)
    find_library(SEC Security)
    find_library(OBJC objc)
    target_link_libraries(DSPiConsole PRIVATE ${IOKIT} ${CF} ${SEC} ${OBJC}
        "-framework SystemConfiguration")
endif()
