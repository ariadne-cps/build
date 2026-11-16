include_guard(GLOBAL)

# Resolve paths inside the per-worktree Git directory. Linked Git worktrees
# must not share the history of their observed submodule Gitlinks.
function(_ariadne_git_path REPOSITORY RELATIVE_PATH OUTPUT)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                rev-parse --git-path "${RELATIVE_PATH}"
        OUTPUT_VARIABLE _path OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _error RESULT_VARIABLE _result)
    if(NOT _result EQUAL 0 OR _path STREQUAL "")
        message(FATAL_ERROR
            "Cannot resolve Git path '${RELATIVE_PATH}' in ${REPOSITORY}: ${_error}")
    endif()
    if(NOT IS_ABSOLUTE "${_path}")
        get_filename_component(_path "${_path}" ABSOLUTE BASE_DIR "${REPOSITORY}")
    endif()
    set(${OUTPUT} "${_path}" PARENT_SCOPE)
endfunction()

function(_ariadne_watch_git_path REPOSITORY RELATIVE_PATH)
    _ariadne_git_path("${REPOSITORY}" "${RELATIVE_PATH}" _path)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_path}")
endfunction()

# Persist observations outside CMake build directories. Each Git worktree
# has an independent state, so deleting a build never loses an override.
function(_ariadne_submodule_pin_state REPOSITORY SUBMODULE_PATH OUTPUT)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}" rev-parse --absolute-git-dir
        OUTPUT_VARIABLE _git_dir OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _error RESULT_VARIABLE _result)
    if(NOT _result EQUAL 0 OR _git_dir STREQUAL "")
        message(FATAL_ERROR "Cannot resolve Git directory in ${REPOSITORY}: ${_error}")
    endif()
    string(SHA256 _key "${SUBMODULE_PATH}")
    set(${OUTPUT} "${_git_dir}/ariadne/observed-gitlinks/${_key}.txt" PARENT_SCOPE)
endfunction()

function(_ariadne_watch_submodule_head CHECKOUT)
    _ariadne_watch_git_path("${CHECKOUT}" HEAD)
    # When HEAD references a branch, watch the branch ref too.
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${CHECKOUT}" symbolic-ref -q HEAD
        OUTPUT_VARIABLE _ref OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _result ERROR_QUIET)
    if(_result EQUAL 0 AND NOT _ref STREQUAL "")
        _ariadne_watch_git_path("${CHECKOUT}" "${_ref}")
    endif()
endfunction()

# The recorded Gitlink is a synchronization event, not a permanent checkout
# constraint. A manual checkout survives until the parent Gitlink changes.
function(_ariadne_checkout_submodule REPOSITORY SUBMODULE_PATH OUTPUT_DIRECTORY)
    get_gitlink_commit("${REPOSITORY}" "${SUBMODULE_PATH}" _recorded)
    _ariadne_watch_git_path("${REPOSITORY}" index)
    _ariadne_submodule_pin_state("${REPOSITORY}" "${SUBMODULE_PATH}" _state)
    set(_previous "")
    if(EXISTS "${_state}")
        file(READ "${_state}" _previous)
        string(STRIP "${_previous}" _previous)
    endif()

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                submodule status -- "${SUBMODULE_PATH}"
        OUTPUT_VARIABLE _status OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _error RESULT_VARIABLE _result)
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR
            "Cannot inspect submodule ${REPOSITORY}/${SUBMODULE_PATH}: ${_error}")
    endif()
    if(_status MATCHES "^U")
        message(FATAL_ERROR
            "Conflicted Gitlink for ${REPOSITORY}/${SUBMODULE_PATH}; resolve the index first.")
    endif()

    set(_checkout "${REPOSITORY}/${SUBMODULE_PATH}")
    set(_align FALSE)
    if(_status MATCHES "^-")
        set(_align TRUE)
    elseif(NOT _previous STREQUAL "" AND NOT _previous STREQUAL _recorded
           AND _status MATCHES "^\\+")
        set(_align TRUE)
    endif()

    if(_align)
        if(NOT _status MATCHES "^-")
            execute_process(
                COMMAND "${GIT_EXECUTABLE}" -C "${_checkout}"
                        status --porcelain --untracked-files=all --ignore-submodules=all
                OUTPUT_VARIABLE _dirty OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_VARIABLE _error RESULT_VARIABLE _result)
            if(NOT _result EQUAL 0)
                message(FATAL_ERROR "Cannot inspect local changes in ${_checkout}: ${_error}")
            endif()
            if(NOT _dirty STREQUAL "")
                message(FATAL_ERROR
                    "Submodule ${_checkout} has local changes and its recorded Gitlink "
                    "changed from ${_previous} to ${_recorded}. Commit or stash "
                    "those changes before configuring; no checkout was overwritten.")
            endif()
        endif()
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                    submodule update --init -- "${SUBMODULE_PATH}"
            ERROR_VARIABLE _error RESULT_VARIABLE _result)
        if(NOT _result EQUAL 0)
            message(FATAL_ERROR "Cannot initialize or synchronize ${_checkout}: ${_error}")
        endif()
        message(STATUS "Synchronized submodule ${_checkout} to ${_recorded}")
    elseif(_status MATCHES "^\\+")
        message(STATUS "Preserving local submodule checkout ${_checkout}; "
                       "recorded Gitlink is ${_recorded}")
    endif()

    # Establish an initial observation without resetting a populated checkout,
    # and advance the observation only after successful synchronization.
    if(NOT _previous STREQUAL _recorded)
        get_filename_component(_state_dir "${_state}" DIRECTORY)
        file(MAKE_DIRECTORY "${_state_dir}")
        file(WRITE "${_state}" "${_recorded}\n")
    endif()
    _ariadne_watch_submodule_head("${_checkout}")
    set(${OUTPUT_DIRECTORY} "${_checkout}" PARENT_SCOPE)
endfunction()
