include_guard(GLOBAL)

# Only functional direct submodules become production C++ link dependencies.
# Build, Testing, Benchmarking and PythonCommon have other responsibilities.
function(_ariadne_direct_cpp_dependencies OUTPUT)
    set(_dependencies)
    set(_gitmodules "${PROJECT_SOURCE_DIR}/.gitmodules")
    if(EXISTS "${_gitmodules}")
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_gitmodules}")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" config --file "${_gitmodules}"
                    --get-regexp "^submodule\..*\.url$"
            OUTPUT_VARIABLE _urls OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE _status)
        if(NOT _status EQUAL 0)
            message(FATAL_ERROR "Cannot read submodules from ${_gitmodules}")
        endif()
        string(REPLACE "\n" ";" _lines "${_urls}")
        foreach(_line IN LISTS _lines)
            if(_line MATCHES "^[^ \t]+[ \t]+(.+)$")
                set(_url "${CMAKE_MATCH_1}")
                string(REGEX REPLACE "\.git/?$" "" _url "${_url}")
                string(REGEX REPLACE "/+$" "" _url "${_url}")
                string(REGEX REPLACE "^.*[/:]" "" _dependency "${_url}")
                if(_dependency MATCHES "^(build|testing|benchmarking|python-common)$")
                    continue()
                endif()
                string(REPLACE "-" "_" _target "${_dependency}")
                if(NOT TARGET ${_target})
                    message(FATAL_ERROR
                        "Functional submodule '${_dependency}' did not create target '${_target}'")
                endif()
                get_target_property(_role ${_target} ARIADNE_MODULE_ROLE)
                if(_role AND NOT _role STREQUAL "FUNCTIONAL")
                    message(FATAL_ERROR "Target '${_target}' is not a functional C++ module")
                endif()
                list(APPEND _dependencies "${_target}")
            endif()
        endforeach()
    endif()
    list(REMOVE_DUPLICATES _dependencies)
    set(${OUTPUT} "${_dependencies}" PARENT_SCOPE)
endfunction()

# Setup retains CMake's directory scope and uses the root's Testing and
# Benchmarking only for standalone test/benchmark targets.
macro(ariadne_setup_module NAME)
    setup_project()
    include_directories("${PROJECT_SOURCE_DIR}/include")
    add_subdirectory(ss)
    _ariadne_direct_cpp_dependencies(_ariadne_module_dependencies)

    string(REPLACE "-" "_" _ariadne_module_target "${NAME}")
    string(TOUPPER "${_ariadne_module_target}" _ariadne_module_upper)
    set(_ariadne_module_objects "${_ariadne_module_upper}_SRC")
    string(REPLACE "_" "-" _ariadne_module_archive_name "${NAME}")
    set(_ariadne_module_archive "ariadne-${_ariadne_module_archive_name}")

    if(NOT TARGET ${_ariadne_module_target})
        add_library(${_ariadne_module_target} INTERFACE)
        target_include_directories(${_ariadne_module_target} INTERFACE
            "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include>"
            "$<INSTALL_INTERFACE:include/${_ariadne_module_archive}>")
        set_property(TARGET ${_ariadne_module_target} PROPERTY
            ARIADNE_MODULE_ROLE FUNCTIONAL)
        if(_ariadne_module_dependencies)
            target_link_libraries(${_ariadne_module_target} INTERFACE
                ${_ariadne_module_dependencies})
        endif()
        add_subdirectory(src)
        target_link_libraries(${_ariadne_module_objects} PRIVATE
            ${_ariadne_module_target})
    endif()
    ariadne_register_public_headers(
        TARGET ${_ariadne_module_target}
        DIRECTORIES "${PROJECT_SOURCE_DIR}/include/${_ariadne_module_archive_name}"
        FILES "${PROJECT_SOURCE_DIR}/include/${_ariadne_module_archive}.hpp")
    setup_project_library(
        TARGET ${_ariadne_module_archive}
        OBJECTS ${_ariadne_module_objects}
        LINK_LIBRARIES ${_ariadne_module_target})
    setup_standalone_project(
        TARGET ${_ariadne_module_archive}
        TEST_DIRECTORY tests TEST_TARGET tests
        SOURCES "${PROJECT_SOURCE_DIR}/include" "${PROJECT_SOURCE_DIR}/src")
    if(BUILD_PYTHON_BINDINGS AND EXISTS "${PROJECT_SOURCE_DIR}/python/CMakeLists.txt")
        add_subdirectory(python)
    endif()
    if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        ariadne_install_dependency_bundle(
            TARGET ${_ariadne_module_target}
            DESTINATION include/${_ariadne_module_archive})
    endif()
endmacro()
