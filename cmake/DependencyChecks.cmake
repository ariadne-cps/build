include_guard(GLOBAL)

find_package(Git REQUIRED)
include(CMakeParseArguments)
include(DependencySnapshot)

# OPTIONAL returns an empty path when the logical submodule is not declared;
# mandatory callers retain their existing strict failure behavior.
function(_ariadne_resolve_submodule_path REPOSITORY NAME OUTPUT_VARIABLE)
    set(_optional FALSE)
    if(ARGC GREATER 3 AND ARGV3 STREQUAL "OPTIONAL")
        set(_optional TRUE)
    endif()
    set(_gitmodules "${REPOSITORY}/.gitmodules")
    if(NOT EXISTS "${_gitmodules}")
        if(_optional)
            set(${OUTPUT_VARIABLE} "" PARENT_SCOPE)
            return()
        endif()
        message(FATAL_ERROR
            "Repository ${REPOSITORY} has no .gitmodules while resolving '${NAME}'.")
    endif()

    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_gitmodules}")

    # Submodule paths are checkout details (e.g. ss/uti), whereas NAME is the
    # logical GitHub repository name (e.g. utility). Use each submodule URL
    # rather than its directory basename, supporting both long and short paths.
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" config --file "${_gitmodules}"
                --get-regexp "^submodule\\..*\\.url$"
        OUTPUT_VARIABLE _urls_output
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _urls_error
        RESULT_VARIABLE _urls_result
    )
    if(NOT _urls_result EQUAL 0)
        if(_optional AND _urls_output STREQUAL "" AND _urls_error STREQUAL "")
            set(${OUTPUT_VARIABLE} "" PARENT_SCOPE)
            return()
        endif()
        message(FATAL_ERROR
            "Cannot read submodule URLs from ${_gitmodules}: ${_urls_error}")
    endif()

    set(_matches)
    string(REPLACE "\n" ";" _url_lines "${_urls_output}")
    foreach(_line IN LISTS _url_lines)
        if(_line MATCHES "^([^ \t]+)[ \t]+(.+)$")
            set(_url_key "${CMAKE_MATCH_1}")
            set(_url "${CMAKE_MATCH_2}")
            string(REGEX REPLACE "\\.git/?$" "" _url "${_url}")
            string(REGEX REPLACE "/+$" "" _url "${_url}")
            string(REGEX REPLACE "^.*[/:]" "" _logical_name "${_url}")
            if(_logical_name STREQUAL "${NAME}")
                string(REGEX REPLACE "\\.url$" ".path" _path_key "${_url_key}")
                execute_process(
                    COMMAND "${GIT_EXECUTABLE}" config --file "${_gitmodules}"
                            --get "${_path_key}"
                    OUTPUT_VARIABLE _path
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_VARIABLE _path_error
                    RESULT_VARIABLE _path_result
                )
                if(NOT _path_result EQUAL 0 OR _path STREQUAL "")
                    message(FATAL_ERROR
                        "No path for submodule '${NAME}' in ${_gitmodules}: ${_path_error}")
                endif()
                list(APPEND _matches "${_path}")
            endif()
        endif()
    endforeach()

    list(LENGTH _matches _match_count)
    if(_optional AND _match_count EQUAL 0)
        set(${OUTPUT_VARIABLE} "" PARENT_SCOPE)
        return()
    endif()
    if(NOT _match_count EQUAL 1)
        message(FATAL_ERROR
            "Submodule '${NAME}' resolves to ${_match_count} paths in "
            "${_gitmodules}; expected exactly one URL match.")
    endif()

    list(GET _matches 0 _path)
    set(${OUTPUT_VARIABLE} "${_path}" PARENT_SCOPE)
endfunction()

