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
    meta_get(MODULE "${_primary}" dist_dir       _dist_dir)

    if(NOT _dist_dir)
        message(FATAL_ERROR "compile_targets: no dist_dir defined for '${_primary}'")
    endif()

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

    # --- Build targets (static omitted when using local source) -----------
    set(_linkages shared)
    if(NOT SLIM_USE_LOCAL_SOURCE)
        list(APPEND _linkages static)
    endif()

    meta_get(MODULE "${_primary}" upper _upper)
    foreach(_linkage ${_linkages})
        set(_target ${_lower}_${_linkage})

        if("${_linkage}" STREQUAL "shared")
            add_library(${_target} SHARED "${_src}")
            set_target_properties(${_target} PROPERTIES
                OUTPUT_NAME ${_lower}
                VERSION     ${_version}
                SOVERSION   ${_version_major}
            )
        else()
            add_library(${_target} STATIC "${_src}")
            set_target_properties(${_target} PROPERTIES
                OUTPUT_NAME ${_lower}
            )
        endif()

        target_include_directories(${_target}
            PUBLIC
                $<BUILD_INTERFACE:${_src_dir}/${_inc_dir}>
                $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/${_inc_dir}>
                $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
        )
        message(STATUS "Applying compile options to ${_target}")
        apply_slim_compile_options(${_target})
        target_compile_features(${_target} PUBLIC cxx_std_${SLIM_CXX_STANDARD})

        # Header and .pc installs are handled by make_install_artifacts()
        install(TARGETS ${_target}
            EXPORT  ${_upper}Targets
            LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
            ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        )
    endforeach()

    # --- Alias ------------------------------------------------------------
    add_library(${_lower} ALIAS ${_lower}_shared)

    _propagate_module("${_primary}")
endfunction()

# ---------------------------------------------------------------------------
# test_targets()
# Compiles src/test.cpp into two executables against the libraries produced by
# compile_targets(). test_shared links against the shared and static libraries.
# test_static is fully statically linked against the static library (-static /
# /MT). Both mirror the primary module's include directories and compile
# options, and are run as a POST_BUILD step.
# When SLIM_USE_LOCAL_SOURCE is ON only the shared linkage is built.
# ---------------------------------------------------------------------------
function(test_targets)
    get_primary_module(_primary)
    if(NOT _primary)
        message(FATAL_ERROR "test_targets: no primary module defined")
    endif()

    meta_get(MODULE "${_primary}" lower       _lower)
    meta_get(MODULE "${_primary}" src_dir     _src_dir)
    meta_get(MODULE "${_primary}" include_dir _inc_dir)
    meta_get(MODULE "${_primary}" hpp_only    _hpp_only)

    set(_test_src "${_src_dir}/src/test.cpp")
    if(NOT EXISTS "${_test_src}")
        message(STATUS "test_targets: src/test.cpp not found, skipping")
        return()
    endif()

#    if(NOT _hpp_only)
#        message(STATUS "test_targets: library target properties before compilation:")
#        dump_target_properties(${_lower}_shared)
#        dump_target_properties(${_lower}_static)
#    endif()

    enable_testing()

    set(_linkages shared)
    if(NOT SLIM_USE_LOCAL_SOURCE)
        list(APPEND _linkages static)
    endif()
    foreach(_linkage ${_linkages})
        set(_target ${_lower}_test_${_linkage})

        add_executable(${_target} "${_test_src}")

        target_include_directories(${_target}
            PRIVATE
                $<BUILD_INTERFACE:${_src_dir}/${_inc_dir}>
                $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/${_inc_dir}>
        )

        if(NOT _hpp_only)
            target_link_libraries(${_target} PRIVATE ${_lower}_${_linkage})
            if("${_linkage}" STREQUAL "shared" AND NOT SLIM_USE_LOCAL_SOURCE)
                target_link_libraries(${_target} PRIVATE ${_lower}_static)
            elseif("${_linkage}" STREQUAL "static")
                if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
                    target_link_options(${_target} PRIVATE /MT)
                else()
                    target_link_options(${_target} PRIVATE -static)
                endif()
            endif()
        endif()

        apply_slim_compile_options(${_target})
        target_compile_features(${_target} PRIVATE cxx_std_${SLIM_CXX_STANDARD})

        add_custom_command(TARGET ${_target} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E echo "Running ${_target}..."
            COMMAND $<TARGET_FILE:${_target}>
            COMMENT "Running ${_target}"
        )
        add_test(NAME ${_target} COMMAND $<TARGET_FILE:${_target}>)
        message(STATUS "test_targets: added target '${_target}'")
    endforeach()
