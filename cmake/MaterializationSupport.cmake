include_guard(GLOBAL)

# The Build checkout providing this helper is the only active Build instance.
get_filename_component(_ARIADNE_ACTIVE_BUILD_SOURCE
    "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(_ARIADNE_MATERIALIZATION_SCRIPT
    "${CMAKE_CURRENT_LIST_DIR}/ListMaterializations.cmake")

# Register only source checkouts selected by the CMake dependency graph.
# Gitlinks inspected solely to verify consistency are intentionally omitted.
function(ariadne_register_materialization NAME SOURCE_DIRECTORY)
    if(NOT TARGET list-materializations)
        return()
    endif()
    get_filename_component(_source "${SOURCE_DIRECTORY}" ABSOLUTE)
    set(_entry "${NAME}|${_source}")
    get_target_property(_registered list-materializations ARIADNE_MATERIALIZATIONS)
    if(_registered)
        list(FIND _registered "${_entry}" _index)
        if(NOT _index EQUAL -1)
            return()
        endif()
    endif()
    set_property(TARGET list-materializations APPEND PROPERTY
        ARIADNE_MATERIALIZATIONS "${_entry}")
endfunction()

function(ariadne_setup_materialization_target)
    if(TARGET list-materializations)
        return()
    endif()
    set(_manifest "${CMAKE_BINARY_DIR}/.ariadne/materializations-$<CONFIG>.txt")
    file(GENERATE OUTPUT "${_manifest}"
        CONTENT "$<JOIN:$<TARGET_PROPERTY:list-materializations,ARIADNE_MATERIALIZATIONS>,\n>\n")
    add_custom_target(list-materializations
        COMMAND "${CMAKE_COMMAND}"
            "-DARIADNE_MATERIALIZATIONS_FILE:FILEPATH=${_manifest}"
            "-DARIADNE_GIT_EXECUTABLE:FILEPATH=${GIT_EXECUTABLE}"
            -P "${_ARIADNE_MATERIALIZATION_SCRIPT}"
        COMMENT "Listing active Git submodule materializations"
        VERBATIM)
    ariadne_register_materialization(build "${_ARIADNE_ACTIVE_BUILD_SOURCE}")
endfunction()
