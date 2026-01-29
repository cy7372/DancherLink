cmake_minimum_required(VERSION 3.16)

set(CMAKE_AUTOUIC ON)

find_package(Qt6 COMPONENTS Core Gui Quick Network QuickControls2 Svg Multimedia Concurrent LinguistTools REQUIRED)

# Common definitions

# Architecture detection
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(ARCH_DIR "x64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64")
    set(ARCH_DIR "arm64")
else()
    set(ARCH_DIR "x86")
endif()

set(LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../libs/windows")

# Sources
set(APP_SOURCES
    backend/nvaddress.cpp
    backend/nvapp.cpp
    cli/pair.cpp
    main.cpp
    backend/computerseeker.cpp
    backend/identitymanager.cpp
    backend/nvcomputer.cpp
    backend/nvhttp.cpp
    backend/nvpairingmanager.cpp
    backend/computermanager.cpp
    backend/boxartmanager.cpp
    backend/richpresencemanager.cpp
    cli/commandlineparser.cpp
    cli/listapps.cpp
    cli/quitstream.cpp
    cli/startstream.cpp
    settings/compatfetcher.cpp
    settings/mappingfetcher.cpp
    settings/streamingpreferences.cpp
    streaming/input/abstouch.cpp
    streaming/input/gamepad.cpp
    streaming/input/input.cpp
    streaming/input/keyboard.cpp
    streaming/input/mouse.cpp
    streaming/input/reltouch.cpp
    streaming/session.cpp
    streaming/micstream.cpp
    streaming/audio/audio.cpp
    streaming/audio/renderers/sdlaud.cpp
    gui/computermodel.cpp
    gui/appmodel.cpp
    streaming/bandwidth.cpp
    streaming/streamutils.cpp
    backend/autoupdatechecker.cpp
    path.cpp
    settings/mappingmanager.cpp
    gui/sdlgamepadkeynavigation.cpp
    streaming/video/overlaymanager.cpp
    backend/systemproperties.cpp
    wm.cpp
    
    # Resources
    resources.qrc
    qml.qrc
    
    # Windows Resources
    DancherLink_resource.rc
    DancherLink.exe.manifest
)

# Translations
file(GLOB TS_FILES "languages/*.ts")
qt6_add_lrelease(DancherLink TS_FILES ${TS_FILES})

# Version
file(STRINGS "version.txt" VERSION_STR)
add_compile_definitions(VERSION_STR="${VERSION_STR}")

# Executable
qt6_add_executable(DancherLink WIN32 ${APP_SOURCES})

# Include directories
target_include_directories(DancherLink PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../moonlight-common-c/moonlight-common-c/src
    ${CMAKE_CURRENT_SOURCE_DIR}/../qmdnsengine/qmdnsengine/src/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../qmdnsengine
    ${CMAKE_CURRENT_SOURCE_DIR}/../h264bitstream/h264bitstream
)

if(WIN32)
    target_include_directories(DancherLink PRIVATE ${LIBS_DIR}/include)
    if(EXISTS "${LIBS_DIR}/include/${ARCH_DIR}")
        target_include_directories(DancherLink PRIVATE "${LIBS_DIR}/include/${ARCH_DIR}")
    endif()
endif()

# FFmpeg and Platform specific sources
if(WIN32)
    target_sources(DancherLink PRIVATE
        streaming/video/ffmpeg.cpp
        streaming/video/ffmpeg-renderers/genhwaccel.cpp
        streaming/video/ffmpeg-renderers/sdlvid.cpp
        streaming/video/ffmpeg-renderers/swframemapper.cpp
        streaming/video/ffmpeg-renderers/pacer/pacer.cpp
        
        # DXVA2/D3D11VA
        streaming/video/ffmpeg-renderers/dxva2.cpp
        streaming/video/ffmpeg-renderers/d3d11va.cpp
        streaming/video/ffmpeg-renderers/pacer/dxvsyncsource.cpp
        
        # LibPlacebo
        streaming/video/ffmpeg-renderers/plvk.cpp
        streaming/video/ffmpeg-renderers/plvk_c.c
    )
    target_compile_definitions(DancherLink PRIVATE HAVE_FFMPEG HAVE_LIBPLACEBO_VULKAN)
endif()

# Linking
target_link_libraries(DancherLink PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick Qt6::Network Qt6::QuickControls2 Qt6::Svg Qt6::Multimedia Qt6::Concurrent
    h264bitstream
    qmdnsengine
    moonlight-common-c
)

# Manually add link directories since CMake isn't propagating them perfectly for imported/custom targets
if(WIN32)
    target_link_directories(DancherLink PRIVATE "${CMAKE_BINARY_DIR}/lib")
endif()

if(WIN32)
    target_link_libraries(DancherLink PRIVATE AntiHooking)
    
    # Windows System Libs
    target_link_libraries(DancherLink PRIVATE
        ws2_32 winmm dxva2 ole32 gdi32 user32 d3d9 dwmapi dbghelp comctl32 Imm32 wtsapi32
    )
    
    # 3rd Party Libs
    target_link_directories(DancherLink PRIVATE "${LIBS_DIR}/lib/${ARCH_DIR}")
    
    target_link_libraries(DancherLink PRIVATE
        libssl libcrypto SDL2 SDL2_ttf avcodec avutil swscale opus dxgi d3d11 libplacebo
    )
endif()

# Definitions
target_compile_definitions(DancherLink PRIVATE 
    QT_DEPRECATED_WARNINGS
    QT_DISABLE_DEPRECATED_BEFORE=0x060000
)

if(WIN32)
    target_compile_definitions(DancherLink PRIVATE _USE_MATH_DEFINES)
endif()
