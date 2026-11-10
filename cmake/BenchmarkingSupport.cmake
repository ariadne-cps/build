include_guard(GLOBAL)

# Initialize Benchmarking independently of Testing. The optional Benchmarking
# dependency owns the 'benchmarks' target and exports a registration macro.
# Register the consumer's benchmarks/ in the ROOT project's directory scope,
# not in Benchmarking's submodule scope.
# The active Logging checkout must match the root Benchmarking Gitlink.
# Do not initialize a second Logging checkout just to validate this.
function(_ariadne_validate_benchmark_logging BENCHMARKING_SOURCE)
    if(NOT TARGET logging)
        message(FATAL_ERROR "Benchmarking requires functional Logging.")
    endif()
    get_target_property(_active_logging_source logging ARIADNE_PROJECT_SOURCE_ROOT)
    if(NOT _active_logging_source)
        message(FATAL_ERROR "Logging did not export its source repository.")
    endif()
    _ariadne_resolve_submodule_path(
        "${BENCHMARKING_SOURCE}" "logging" _benchmark_logging_path)
    get_gitlink_commit(
        "${BENCHMARKING_SOURCE}" "${_benchmark_logging_path}"
        _benchmark_logging_sha)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${_active_logging_source}" rev-parse HEAD
        OUTPUT_VARIABLE _active_logging_sha OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _logging_status ERROR_VARIABLE _logging_error)
    if(NOT _logging_status EQUAL 0 OR
       NOT _active_logging_sha STREQUAL _benchmark_logging_sha)
        message(FATAL_ERROR
            "Active Logging commit '${_active_logging_sha}' differs from "
            "Benchmarking's pinned Logging '${_benchmark_logging_sha}': "
            "${_logging_error}")
    endif()
endfunction()

macro(ariadne_setup_benchmarking)
    if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        if(NOT TARGET benchmarking)
            _ariadne_resolve_submodule_path(
                "${PROJECT_SOURCE_DIR}" "benchmarking" _ariadne_benchmarking_path OPTIONAL)
            if(NOT _ariadne_benchmarking_path STREQUAL "")
                require_same_dependency_commit(Build CHAINS
                    "build" "benchmarking|build")
                ariadne_add_submodule(benchmarking)
                _ariadne_validate_benchmark_logging(
                    "${PROJECT_SOURCE_DIR}/${_ariadne_benchmarking_path}")
            endif()
        endif()
        if(TARGET benchmarking)
            if(NOT COMMAND ariadne_register_project_benchmarks)
                message(FATAL_ERROR
                    "Benchmarking target exists without its benchmark registration API.")
            endif()
            ariadne_register_project_benchmarks()
            if(NOT TARGET ariadne_all_benchmarks)
                add_custom_target(ariadne_all_benchmarks ALL)
                add_dependencies(ariadne_all_benchmarks benchmarks)
            endif()
        endif()
    endif()
    if(TARGET ariadne-benchmarking AND NOT TARGET benchmarking)
        message(FATAL_ERROR
            "Ariadne Benchmarking target exists without its 'benchmarking' interface target.")
    endif()
endmacro()