endfunction()

# ---------------------------------------------------------------------------
# test_catch2_targets()
# Fetches Catch2 v3.5.0, compiles all tests/*.cpp sources from the primary
# module's source tree, and wires them up with CTest and catch_discover_tests.
# Mirrors the primary module's include directories and compile options.
# Runs the test executable as a POST_BUILD step.
# ---------------------------------------------------------------------------
function(test_catch2_targets)
    get_primary_module(_primary)
    if(NOT _primary)
        message(FATAL_ERROR "test_catch2_targets: no primary module defined")
    endif()

    meta_get(MODULE "${_primary}" lower       _lower)
    meta_get(MODULE "${_primary}" src_dir     _src_dir)
    meta_get(MODULE "${_primary}" include_dir _inc_dir)
    meta_get(MODULE "${_primary}" hpp_only    _hpp_only)

    set(_tests_dir "${_src_dir}/tests")
    if(NOT EXISTS "${_tests_dir}")
        message(STATUS "test_catch2_targets: disabled (no tests directory found)")
        return()
    endif()
    message(STATUS "test_catch2_targets: enabled")

    file(GLOB_RECURSE _test_sources "${_tests_dir}/*.cpp")

    if(NOT _hpp_only)
        message(STATUS "test_catch2_targets: library target properties before compilation:")
        dump_target_properties(${_lower}_shared)
        if(NOT SLIM_USE_LOCAL_SOURCE)
            dump_target_properties(${_lower}_static)
        endif()
    endif()

    include(FetchContent)
    FetchContent_Declare(
        Catch2
        GIT_REPOSITORY https://github.com/catchorg/Catch2.git
        GIT_TAG v3.5.0
    )
    FetchContent_MakeAvailable(Catch2)

    enable_testing()

    add_executable(${_lower}_catch2_tests ${_test_sources})

    target_include_directories(${_lower}_catch2_tests
        PRIVATE
            $<BUILD_INTERFACE:${_src_dir}/${_inc_dir}>
            $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/${_inc_dir}>
    )

    if(NOT _hpp_only)
        if(SLIM_USE_LOCAL_SOURCE)
            target_link_libraries(${_lower}_catch2_tests PRIVATE ${_lower}_shared)
        else()
            target_link_libraries(${_lower}_catch2_tests PRIVATE ${_lower}_static)
        endif()
    endif()

    apply_slim_compile_options(${_lower}_catch2_tests)
    target_compile_features(${_lower}_catch2_tests PRIVATE cxx_std_${SLIM_CXX_STANDARD})

    target_link_libraries(${_lower}_catch2_tests PRIVATE Catch2::Catch2WithMain)

    include(CTest)
    add_test(NAME ${_lower}_catch2_tests COMMAND $<TARGET_FILE:${_lower}_catch2_tests>)

    add_custom_command(TARGET ${_lower}_catch2_tests POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E echo "Running ${_lower}_catch2_tests..."
        COMMAND $<TARGET_FILE:${_lower}_catch2_tests>
        COMMENT "Running ${_lower}_catch2_tests"
    )

    message(STATUS "test_catch2_targets: added target '${_lower}_catch2_tests'")
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