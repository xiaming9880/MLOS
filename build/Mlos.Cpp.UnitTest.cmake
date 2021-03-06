# Mlos.Cpp.UnitTest.cmake
#
# A set of cmake rules for C++ unit tests.

# Fetch and build Google Test library dependency.

include(FetchContent)
#set(FETCHCONTENT_QUIET OFF)
FetchContent_Declare(
    googletest
    GIT_REPOSITORY  https://github.com/google/googletest.git
    GIT_TAG         release-1.10.0
    GIT_SHALLOW     ON
)

FetchContent_GetProperties(googletest)
if(NOT googletest_POPULATED)
    FetchContent_Populate(googletest)
    add_subdirectory(${googletest_SOURCE_DIR} ${googletest_BINARY_DIR} EXCLUDE_FROM_ALL)
endif()


# Add some test fixtures to use for setup/tear down of other Mlos unit tests.

# Note: Fixtures only run once per ctest invokation.
# That's fine for the pre-check, but the cleanup step, so we moved that into
# the test command itself for now.

# These "tests" are really just to help define fixtures to be depended on by
# other tests for setup/tear down checks.
add_test(NAME CheckForMlosSharedMemories
    COMMAND ${MLOS_ROOT}/build/CMakeHelpers/CheckForMlosSharedMemories.sh)
#add_test(NAME RemoveMlosSharedMemories
#    COMMAND ${MLOS_ROOT}/build/CMakeHelpers/RemoveMlosSharedMemories.sh)
# These properties add the pre/post actions for the "MlosSharedMemoriesChecks" fixture.
set_tests_properties(CheckForMlosSharedMemories PROPERTIES
    FIXTURES_SETUP MlosSharedMemoriesChecks)
#set_tests_properties(RemoveMlosSharedMemories PROPERTIES
#    FIXTURES_CLEANUP MlosSharedMemoriesChecks)
# Now other test can add "MlosSharedMemoriesChecks" to their
# "FIXTURES_REQUIRED" property to invoke these scripts before/after themselves.

# Mark all setup/tear down activities involving the shared memory regions as
# mutually exclusive (no parallel runs).
set_tests_properties(
    CheckForMlosSharedMemories
    #RemoveMlosSharedMemories
    PROPERTIES RESOURCE_LOCK MlosSharedMemories)

# add_mlos_agent_server_exe_test_run()
#
# Provide a function for handling some of the boilerplate to setup a test run
# of an executable using the Mlos.Agent.Server
#
#   add_mlos_agent_server_exe_test_run(
#       NAME MlosTestRun_Mlos.Agent.Server_${PROJECT_NAME}
#       EXECUTABLE_TARGET ${PROJECT_NAME}
#       TIMEOUT 240
#       MLOS_SETTINGS_REGISTRY_TARGETS Mlos.UnitTest.SettingsRegistry)
#
function(add_mlos_agent_server_exe_test_run)
    set(oneValueArgs NAME EXECUTABLE_TARGET TIMEOUT)
    set(multiValueArgs MLOS_SETTINGS_REGISTRY_TARGETS)
    cmake_parse_arguments(add_mlos_agent_server_exe_test_run "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    set(TEST_NAME ${add_mlos_agent_server_exe_test_run_NAME})
    set(TEST_EXECUTABLE_TARGET ${add_mlos_agent_server_exe_test_run_EXECUTABLE_TARGET})

    if(NOT DEFINED add_mlos_agent_server_exe_test_run_TIMEOUT)
        set(TEST_TIMEOUT ${DEFAULT_CTEST_TIMEOUT})
    else()
        set(TEST_TIMEOUT ${add_mlos_agent_server_exe_test_run_TIMEOUT})
    endif()

    if(NOT DEFINED add_mlos_agent_server_exe_test_run_MLOS_SETTINGS_REGISTRY_TARGETS)
        message(SEND_ERROR
            "Missing MLOS_SETTINGS_REGISTRY_TARGETS for ${TEST_NAME}")
    endif()

    foreach(SETTINGS_REGISTRY_TGT in ${add_mlos_agent_server_exe_test_run_MLOS_SETTINGS_REGISTRY_TARGETS})
        if(NOT DEFINED MLOS_SETTINGS_REGISTRY)
            set(MLOS_SETTINGS_REGISTRY_PATH $<TARGET_PROPERTY:${SETTINGS_REGISTRY_TGT},DOTNET_OUTPUT_DIR>)
        else()
            set(MLOS_SETTINGS_REGISTRY_PATH ${MLOS_SETTINGS_REGISTRY_PATH}:$<TARGET_PROPERTY:${SETTINGS_REGISTRY_TGT},DOTNET_OUTPUT_DIR>)
        endif()
    endforeach()

    # Basically we want to run:
    # $ dotnet Mlos.Agent.Server.dll --executable /some/test/exe
    # However, we need to
    # - Make sure there aren't other things using the shared mem regions in
    #   /dev/shm/ that we're about to create (e.g. from a previous failed test
    #   or something else that's running).
    #   (and also clean them up after we're done)
    # - Make sure that the Agent can find the SettingsRegistry DLLs that the
    #   /some/test/exe needs to use.
    add_test(NAME ${TEST_NAME}
        COMMAND ${MLOS_ROOT}/build/CMakeHelpers/RunTestsAndSharedMemChecks.sh ${DOTNET} $<TARGET_PROPERTY:Mlos.Agent.Server,DOTNET_OUTPUT_DLL> --executable $<TARGET_FILE:${TEST_EXECUTABLE_TARGET}>)
    set_tests_properties(${TEST_NAME} PROPERTIES
        TIMEOUT ${TEST_TIMEOUT}
        # Let the Mlos.Agent.Server know where to find the registry assembly.
        ENVIRONMENT MLOS_SETTINGS_REGISTRY_PATH=${MLOS_SETTINGS_REGISTRY_PATH}
        # Make sure to check for existing shared registry memories before hand.
        FIXTURES_REQUIRED MlosSharedMemoriesChecks
        # This test conflicts with any other test using the MlosSharedMemories
        # (no parallel test runs).
        RESOURCE_LOCK MlosSharedMemories)
    # Include these targets in cmake's "check" target so we can build/test in one shot.
    add_dependencies(check ${TEST_EXECUTABLE_TARGET} Mlos.Agent.Server)
endfunction()
