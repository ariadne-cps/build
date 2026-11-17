# Executed at build time: read the configured source paths and their current
# HEADs without initializing, checking out, or modifying any submodule.
if(NOT EXISTS "${ARIADNE_MATERIALIZATIONS_FILE}")
    message(FATAL_ERROR "Missing materialization manifest: ${ARIADNE_MATERIALIZATIONS_FILE}")
endif()
if(NOT ARIADNE_GIT_EXECUTABLE)
    message(FATAL_ERROR "Git executable was not supplied")
endif()

file(STRINGS "${ARIADNE_MATERIALIZATIONS_FILE}" _materializations)
message("Active submodule materializations:")
foreach(_entry IN LISTS _materializations)
    if(NOT _entry MATCHES "^([^|]+)[|](.+)$")
        message(FATAL_ERROR "Invalid materialization entry: ${_entry}")
    endif()
    set(_name "${CMAKE_MATCH_1}")
    set(_path "${CMAKE_MATCH_2}")
    if(NOT IS_DIRECTORY "${_path}")
        message(FATAL_ERROR "Materialization ${_name} is missing: ${_path}")
    endif()
    execute_process(
        COMMAND "${ARIADNE_GIT_EXECUTABLE}" -C "${_path}" rev-parse --show-toplevel
        OUTPUT_VARIABLE _root OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _error RESULT_VARIABLE _status)
    if(NOT _status EQUAL 0)
        message(FATAL_ERROR "Cannot inspect ${_name} at ${_path}: ${_error}")
    endif()
    get_filename_component(_actual_root "${_root}" REALPATH)
    get_filename_component(_expected_root "${_path}" REALPATH)
    if(NOT _actual_root STREQUAL _expected_root)
        message(FATAL_ERROR
            "Materialization ${_name} at ${_path} is not a Git checkout root")
    endif()
    execute_process(
        COMMAND "${ARIADNE_GIT_EXECUTABLE}" -C "${_path}" rev-parse --verify HEAD
        OUTPUT_VARIABLE _sha OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _error RESULT_VARIABLE _status)
    if(NOT _status EQUAL 0 OR _sha STREQUAL "")
        message(FATAL_ERROR "Cannot read HEAD for ${_name} at ${_path}: ${_error}")
    endif()
    message("  ${_name}: ${_path} [${_sha}]")
endforeach()
