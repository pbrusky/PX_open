cmake_minimum_required(VERSION 3.16)

project(px_open LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick Qml QuickControls2 WebEngineQuick WebEngineCore)

qt_standard_project_setup()

include_directories(
    ${CMAKE_SOURCE_DIR}/src
    ${CMAKE_SOURCE_DIR}/src/backend
    C:/ffmpeg/include
)

link_directories(C:/ffmpeg/lib)

qt_add_resources(APP_RESOURCES
    resources.qrc
)

qt_add_executable(px_open
    src/main.cpp

    # Backend
    src/backend/FrigateAPI.cpp
    src/backend/FrigateAPI.h
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

    ${APP_RESOURCES}
)

target_link_libraries(px_open
    PRIVATE
        Qt6::Quick
        Qt6::Qml
        Qt6::QuickControls2
        Qt6::WebEngineQuick
        Qt6::WebEngineCore

        avcodec
        avformat
        avutil
        swscale
)
