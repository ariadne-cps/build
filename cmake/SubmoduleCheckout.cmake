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

# When there is no saved observation, a checkout equal to the immediately
# previous parent Gitlink is strong evidence of a parent pull/checkout that
# moved the pin without updating the submodule. Do not infer anything if HEAD
# and the staged Gitlink disagree, or if the parent's reflog is unavailable.
function(_ariadne_checkout_matches_previous_gitlink
         REPOSITORY SUBMODULE_PATH RECORDED CHECKOUT OUTPUT)
    set(${OUTPUT} FALSE PARENT_SCOPE)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                ls-tree HEAD -- "${SUBMODULE_PATH}"
        OUTPUT_VARIABLE _current_entry OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _result ERROR_QUIET)
    if(NOT _result EQUAL 0 OR
       NOT _current_entry MATCHES "^160000 commit ([0-9a-fA-F]+)[\t ]")
        return()
    endif()
    if(NOT CMAKE_MATCH_1 STREQUAL "${RECORDED}")
        return()
    endif()

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                rev-parse --verify "HEAD@{1}^{commit}"
        OUTPUT_VARIABLE _previous_parent OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _result ERROR_QUIET)
    if(NOT _result EQUAL 0 OR _previous_parent STREQUAL "")
        return()
    endif()
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                ls-tree "${_previous_parent}" -- "${SUBMODULE_PATH}"
        OUTPUT_VARIABLE _previous_entry OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _result ERROR_QUIET)
    if(NOT _result EQUAL 0 OR
       NOT _previous_entry MATCHES "^160000 commit ([0-9a-fA-F]+)[\t ]")
        return()
    endif()
    set(_previous_gitlink "${CMAKE_MATCH_1}")
    if(_previous_gitlink STREQUAL "${RECORDED}")
        return()
    endif()

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${CHECKOUT}" rev-parse --verify HEAD
        OUTPUT_VARIABLE _checkout_head OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _result ERROR_QUIET)
    if(_result EQUAL 0 AND _checkout_head STREQUAL _previous_gitlink)
        set(${OUTPUT} TRUE PARENT_SCOPE)
    endif()
endfunction()

# The recorded Gitlink is a synchronization event, not a permanent checkout
# constraint. A manual checkout survives until the parent Gitlink changes.
option(ARIADNE_PRESERVE_INITIAL_SUBMODULE_CHECKOUTS
    "Explicitly preserve and accept initialized submodule overrides on first observation" OFF)
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
    elseif(_previous STREQUAL "" AND _status MATCHES "^\\+"
           AND NOT ARIADNE_PRESERVE_INITIAL_SUBMODULE_CHECKOUTS)
        _ariadne_checkout_matches_previous_gitlink(
            "${REPOSITORY}" "${SUBMODULE_PATH}" "${_recorded}"
            "${_checkout}" _left_behind)
        if(_left_behind)
            set(_align TRUE)
            message(STATUS "Detected checkout left at previous Gitlink: ${_checkout}")
        endif()
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
                if(_previous STREQUAL "")
                    set(_baseline "<unobserved>")
                else()
                    set(_baseline "${_previous}")
                endif()
                message(FATAL_ERROR
                    "Submodule ${_checkout} has local changes and its recorded Gitlink "
                    "changed from ${_baseline} to ${_recorded}. Commit or stash "
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
        if(_previous STREQUAL "" AND NOT ARIADNE_PRESERVE_INITIAL_SUBMODULE_CHECKOUTS)
            message(STATUS "Previous Gitlink could not be established reliably; "
                           "leaving this first observation unrecorded")
        endif()
    endif()

    # A preserved, unknown mismatch is not a successful initial observation.
    # An explicit preserve option accepts it; later parent pin changes may
    # again synchronize it according to the usual observed-Gitlink semantics.
    set(_accept TRUE)
    if(_previous STREQUAL "" AND _status MATCHES "^\\+" AND NOT _align
       AND NOT ARIADNE_PRESERVE_INITIAL_SUBMODULE_CHECKOUTS)
        set(_accept FALSE)
    endif()
    if(_accept AND NOT _previous STREQUAL _recorded)
        get_filename_component(_state_dir "${_state}" DIRECTORY)
        file(MAKE_DIRECTORY "${_state_dir}")
        file(WRITE "${_state}" "${_recorded}\n")
    endif()
    _ariadne_watch_submodule_head("${_checkout}")
    set(${OUTPUT_DIRECTORY} "${_checkout}" PARENT_SCOPE)
endfunction()
