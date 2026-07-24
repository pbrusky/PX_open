cmake_minimum_required(VERSION 3.16)

project(px_open LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

#
# Qt modules
#
find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Network
    Quick
    Qml
    QuickControls2
    WebEngineQuick
    WebEngineCore
    Multimedia
)

qt_standard_project_setup()

#
# FFmpeg library directory
#
link_directories(C:/ffmpeg/lib)

#
# Resources
#
qt_add_resources(APP_RESOURCES resources.qrc)

# ---------------------------------------------------------
# 1. Create the executable FIRST
# ---------------------------------------------------------
qt_add_executable(px_open
    src/main.cpp

    # Backend (non-Frigate)
    src/backend/FrigateWorker.cpp
    src/backend/FrigateWorker.h
    src/backend/DiscoveryListener.cpp
    src/backend/DiscoveryListener.h

    # Video pipeline
    src/backend/FrameQueue.cpp
    src/backend/FrameQueue.h
    src/backend/FFmpegWorker.cpp
    src/backend/FFmpegWorker.h
    src/backend/CameraVideoItem.cpp
    src/backend/CameraVideoItem.h
    src/ui/FrameItem.cpp
    src/ui/FrameItem.h

    ${APP_RESOURCES}
)

# ---------------------------------------------------------
# 2. NOW attach include directories
# ---------------------------------------------------------
target_include_directories(px_open PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ui
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/frigate
    C:/ffmpeg/include
)

# ---------------------------------------------------------
# 3. Frigate backend library
# ---------------------------------------------------------
add_library(frigate_backend
    src/backend/frigate/FrigateAPI.cpp
    src/backend/frigate/FrigateAPI.h

    src/backend/frigate/FrigateCameraManager.cpp
    src/backend/frigate/FrigateCameraManager.h

    src/backend/frigate/FrigateStreamManager.cpp
    src/backend/frigate/FrigateStreamManager.h

    src/backend/frigate/FrigateTimeline.cpp
    src/backend/frigate/FrigateTimeline.h

    src/backend/frigate/FrigatePlayback.cpp
    src/backend/frigate/FrigatePlayback.h

    src/backend/frigate/FrigateOnvif.cpp
    src/backend/frigate/FrigateOnvif.h
)

# ⭐ THIS FIXES THE MISSING HEADER ERRORS
target_include_directories(frigate_backend PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ui
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/frigate
    C:/ffmpeg/include
)

target_link_libraries(frigate_backend PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Multimedia
)

# ---------------------------------------------------------
# 4. Link everything together
# ---------------------------------------------------------
target_link_libraries(px_open PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Network
    Qt6::Quick
    Qt6::Qml
    Qt6::QuickControls2
    Qt6::WebEngineQuick
    Qt6::WebEngineCore
    Qt6::Multimedia

    frigate_backend

    avcodec
    avformat
    avutil
    swscale
)
