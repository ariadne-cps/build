include_guard(GLOBAL)

# Optional standalone benchmark support, independent of Testing. Benchmarking
# is not linked to production targets and is never initialized from their
# nested subdirectories. Its own CMakeLists.txt registers 'benchmarks' and the
# root project's benchmarks/ when available.
macro(ariadne_setup_benchmarking)
    if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR AND NOT TARGET benchmarking)
        _ariadne_resolve_submodule_path(
            "${PROJECT_SOURCE_DIR}" "benchmarking" _ariadne_benchmarking_path OPTIONAL)
        if(NOT _ariadne_benchmarking_path STREQUAL "")
            ariadne_add_submodule(benchmarking)
        endif()
    endif()
    if(TARGET ariadne-benchmarking AND NOT TARGET benchmarking)
        message(FATAL_ERROR
            "Ariadne Benchmarking target exists without its 'benchmarking' interface target.")
    endif()
endmacro()
