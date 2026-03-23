# DancherLink Unit Tests

# Include directories for testing
include_directories(${CMAKE_SOURCE_DIR}/app)

# Test utilities (if needed in future)
# add_library(test_utils STATIC utils/test_utils.cpp)

# =============================================================================
# ComputerManager Tests
# =============================================================================
add_executable(computermanager_tests
    computermanager/test_computermanager.cpp
)

target_link_libraries(computermanager_tests
    GTest::gtest_main
    Qt6::Network
)

include(GoogleTest)
gtest_discover_tests(computermanager_tests DISCOVERY_MODE PRE_TEST)

# =============================================================================
# StreamUtils Tests
# =============================================================================
add_executable(streamutils_tests
    streaming/test_streamutils.cpp
)

target_link_libraries(streamutils_tests
    GTest::gtest_main
)

gtest_discover_tests(streamutils_tests DISCOVERY_MODE PRE_TEST)

# =============================================================================
# Add more test modules here as needed
# =============================================================================
