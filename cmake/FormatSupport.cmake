include_guard(GLOBAL)

# The caller's project owns the files; Build provides the implementation.
set(_ariadne_format_script "${CMAKE_CURRENT_LIST_DIR}/RunClangFormat.cmake")

function(ariadne_setup_format_targets)
    # Nested dependencies must not create duplicate targets or scan each other.
    if(NOT CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        return()
    endif()

    foreach(_mode IN ITEMS check apply)
        if(NOT TARGET ${_mode}-format)
            add_custom_target(${_mode}-format
                COMMAND "${CMAKE_COMMAND}"
                    "-DARIADNE_FORMAT_ROOT:PATH=${PROJECT_SOURCE_DIR}"
                    "-DARIADNE_FORMAT_CONFIG:FILEPATH=${PROJECT_SOURCE_DIR}/ss/bui/.clang-format"
                    "-DARIADNE_FORMAT_MODE:STRING=${_mode}"
                    "-DARIADNE_CLANG_FORMAT_EXECUTABLE:FILEPATH=${ARIADNE_CLANG_FORMAT_EXECUTABLE}"
                    -P "${_ariadne_format_script}"
                COMMENT "${_mode}-format: C++ source formatting"
                VERBATIM USES_TERMINAL)
        endif()
    endforeach()
endfunction()
