function(apply_slim_compile_options TARGET)
    get_target_property(_existing ${TARGET} COMPILE_OPTIONS)
    if(_existing MATCHES "NOTFOUND$")
        target_compile_options(${TARGET} PRIVATE ${SLIM_CXX_FLAGS})
        apply_module_flags(${TARGET})
    else()
        message(WARNING "apply_slim_compile_options: '${TARGET}' already has COMPILE_OPTIONS set, skipping")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# compile_targets()
# Derives all target information from the primary module's metadata.
# ---------------------------------------------------------------------------
function(compile_targets)
    get_primary_module(_primary)
    if(NOT _primary)
        message(FATAL_ERROR "compile_targets: no primary module defined")
    endif()

    meta_get(MODULE "${_primary}" lower          _lower)
    meta_get(MODULE "${_primary}" git_tag        _version)
    meta_get(MODULE "${_primary}" src_dir        _src_dir)
    meta_get(MODULE "${_primary}" include_dir    _inc_dir)
    meta_get(MODULE "${_primary}" hpp_only       _hpp_only)

    if(_hpp_only)
        message(STATUS "Library targets: header-only, skipping shared/static build")
        return()
    endif()

    set(_src "${_src_dir}/src/main.cpp")
    if(NOT EXISTS "${_src}")
        message(FATAL_ERROR "setup_slim_library_targets: source not found '${_src}'")
    endif()

    # --- Version components -----------------------------------------------
    string(REGEX MATCH "^([0-9]+)" _ "${_version}")
    set(_version_major "${CMAKE_MATCH_1}")

    # --- Shared library ---------------------------------------------------
    add_library(${_lower}_shared SHARED "${_src}")
    set_target_properties(${_lower}_shared PROPERTIES
        OUTPUT_NAME ${_lower}
        VERSION     ${_version}
        SOVERSION   ${_version_major}
    )
    add_custom_command(TARGET ${_lower}_shared POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo "Shared lib: $<TARGET_FILE_NAME:${_lower}_shared>"
    )

    # --- Static library ---------------------------------------------------
    add_library(${_lower}_static STATIC "${_src}")
    set_target_properties(${_lower}_static PROPERTIES
        OUTPUT_NAME ${_lower}
    )
    add_custom_command(TARGET ${_lower}_static POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo "Static lib: $<TARGET_FILE_NAME:${_lower}_static>"
    )

    # --- Common target settings -------------------------------------------
    foreach(_target ${_lower}_shared ${_lower}_static)
        target_include_directories(${_target}
            PUBLIC
                $<BUILD_INTERFACE:${_src_dir}/${_inc_dir}>
                $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/${_inc_dir}>
                $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
        )
		message(STATUS "Applying compile options to ${_target}")
        apply_slim_compile_options(${_target})
        target_compile_features(${_target} PUBLIC cxx_std_${SLIM_CXX_STANDARD})
    endforeach()

    # --- Alias ------------------------------------------------------------
    add_library(${_lower} ALIAS ${_lower}_shared)

    # --- Install ----------------------------------------------------------
    meta_get(MODULE "${_primary}" upper _upper)
    install(TARGETS ${_lower}_shared ${_lower}_static
        EXPORT ${_upper}Targets
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    )

    _propagate_module("${_primary}")
endfunction()

# ---------------------------------------------------------------------------
# dump_target_properties(<TARGET>)
# Prints all common target properties to STATUS output.
# ---------------------------------------------------------------------------
function(dump_target_properties TARGET)
    if(NOT TARGET ${TARGET})
        message(WARNING "dump_target_properties: '${TARGET}' is not a valid target")
        return()
    endif()

    set(_props
        TYPE
        OUTPUT_NAME
        VERSION
        SOVERSION
        COMPILE_OPTIONS
        COMPILE_DEFINITIONS
        COMPILE_FEATURES
        INCLUDE_DIRECTORIES
        LINK_LIBRARIES
        LINK_OPTIONS
        LINK_DIRECTORIES
        INTERFACE_INCLUDE_DIRECTORIES
        INTERFACE_LINK_LIBRARIES
        INTERFACE_COMPILE_OPTIONS
        INTERFACE_COMPILE_DEFINITIONS
        POSITION_INDEPENDENT_CODE
    )

    message(STATUS "  === Target: ${TARGET} ===")
    foreach(_prop IN LISTS _props)
        get_target_property(_val ${TARGET} ${_prop})
        if(NOT _val MATCHES "NOTFOUND$")
            message(STATUS "    ${_prop}: ${_val}")
        endif()
    endforeach()
endfunction()
