include_guard(GLOBAL)

include(CMakeParseArguments)

macro(enable_project_coverage)
    if(COVERAGE)
        if(APPLE AND CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang")
            include(LLVMCodeCoverage)
            append_llvm_coverage_compiler_flags()
        elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
            include(GCCCodeCoverage)
            append_gcc_coverage_compiler_flags()
        else()
            message(FATAL_ERROR
                "Coverage is supported only with GCC or macOS AppleClang/Clang.")
        endif()
    endif()
endmacro()

function(setup_project_coverage)
    if(NOT COVERAGE)
        return()
    endif()

    set(options)
    set(oneValueArgs TARGET TEST_TARGET EXCLUDE_REGEX)
    set(multiValueArgs SOURCES COVERAGE_TARGETS MODULE_REPORTS)
    cmake_parse_arguments(COVERAGE_SETUP
        "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT COVERAGE_SETUP_TARGET)
        message(FATAL_ERROR "setup_project_coverage requires TARGET.")
    endif()
    if(NOT COVERAGE_SETUP_TEST_TARGET)
        message(FATAL_ERROR "setup_project_coverage requires TEST_TARGET.")
    endif()
    if(NOT TARGET ${COVERAGE_SETUP_TARGET})
        message(FATAL_ERROR "Coverage target '${COVERAGE_SETUP_TARGET}' does not exist.")
    endif()
    if(NOT TARGET ${COVERAGE_SETUP_TEST_TARGET})
        message(FATAL_ERROR "Test aggregate target '${COVERAGE_SETUP_TEST_TARGET}' does not exist.")
    endif()

    set(_coverage_sources ${COVERAGE_SETUP_SOURCES})
    set(_module_names ${COVERAGE_SETUP_MODULE_REPORTS})
    set(_module_project_root "${PROJECT_SOURCE_DIR}")

    foreach(_module_name IN LISTS _module_names)
        if(NOT EXISTS "${PROJECT_SOURCE_DIR}/include/${_module_name}"
           AND NOT EXISTS "${PROJECT_SOURCE_DIR}/src/${_module_name}")
            message(FATAL_ERROR
                "Coverage module '${_module_name}' has neither include/${_module_name} nor src/${_module_name}.")
        endif()
    endforeach()
    if(APPLE AND CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang")
        set(_coverage_objects ${COVERAGE_SETUP_COVERAGE_TARGETS})

        if(NOT _coverage_objects)
            get_property(_test_dependencies
                TARGET ${COVERAGE_SETUP_TEST_TARGET}
                PROPERTY MANUALLY_ADDED_DEPENDENCIES)

            foreach(_test_target IN LISTS _test_dependencies)
                if(TARGET ${_test_target})
                    get_target_property(_test_target_type ${_test_target} TYPE)
                    if(_test_target_type STREQUAL "EXECUTABLE")
                        list(APPEND _coverage_objects ${_test_target})
                    endif()
                endif()
            endforeach()
        endif()

        set(_llvm_args
            NAME coverage
            TARGET ${COVERAGE_SETUP_TARGET}
            OBJECTS ${_coverage_objects}
            DEPENDENCIES ${COVERAGE_SETUP_TEST_TARGET}
            SOURCES ${_coverage_sources}
            MODULE_NAMES ${_module_names}
            MODULE_PROJECT_ROOT "${_module_project_root}"
        )
        if(COVERAGE_SETUP_EXCLUDE_REGEX)
            list(APPEND _llvm_args EXCLUDE_REGEX "${COVERAGE_SETUP_EXCLUDE_REGEX}")
        endif()

        setup_target_for_coverage_llvm(${_llvm_args})
    else()
        setup_target_for_coverage_gcc(
            NAME coverage
            DEPENDENCIES ${COVERAGE_SETUP_TEST_TARGET}
            SOURCES ${_coverage_sources}
            MODULE_NAMES ${_module_names}
            MODULE_PROJECT_ROOT "${_module_project_root}"
            EXCLUDE_REGEX "${COVERAGE_SETUP_EXCLUDE_REGEX}"
        )
    endif()
endfunction()

# Configure standalone tests and, independently, the optional Benchmarking
# support declared by the root repository. Testing and Benchmarking are never
# dependencies of production targets.
macro(setup_standalone_project)
    if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        set(options EXCLUDE_FROM_ALL)
        set(oneValueArgs TARGET TEST_DIRECTORY TEST_TARGET EXCLUDE_REGEX)
        set(multiValueArgs SOURCES TEST_BUILD_DEPENDENCIES COVERAGE_TARGETS MODULE_REPORTS)
        cmake_parse_arguments(STANDALONE
            "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

        # The Benchmarking repository owns the 'benchmarks' aggregate target
        # and registers the root project's benchmarks/ when that directory exists.
        # A project without Benchmarking still configures its tests normally.
        ariadne_setup_benchmarking()

        if(STANDALONE_TEST_DIRECTORY)
            if(NOT STANDALONE_TARGET)
                message(FATAL_ERROR "setup_standalone_project requires TARGET when tests are requested.")
            endif()
            if(NOT STANDALONE_TEST_TARGET)
                message(FATAL_ERROR "setup_standalone_project requires TEST_TARGET when tests are requested.")
            endif()

            enable_testing()
            ariadne_setup_testing()

            if(STANDALONE_EXCLUDE_FROM_ALL)
                add_subdirectory("${STANDALONE_TEST_DIRECTORY}" EXCLUDE_FROM_ALL)
            else()
                add_subdirectory("${STANDALONE_TEST_DIRECTORY}")
            endif()

            if(NOT TARGET ${STANDALONE_TEST_TARGET})
                message(FATAL_ERROR
                    "Test directory '${STANDALONE_TEST_DIRECTORY}' did not create target '${STANDALONE_TEST_TARGET}'.")
            endif()

            if(STANDALONE_TEST_BUILD_DEPENDENCIES)
                add_dependencies(${STANDALONE_TEST_TARGET} ${STANDALONE_TEST_BUILD_DEPENDENCIES})
            endif()

            setup_project_coverage(
                TARGET ${STANDALONE_TARGET}
                TEST_TARGET ${STANDALONE_TEST_TARGET}
                SOURCES ${STANDALONE_SOURCES}
                COVERAGE_TARGETS ${STANDALONE_COVERAGE_TARGETS}
                MODULE_REPORTS ${STANDALONE_MODULE_REPORTS}
                EXCLUDE_REGEX "${STANDALONE_EXCLUDE_REGEX}"
            )
        elseif(STANDALONE_TARGET OR STANDALONE_TEST_TARGET
               OR STANDALONE_TEST_BUILD_DEPENDENCIES OR STANDALONE_COVERAGE_TARGETS)
            message(FATAL_ERROR
                "setup_standalone_project requires TEST_DIRECTORY for test configuration.")
        endif()
    endif()
endmacro()

macro(setup_project_tests)
    if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        set(options)
        set(oneValueArgs EXCLUDE_REGEX)
        cmake_parse_arguments(PROJECT_TESTS
            "${options}" "${oneValueArgs}" "" ${ARGN})

        get_property(_project_library_target GLOBAL PROPERTY ARIADNE_PROJECT_LIBRARY_TARGET)
        if(NOT _project_library_target)
            message(FATAL_ERROR
                "setup_project_tests requires setup_project_library to be called first.")
        endif()

        enable_testing()
        add_subdirectory(test)

        if(NOT TARGET tests)
            message(FATAL_ERROR "Test directory 'test' did not create target 'tests'.")
        endif()

        ariadne_setup_benchmarking()

        setup_project_coverage(
            TARGET ${_project_library_target}
            TEST_TARGET tests
            SOURCES
                "${PROJECT_SOURCE_DIR}/include"
                "${PROJECT_SOURCE_DIR}/src"
            EXCLUDE_REGEX "${PROJECT_TESTS_EXCLUDE_REGEX}"
        )
    endif()
endmacro()
