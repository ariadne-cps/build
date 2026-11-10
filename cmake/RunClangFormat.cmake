cmake_minimum_required(VERSION 3.15)

foreach(_required IN ITEMS ARIADNE_FORMAT_ROOT ARIADNE_FORMAT_CONFIG ARIADNE_FORMAT_MODE)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
        message(FATAL_ERROR "Missing ${_required}")
    endif()
endforeach()
if(NOT ARIADNE_FORMAT_MODE MATCHES "^(check|impose)$")
    message(FATAL_ERROR "Unknown formatting mode: ${ARIADNE_FORMAT_MODE}")
endif()
if(NOT EXISTS "${ARIADNE_FORMAT_CONFIG}")
    message(FATAL_ERROR "Shared clang-format configuration missing: ${ARIADNE_FORMAT_CONFIG}")
endif()

find_program(_ariadne_git NAMES git)
if(NOT _ariadne_git)
    message(FATAL_ERROR "Git is required for ${ARIADNE_FORMAT_MODE}-format")
endif()

if(DEFINED ARIADNE_CLANG_FORMAT_EXECUTABLE AND
   NOT "${ARIADNE_CLANG_FORMAT_EXECUTABLE}" STREQUAL "")
    set(_formatter "${ARIADNE_CLANG_FORMAT_EXECUTABLE}")
else()
    find_program(_formatter NAMES clang-format-18 clang-format)
endif()
if(NOT _formatter)
    message(FATAL_ERROR "clang-format 18 is required for ${ARIADNE_FORMAT_MODE}-format")
endif()
execute_process(
    COMMAND "${_formatter}" --version
    RESULT_VARIABLE _version_result
    OUTPUT_VARIABLE _version_output
    ERROR_VARIABLE _version_error)
if(NOT _version_result EQUAL 0 OR NOT _version_output MATCHES "version ([0-9]+)")
    message(FATAL_ERROR "Cannot determine clang-format version: ${_version_output} ${_version_error}")
endif()
if(NOT CMAKE_MATCH_1 EQUAL 18)
    message(FATAL_ERROR "clang-format version 18 required, got: ${_version_output}")
endif()

execute_process(
    COMMAND "${_ariadne_git}" -C "${ARIADNE_FORMAT_ROOT}"
        -c core.quotePath=false ls-files --cached -- include src python/bindings
    RESULT_VARIABLE _git_result
    OUTPUT_VARIABLE _tracked_files
    ERROR_VARIABLE _git_error)
if(NOT _git_result EQUAL 0)
    message(FATAL_ERROR "Cannot list tracked source files: ${_git_error}")
endif()

# Process only the calling repo's tracked files (excluding nested submodules).
string(REPLACE ";" "\\;" _tracked_files "${_tracked_files}")
string(REPLACE "\n" ";" _tracked_files "${_tracked_files}")
set(_selected_files)
foreach(_path IN LISTS _tracked_files)
    if(_path MATCHES "^(include|src|python/bindings)/.+[.](cpp|hpp)$" AND
       EXISTS "${ARIADNE_FORMAT_ROOT}/${_path}")
        list(APPEND _selected_files "${ARIADNE_FORMAT_ROOT}/${_path}")
    endif()
endforeach()

list(LENGTH _selected_files _file_count)
if(_file_count EQUAL 0)
    message(STATUS "No tracked C++ sources to format in ${ARIADNE_FORMAT_ROOT}")
    return()
endif()

set(_args "--style=file:${ARIADNE_FORMAT_CONFIG}")
if(ARIADNE_FORMAT_MODE STREQUAL "check")
    list(APPEND _args --dry-run --Werror)
else()
    list(APPEND _args -i)
endif()

# Batches avoid excessively long command lines, particularly on Windows.
set(_batch)
set(_failed_batches 0)
macro(_run_format_batch)
    if(_batch)
        execute_process(
            COMMAND "${_formatter}" ${_args} ${_batch}
            RESULT_VARIABLE _status
            OUTPUT_VARIABLE _stdout
            ERROR_VARIABLE _stderr)
        if(NOT "${_stdout}" STREQUAL "")
            message("${_stdout}")
        endif()
        if(NOT "${_stderr}" STREQUAL "")
            message("${_stderr}")
        endif()
        if(NOT "${_status}" STREQUAL "0")
            math(EXPR _failed_batches "${_failed_batches} + 1")
        endif()
        set(_batch)
    endif()
endmacro()

foreach(_file IN LISTS _selected_files)
    list(APPEND _batch "${_file}")
    list(LENGTH _batch _batch_count)
    if(_batch_count GREATER_EQUAL 32)
        _run_format_batch()
    endif()
endforeach()
_run_format_batch()

if(_failed_batches GREATER 0)
    message(FATAL_ERROR "${ARIADNE_FORMAT_MODE}-format failed (${_failed_batches} batch(es))")
endif()
message(STATUS "${ARIADNE_FORMAT_MODE}-format succeeded for ${_file_count} tracked C++ files")
