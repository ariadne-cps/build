# TEMPORARY minimizechecks regression. Remove after the rollout.
cmake_minimum_required(VERSION 3.15)
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/DependencyChecks.cmake")

# Synthetic fixture: Numeric certifies Testing from Logging before Logging
# is configured. The intentionally inconsistent unvisited Utility path must
# not be inspected once the higher-level check has succeeded.
function(_ariadne_resolve_submodule_path REPOSITORY NAME OUTPUT_VARIABLE)
    set(${OUTPUT_VARIABLE} "${NAME}" PARENT_SCOPE)
endfunction()

function(_ariadne_ensure_submodule_initialized REPOSITORY NAME OUTPUT_DIRECTORY)
    set_property(GLOBAL APPEND PROPERTY TEST_VISITS "${REPOSITORY}|${NAME}")
    set(${OUTPUT_DIRECTORY} "${REPOSITORY}/${NAME}" PARENT_SCOPE)
endfunction()

function(get_gitlink_commit REPOSITORY SUBMODULE_PATH OUTPUT_VARIABLE)
    set_property(GLOBAL APPEND PROPERTY TEST_GITLINKS "${REPOSITORY}|${SUBMODULE_PATH}")
    if(SUBMODULE_PATH STREQUAL "testing")
        if(REPOSITORY STREQUAL "numeric/logging/utility")
            set(_commit "UNVISITED_DIFFERENT_COMMIT")
        else()
            set(_commit "TESTING_COMMIT")
        endif()
    elseif(SUBMODULE_PATH STREQUAL "build")
        set(_commit "BUILD_COMMIT")
    else()
        message(FATAL_ERROR "Unexpected gitlink: ${REPOSITORY}/${SUBMODULE_PATH}")
    endif()
    set(${OUTPUT_VARIABLE} "${_commit}" PARENT_SCOPE)
endfunction()

set(PROJECT_SOURCE_DIR "numeric")
require_same_dependency_commit(Testing CHAINS "testing" "logging|testing")
get_property(_before_visits GLOBAL PROPERTY TEST_VISITS)
get_property(_before_links GLOBAL PROPERTY TEST_GITLINKS)

set(PROJECT_SOURCE_DIR "numeric/logging")
require_same_dependency_commit(Testing CHAINS "testing" "utility|testing")
get_property(_after_visits GLOBAL PROPERTY TEST_VISITS)
get_property(_after_links GLOBAL PROPERTY TEST_GITLINKS)
if(NOT "${_before_visits}" STREQUAL "${_after_visits}" OR
   NOT "${_before_links}" STREQUAL "${_after_links}")
    message(FATAL_ERROR "Certified Testing caused redundant Git traversal")
endif()

# Certification is scoped to dependency name, not the whole project.
require_same_dependency_commit(Build CHAINS "build" "utility|build")
get_property(_other_visits GLOBAL PROPERTY TEST_VISITS)
if("${_before_visits}" STREQUAL "${_other_visits}")
    message(FATAL_ERROR "Testing certification also skipped Build")
endif()
message(STATUS "Temporary minimizechecks regression passed")
