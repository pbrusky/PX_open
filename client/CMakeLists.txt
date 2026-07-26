cmake_minimum_required(VERSION 3.16)

project(px_open LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core Gui Network Quick Qml QuickControls2
    WebEngineQuick WebEngineCore Multimedia
    Concurrent            # ⭐ ADD THIS
)

qt_standard_project_setup()

link_directories(C:/ffmpeg/lib)

qt_add_resources(APP_RESOURCES resources.qrc)

qt_add_executable(px_open
    src/main.cpp

    # Backend: discovery
    src/backend/discovery/DiscoveryListener.cpp

    # Backend: stream
    src/backend/stream/FrameQueue.cpp
    src/backend/stream/FFmpegWorker.cpp
    src/backend/stream/FrameData.cpp

    # Backend: render
    src/backend/render/CameraVideoItem.cpp
    src/backend/render/CameraVideoItemTexture.cpp
   
    # UI
    src/ui/FrameItem.cpp
    src/ui/FullscreenHelper.cpp
    src/ui/AboutInfo.cpp

    ${APP_RESOURCES}
)

if (WIN32)
    target_sources(px_open PRIVATE appicon.rc)
endif()

target_include_directories(px_open PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ui
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/discovery
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/stream
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/frigate
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/render
    C:/ffmpeg/include
)

add_library(frigate_backend
    src/backend/frigate/FrigateAPI.cpp
    src/backend/frigate/FrigateCameraManager.cpp
    src/backend/frigate/FrigateStreamManager.cpp
    src/backend/frigate/FrigateTimeline.cpp
    src/backend/frigate/FrigatePlayback.cpp
    src/backend/frigate/FrigateOnvif.cpp
    src/backend/frigate/FrigateWorker.cpp
)

target_include_directories(frigate_backend PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/stream
    C:/ffmpeg/include
)

target_link_libraries(frigate_backend PRIVATE
    Qt6::Core Qt6::Gui Qt6::Network Qt6::Multimedia
)

target_link_libraries(px_open PRIVATE
    Qt6::Core Qt6::Gui Qt6::Network Qt6::Quick Qt6::Qml
    Qt6::QuickControls2 Qt6::WebEngineQuick Qt6::WebEngineCore
    Qt6::Multimedia
    Qt6::Concurrent          # ⭐ ADD THIS

    frigate_backend

    avcodec avformat avutil swscale
)