# Register the Git index as a configure dependency of this CMake
# project. A plain `git pull` or `git checkout` changing pinned gitlinks
# updates the index, so cmake --build (including --target benchmarks) first
# reruns CMake and lets ariadne_add_submodule resolve the recorded commits.
# Never follow remote branches: only the superproject's pinned gitlinks.
# rev-parse --git-path works for ordinary checkouts and linked worktrees.
function(ariadne_watch_git_index)
    if(NOT EXISTS "${PROJECT_SOURCE_DIR}/.git")
        return()
    endif()
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${PROJECT_SOURCE_DIR}"
                rev-parse --git-path index
        OUTPUT_VARIABLE _index_path
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _index_error
        RESULT_VARIABLE _index_result
    )
    if(NOT _index_result EQUAL 0 OR _index_path STREQUAL "")
        message(FATAL_ERROR
            "Cannot locate the Git index for ${PROJECT_SOURCE_DIR}: ${_index_error}")
    endif()
    if(NOT IS_ABSOLUTE "${_index_path}")
        get_filename_component(_index_path "${_index_path}" ABSOLUTE
            BASE_DIR "${PROJECT_SOURCE_DIR}")
    endif()
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${_index_path}")
endfunction()

function(_ariadne_ensure_submodule_initialized REPOSITORY NAME OUTPUT_DIRECTORY)
    _ariadne_resolve_submodule_path("${REPOSITORY}" "${NAME}" _path)

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}" submodule status -- "${_path}"
        OUTPUT_VARIABLE _status
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _status_error
        RESULT_VARIABLE _status_result
    )
    if(NOT _status_result EQUAL 0)
        message(FATAL_ERROR
            "Cannot inspect submodule ${REPOSITORY}/${_path}: ${_status_error}")
    endif()

    if(_status MATCHES "^U")
        message(FATAL_ERROR
            "Cannot align conflicted submodule ${REPOSITORY}/${_path};"
            " resolve the Git index conflict first.")
    endif()

    if(_status MATCHES "^[-+]")
        # Never replace a populated checkout with outstanding local changes,
        # even when Git might be able to switch commits without overwriting
        # their contents. Nested submodule gitlinks are checked separately.
        if(_status MATCHES "^\\+")
            execute_process(
                COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}/${_path}"
                        status --porcelain --untracked-files=all
                        --ignore-submodules=all
                OUTPUT_VARIABLE _dirty
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_VARIABLE _dirty_error
                RESULT_VARIABLE _dirty_result
            )
            if(NOT _dirty_result EQUAL 0)
                message(FATAL_ERROR
                    "Cannot inspect local changes in ${REPOSITORY}/${_path}: ${_dirty_error}")
            endif()
            if(NOT _dirty STREQUAL "")
                message(FATAL_ERROR
                    "Submodule ${REPOSITORY}/${_path} has local changes and"
                    " is not at the recorded commit. Commit/stash them"
                    " before rebuilding; automatic checkout is disabled.")
            endif()
        endif()
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                    submodule update --init -- "${_path}"
            ERROR_VARIABLE _update_error
            RESULT_VARIABLE _update_result
        )
        if(NOT _update_result EQUAL 0)
            message(FATAL_ERROR
                "Cannot align submodule ${REPOSITORY}/${_path}: ${_update_error}")
        endif()
        message(STATUS "Aligned submodule ${REPOSITORY}/${_path}"
            " to its recorded commit")
    endif()

    set(${OUTPUT_DIRECTORY} "${REPOSITORY}/${_path}" PARENT_SCOPE)
endfunction()

function(ensure_submodule_initialized NAME)
    set(options)
    set(oneValueArgs REPOSITORY)
    cmake_parse_arguments(
        SUBMODULE "${options}" "${oneValueArgs}" "" ${ARGN})

    if(SUBMODULE_REPOSITORY)
        set(_repository "${SUBMODULE_REPOSITORY}")
    else()
        set(_repository "${PROJECT_SOURCE_DIR}")
    endif()

    _ariadne_ensure_submodule_initialized(
        "${_repository}" "${NAME}" _directory)
endfunction()

