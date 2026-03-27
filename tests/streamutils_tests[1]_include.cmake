if(EXISTS "C:/Users/CyYu/Programs/DancherLink-qt/bin/streamutils_tests.exe")
  if(NOT EXISTS "C:/Users/CyYu/Programs/DancherLink-qt/tests/streamutils_tests[1]_tests.cmake" OR
     NOT "C:/Users/CyYu/Programs/DancherLink-qt/tests/streamutils_tests[1]_tests.cmake" IS_NEWER_THAN "C:/Users/CyYu/Programs/DancherLink-qt/bin/streamutils_tests.exe" OR
     NOT "C:/Users/CyYu/Programs/DancherLink-qt/tests/streamutils_tests[1]_tests.cmake" IS_NEWER_THAN "${CMAKE_CURRENT_LIST_FILE}")
    include("C:/Program Files/CMake/share/cmake-4.2/Modules/GoogleTestAddTests.cmake")
    gtest_discover_tests_impl(
      TEST_EXECUTABLE [==[C:/Users/CyYu/Programs/DancherLink-qt/bin/streamutils_tests.exe]==]
      TEST_EXECUTOR [==[]==]
      TEST_WORKING_DIR [==[C:/Users/CyYu/Programs/DancherLink-qt/tests]==]
      TEST_EXTRA_ARGS [==[]==]
      TEST_PROPERTIES [==[]==]
      TEST_PREFIX [==[]==]
      TEST_SUFFIX [==[]==]
      TEST_FILTER [==[]==]
      NO_PRETTY_TYPES [==[FALSE]==]
      NO_PRETTY_VALUES [==[FALSE]==]
      TEST_LIST [==[streamutils_tests_TESTS]==]
      CTEST_FILE [==[C:/Users/CyYu/Programs/DancherLink-qt/tests/streamutils_tests[1]_tests.cmake]==]
      TEST_DISCOVERY_TIMEOUT [==[5]==]
      TEST_DISCOVERY_EXTRA_ARGS [==[]==]
      TEST_XML_OUTPUT_DIR [==[]==]
    )
  endif()
  include("C:/Users/CyYu/Programs/DancherLink-qt/tests/streamutils_tests[1]_tests.cmake")
else()
  add_test(streamutils_tests_NOT_BUILT streamutils_tests_NOT_BUILT)
endif()
