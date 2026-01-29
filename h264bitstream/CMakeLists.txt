cmake_minimum_required(VERSION 3.16)

add_library(h264bitstream STATIC
    h264bitstream/h264_nal.c
    h264bitstream/h264_sei.c
    h264bitstream/h264_stream.c
)

target_include_directories(h264bitstream PUBLIC 
    ${CMAKE_CURRENT_SOURCE_DIR}/h264bitstream
)

if(MSVC)
    target_compile_options(h264bitstream PRIVATE /wd4244 /wd4267)
else()
    target_compile_options(h264bitstream PRIVATE -std=gnu99)
endif()
