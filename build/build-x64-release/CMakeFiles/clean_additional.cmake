# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "Release")
  file(REMOVE_RECURSE
  "AntiHooking\\AntiHooking_autogen"
  "AntiHooking\\CMakeFiles\\AntiHooking_autogen.dir\\AutogenUsed.txt"
  "AntiHooking\\CMakeFiles\\AntiHooking_autogen.dir\\ParseCache.txt"
  "app\\CMakeFiles\\DancherLink_autogen.dir\\AutogenUsed.txt"
  "app\\CMakeFiles\\DancherLink_autogen.dir\\ParseCache.txt"
  "app\\DancherLink_autogen"
  "h264bitstream\\CMakeFiles\\h264bitstream_autogen.dir\\AutogenUsed.txt"
  "h264bitstream\\CMakeFiles\\h264bitstream_autogen.dir\\ParseCache.txt"
  "h264bitstream\\h264bitstream_autogen"
  "moonlight-common-c\\moonlight-common-c\\CMakeFiles\\moonlight-common-c_autogen.dir\\AutogenUsed.txt"
  "moonlight-common-c\\moonlight-common-c\\CMakeFiles\\moonlight-common-c_autogen.dir\\ParseCache.txt"
  "moonlight-common-c\\moonlight-common-c\\enet\\CMakeFiles\\enet_autogen.dir\\AutogenUsed.txt"
  "moonlight-common-c\\moonlight-common-c\\enet\\CMakeFiles\\enet_autogen.dir\\ParseCache.txt"
  "moonlight-common-c\\moonlight-common-c\\enet\\enet_autogen"
  "moonlight-common-c\\moonlight-common-c\\moonlight-common-c_autogen"
  "qmdnsengine\\qmdnsengine\\src\\CMakeFiles\\qmdnsengine_autogen.dir\\AutogenUsed.txt"
  "qmdnsengine\\qmdnsengine\\src\\CMakeFiles\\qmdnsengine_autogen.dir\\ParseCache.txt"
  "qmdnsengine\\qmdnsengine\\src\\qmdnsengine_autogen"
  )
endif()
