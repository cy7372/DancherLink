cmake_minimum_required(VERSION 3.16)

project(DancherLink LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 COMPONENTS Core Gui Quick Network QuickControls2 Svg Multimedia Concurrent REQUIRED)

# Common definitions
if(MSVC)
    add_compile_options(/W3 /wd4005 /wd4996 /wd4267)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
else()
    add_compile_options(-Wall -Wextra)
endif()

# Configuration
option(DISABLE_PREBUILTS "Disable usage of prebuilt libraries" OFF)

# Architecture detection
if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64" OR CMAKE_GENERATOR_PLATFORM MATCHES "ARM64")
    set(ARCH_DIR "arm64")
elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(ARCH_DIR "x64")
else()
    set(ARCH_DIR "x86")
endif()

if(WIN32)
    set(OPENSSL_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libs/windows")
    
    if(ARCH_DIR STREQUAL "arm64")
        set(OPENSSL_INCLUDE_DIR "${OPENSSL_ROOT_DIR}/include/arm64" CACHE PATH "OpenSSL Include Directory" FORCE)
    else()
        set(OPENSSL_INCLUDE_DIR "${OPENSSL_ROOT_DIR}/include" CACHE PATH "OpenSSL Include Directory" FORCE)
    endif()

    if(EXISTS "${OPENSSL_ROOT_DIR}/lib/${ARCH_DIR}/libcrypto.lib")
        set(OPENSSL_CRYPTO_LIBRARY "${OPENSSL_ROOT_DIR}/lib/${ARCH_DIR}/libcrypto.lib" CACHE FILEPATH "OpenSSL Crypto Library" FORCE)
        set(OPENSSL_SSL_LIBRARY "${OPENSSL_ROOT_DIR}/lib/${ARCH_DIR}/libssl.lib" CACHE FILEPATH "OpenSSL SSL Library" FORCE)
        set(MOONLIGHT_OPENSSL_INCLUDE_DIR "${OPENSSL_INCLUDE_DIR}" CACHE PATH "Moonlight OpenSSL Include" FORCE)
    endif()
endif()

# Set output directories for all targets
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Ensure subdirectories inherit these output paths
link_directories(${CMAKE_LIBRARY_OUTPUT_DIRECTORY})
link_directories(${CMAKE_ARCHIVE_OUTPUT_DIRECTORY})

if(WIN32)
    # Ensure MSVC implibs are placed correctly
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_DEBUG ${CMAKE_BINARY_DIR}/lib)
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE ${CMAKE_BINARY_DIR}/lib)
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_DEBUG ${CMAKE_BINARY_DIR}/bin)
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_RELEASE ${CMAKE_BINARY_DIR}/bin)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_BINARY_DIR}/bin)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_BINARY_DIR}/bin)
endif()

# Add subdirectories
add_subdirectory(h264bitstream)

# These submodules have their own CMakeLists.txt
# We map the target names to match what DancherLink expects if they differ
add_subdirectory(moonlight-common-c/moonlight-common-c)
add_subdirectory(qmdnsengine/qmdnsengine)

if(WIN32)
    add_subdirectory(AntiHooking)
endif()

add_subdirectory(app)
