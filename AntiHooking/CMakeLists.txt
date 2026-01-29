cmake_minimum_required(VERSION 3.16)

if(WIN32)
    add_library(AntiHooking STATIC
        antihookingprotection.cpp
        antihookingprotection.h
    )

    # Architecture detection for library paths
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(ARCH_DIR "x64")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64")
        set(ARCH_DIR "arm64")
    else()
        set(ARCH_DIR "x86")
    endif()

    set(LIBS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../libs/windows")
    
    target_include_directories(AntiHooking PUBLIC 
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${LIBS_DIR}/include
    )

    find_library(DETOURS_LIB detours PATHS "${LIBS_DIR}/lib/${ARCH_DIR}" NO_DEFAULT_PATH)
    
    if(DETOURS_LIB)
        target_link_libraries(AntiHooking PRIVATE ${DETOURS_LIB})
    else()
        message(WARNING "Detours library not found in ${LIBS_DIR}/lib/${ARCH_DIR}")
    endif()
    
    target_compile_definitions(AntiHooking PUBLIC ANTIHOOKING_LIBRARY)
endif()
