cmake_minimum_required(VERSION 3.16)

project(px_open LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core Gui Network Quick Qml QuickControls2
    WebEngineQuick WebEngineCore Multimedia
    Concurrent
)

qt_standard_project_setup()

# ---------------------------------------------------------------------------
# FFmpeg — Windows keeps C:/ffmpeg default; Linux uses pkg-config / system
# Override either side with:
#   cmake -DFFMPEG_ROOT=C:/ffmpeg ...
#   cmake -DFFMPEG_ROOT=/usr ...
# ---------------------------------------------------------------------------
set(FFMPEG_ROOT "C:/ffmpeg" CACHE PATH "FFmpeg install prefix (Windows default C:/ffmpeg)")

set(FFMPEG_INCLUDE_DIR "")
set(FFMPEG_LIB_DIR "")
set(FFMPEG_LIBRARIES avcodec avformat avutil swscale)

if(WIN32)
    set(FFMPEG_INCLUDE_DIR "${FFMPEG_ROOT}/include")
    set(FFMPEG_LIB_DIR "${FFMPEG_ROOT}/lib")
    if(EXISTS "${FFMPEG_LIB_DIR}")
        link_directories("${FFMPEG_LIB_DIR}")
    endif()
else()
    # Linux / macOS: prefer pkg-config
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        pkg_check_modules(FFMPEG QUIET libavcodec libavformat libavutil libswscale)
    endif()

    if(FFMPEG_FOUND)
        set(FFMPEG_INCLUDE_DIR ${FFMPEG_INCLUDE_DIRS})
        set(FFMPEG_LIBRARIES ${FFMPEG_LIBRARIES})
        link_directories(${FFMPEG_LIBRARY_DIRS})
        message(STATUS "FFmpeg via pkg-config: ${FFMPEG_LIBRARIES}")
    else()
        # Fallback: FFMPEG_ROOT or common system paths
        find_path(FFMPEG_INCLUDE_DIR
            NAMES libavcodec/avcodec.h
            HINTS "${FFMPEG_ROOT}/include" /usr/include /usr/local/include
        )
        find_library(AVCODEC_LIB  NAMES avcodec  HINTS "${FFMPEG_ROOT}/lib" /usr/lib /usr/local/lib)
        find_library(AVFORMAT_LIB NAMES avformat HINTS "${FFMPEG_ROOT}/lib" /usr/lib /usr/local/lib)
        find_library(AVUTIL_LIB   NAMES avutil   HINTS "${FFMPEG_ROOT}/lib" /usr/lib /usr/local/lib)
        find_library(SWSCALE_LIB  NAMES swscale  HINTS "${FFMPEG_ROOT}/lib" /usr/lib /usr/local/lib)

        if(NOT FFMPEG_INCLUDE_DIR OR NOT AVCODEC_LIB)
            message(FATAL_ERROR
                "FFmpeg not found. Install libavcodec-dev (and related) or set -DFFMPEG_ROOT=...")
        endif()

        set(FFMPEG_LIBRARIES ${AVCODEC_LIB} ${AVFORMAT_LIB} ${AVUTIL_LIB} ${SWSCALE_LIB})
        message(STATUS "FFmpeg includes: ${FFMPEG_INCLUDE_DIR}")
        message(STATUS "FFmpeg libs: ${FFMPEG_LIBRARIES}")
    endif()
endif()

qt_add_resources(APP_RESOURCES resources.qrc)

qt_add_executable(px_open
    src/main.cpp

    # Backend: discovery
    src/backend/discovery/DiscoveryListener.cpp
    src/backend/discovery/DiscoveryProxy.cpp

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

if(WIN32)
    target_sources(px_open PRIVATE appicon.rc)
endif()

target_include_directories(px_open PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ui
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/discovery
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/stream
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/frigate
    ${CMAKE_CURRENT_SOURCE_DIR}/src/backend/render
    ${FFMPEG_INCLUDE_DIR}
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
    ${FFMPEG_INCLUDE_DIR}
)

target_link_libraries(frigate_backend PRIVATE
    Qt6::Core Qt6::Gui Qt6::Network Qt6::Multimedia
)

target_link_libraries(px_open PRIVATE
    Qt6::Core Qt6::Gui Qt6::Network Qt6::Quick Qt6::Qml
    Qt6::QuickControls2 Qt6::WebEngineQuick Qt6::WebEngineCore
    Qt6::Multimedia
    Qt6::Concurrent

    frigate_backend

    ${FFMPEG_LIBRARIES}
)