# Resolve and initialize by logical repository name, then add its
# physical checkout directory. Keep a macro so child project() and
# add_subdirectory() retain the caller's CMake directory scope.
macro(ariadne_add_submodule NAME)
    # Only the compilation root may select an auxiliary Testing or
    # Benchmarking checkout. Nested modules cannot override that selection.
    if(("${NAME}" STREQUAL "testing" OR "${NAME}" STREQUAL "benchmarking")
       AND NOT CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        message(VERBOSE "Ignoring nested auxiliary submodule '${NAME}'")
    else()
        _ariadne_ensure_submodule_initialized(
            "${PROJECT_SOURCE_DIR}" "${NAME}" _ariadne_submodule_source)
        get_filename_component(_ariadne_submodule_basename
            "${_ariadne_submodule_source}" NAME)
        add_subdirectory("${_ariadne_submodule_source}"
            "${CMAKE_CURRENT_BINARY_DIR}/${_ariadne_submodule_basename}")
    endif()
endmacro()

function(get_gitlink_commit REPOSITORY SUBMODULE_PATH OUTPUT_VARIABLE)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                ls-files --stage -- "${SUBMODULE_PATH}"
        OUTPUT_VARIABLE _entry OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _error RESULT_VARIABLE _result)
    if(NOT _result EQUAL 0 OR NOT _entry MATCHES "^160000 ([0-9a-fA-F]+) 0[\t ]")
        message(FATAL_ERROR
            "Cannot determine a unique staged Gitlink for ${REPOSITORY}/${SUBMODULE_PATH}: "
            "${_error} ${_entry}")
    endif()
    set(${OUTPUT_VARIABLE} "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()

function(require_same_dependency_commit NAME)
    set(options)
    set(oneValueArgs)
    set(multiValueArgs CHAINS)
    cmake_parse_arguments(
        CHECK "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT CHECK_CHAINS)
        message(FATAL_ERROR
            "require_same_dependency_commit(${NAME}) requires CHAINS.")
    endif()

    if(NOT EXISTS "${PROJECT_SOURCE_DIR}/.git")
        return()
    endif()

    # Do not certify a wider chain set from a narrower prior check.
    string(SHA256 _certification_key
        "${PROJECT_SOURCE_DIR}|${NAME}|${CHECK_CHAINS}")
    get_property(_certified GLOBAL PROPERTY
        "ARIADNE_DEPENDENCY_CERTIFIED_${_certification_key}")
    if(_certified)
        return()
    endif()
    _ariadne_dependency_cache_matches("${_certification_key}" _cached)
    if(_cached)
        set_property(GLOBAL PROPERTY
            "ARIADNE_DEPENDENCY_CERTIFIED_${_certification_key}" TRUE)
        message(STATUS "Reused verified ${NAME} Gitlink constraints")
        return()
    endif()
    set(_checked_gitlinks)

    set(_expected "")
    set(_terminal_name "")
    set(_details "")

    foreach(_chain IN LISTS CHECK_CHAINS)
        string(REPLACE "|" ";" _tokens "${_chain}")
        list(LENGTH _tokens _token_count)
        if(_token_count EQUAL 0)
            message(FATAL_ERROR "Invalid empty dependency chain for ${NAME}.")
        endif()

        math(EXPR _last_index "${_token_count} - 1")
        list(GET _tokens ${_last_index} _chain_terminal)

        if(_terminal_name STREQUAL "")
            set(_terminal_name "${_chain_terminal}")
        elseif(NOT _terminal_name STREQUAL _chain_terminal)
            message(FATAL_ERROR
                "All ${NAME} CHAINS must terminate at the same dependency.")
        endif()

        set(_repository "${PROJECT_SOURCE_DIR}")
        set(_index 0)
        foreach(_token IN LISTS _tokens)
            _ariadne_resolve_submodule_path(
                "${_repository}" "${_token}" _path)
            list(APPEND _checked_gitlinks "${_repository}|${_path}")
            if(_index EQUAL _last_index)
                get_gitlink_commit("${_repository}" "${_path}" _commit)
            else()
                _ariadne_ensure_submodule_initialized(
                    "${_repository}" "${_token}" _repository)
            endif()
            math(EXPR _index "${_index} + 1")
        endforeach()

        string(APPEND _details "  ${_chain}: ${_commit}\n")

        if(_expected STREQUAL "")
            set(_expected "${_commit}")
        elseif(NOT _expected STREQUAL _commit)
            message(FATAL_ERROR
                "Inconsistent ${NAME} dependency:\n${_details}")
        endif()
    endforeach()

    _ariadne_dependency_cache_record("${_certification_key}" ${_checked_gitlinks})
    # Certify only after *all* chains have been successfully compared.
    set_property(GLOBAL PROPERTY
        "ARIADNE_DEPENDENCY_CERTIFIED_${_certification_key}" TRUE)
    message(STATUS "Verified ${NAME} dependency commit: ${_expected}")
endfunction()
