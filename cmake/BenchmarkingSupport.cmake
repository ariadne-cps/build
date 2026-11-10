include_guard(GLOBAL)

# Initialize Benchmarking independently of Testing. The optional Benchmarking
# dependency owns the 'benchmarks' target and exports a registration macro.
# Register the consumer's benchmarks/ in the ROOT project's directory scope,
# not in Benchmarking's submodule scope.
macro(ariadne_setup_benchmarking)
    if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        if(NOT TARGET benchmarking)
            _ariadne_resolve_submodule_path(
                "${PROJECT_SOURCE_DIR}" "benchmarking" _ariadne_benchmarking_path OPTIONAL)
            if(NOT _ariadne_benchmarking_path STREQUAL "")
                ariadne_add_submodule(benchmarking)
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
