set(_EMPTY_SENTINEL "__EMPTY__")

include(SlimMetaFunctions)
include(SlimGitFunctions)
include(SlimLoadRequiredPackages)

# ---------------------------------------------------------------------------
# apply_module_flags(<TARGET>)
# Iterates MODULE_NAMES and applies pkg_CFLAGS, pkg_LDFLAGS, pkg_INCLUDE_DIRS,
# and pkg_LIBRARIES from each non-primary module to the given target.
# ---------------------------------------------------------------------------
function(apply_module_flags TARGET)
    foreach(_name IN LISTS MODULE_NAMES)
        meta_get(MODULE "${_name}" primary _is_primary)
        if(_is_primary)
            continue()
        endif()

        meta_get(MODULE "${_name}" pkg_CFLAGS      _cflags)
        meta_get(MODULE "${_name}" pkg_LDFLAGS     _ldflags)
        meta_get(MODULE "${_name}" pkg_INCLUDE_DIRS _inc_dirs)
        meta_get(MODULE "${_name}" pkg_LIBRARIES   _libs)

        if(_cflags)
            target_compile_options(${TARGET} PRIVATE ${_cflags})
        endif()

        if(_inc_dirs)
            target_include_directories(${TARGET} PRIVATE ${_inc_dirs})
        endif()

        if(_ldflags OR _libs)
            target_link_options(${TARGET} PRIVATE ${_ldflags})
            target_link_libraries(${TARGET} PRIVATE ${_libs})
        endif()
    endforeach()
endfunction()

# ---------------------------------------------------------------------------
# get_primary_module(<OUT_VAR>)
# Returns the name of the primary module, or empty string if none found.
# ---------------------------------------------------------------------------
function(get_primary_module OUT_VAR)
    foreach(_name IN LISTS MODULE_NAMES)
        meta_get(MODULE "${_name}" primary _is_primary)
        if(_is_primary)
            set(${OUT_VAR} "${_name}" PARENT_SCOPE)
            return()
        endif()
    endforeach()
    set(${OUT_VAR} "" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# _derive_module_type(<NAME> <OUT_TYPE>)  [internal]
# ---------------------------------------------------------------------------
function(_derive_module_type NAME OUT_TYPE)
    if("${NAME}" STREQUAL "SlimCommon")
        set(${OUT_TYPE} "SlimCommon" PARENT_SCOPE)

    elseif("${NAME}" MATCHES "^SlimCommon[A-Z]")
        string(REGEX REPLACE "^SlimCommon" "" _suffix "${NAME}")
        string(REGEX MATCHALL "[A-Z][a-z0-9]*" _words "${_suffix}")
        list(LENGTH _words _word_count)
        if(_word_count LESS 1 OR _word_count GREATER 2)
            message(FATAL_ERROR "define_module: '${NAME}' must have 1 or 2 words after 'SlimCommon' (got ${_word_count}).")
        endif()
        set(${OUT_TYPE} "SlimCommonOtherlibSublib" PARENT_SCOPE)

    elseif("${NAME}" MATCHES "^Slim[A-Z]")
        string(REGEX REPLACE "^Slim" "" _suffix "${NAME}")
        string(REGEX MATCHALL "[A-Z][a-z0-9]*" _words "${_suffix}")
        list(LENGTH _words _word_count)
        if(NOT _word_count EQUAL 1)
            message(FATAL_ERROR "define_module: '${NAME}' must have exactly 1 word after 'Slim' (got ${_word_count}).")
        endif()
        set(${OUT_TYPE} "SlimLib" PARENT_SCOPE)

    else()
        message(FATAL_ERROR "define_module: '${NAME}' does not match any known module type. Must start with 'Slim'.")
    endif()
endfunction()

# ---------------------------------------------------------------------------
# _set_check_module(<NAME> <MIN_VERSION> <MAX_VERSION>)  [internal]
# ---------------------------------------------------------------------------
function(_set_check_module NAME MIN_VERSION MAX_VERSION)
    meta_get(MODULE "${NAME}" primary _primary)
    if(_primary)
        return()
    endif()
    if(NOT SLIM_USE_LOCAL_SOURCE)
        return()
    endif()

    find_package(PkgConfig REQUIRED)

    meta_get(MODULE "${NAME}" lower _pkg_name)

    set(_constraints "")
    if(NOT "${MIN_VERSION}" STREQUAL "${_EMPTY_SENTINEL}" AND NOT "${MIN_VERSION}" STREQUAL "")
        list(APPEND _constraints "${_pkg_name}>=${MIN_VERSION}")
    endif()
    if(NOT "${MAX_VERSION}" STREQUAL "${_EMPTY_SENTINEL}" AND NOT "${MAX_VERSION}" STREQUAL "")
        list(APPEND _constraints "${_pkg_name}<=${MAX_VERSION}")
    endif()

    if(_constraints)
        pkg_check_modules("${NAME}" REQUIRED ${_constraints})
    else()
        pkg_check_modules("${NAME}" REQUIRED "${_pkg_name}")
    endif()

    find_program(_PKG_CONFIG_EXEC pkg-config)
    if(_PKG_CONFIG_EXEC)
        execute_process(
            COMMAND "${_PKG_CONFIG_EXEC}" --modversion "${_pkg_name}"
            OUTPUT_VARIABLE "${NAME}_RESOLVED_VERSION"
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
    endif()

    foreach(KEY IN ITEMS CFLAGS LDFLAGS LIBRARIES INCLUDE_DIRS LIBRARY_DIRS VERSION)
        meta_set(MODULE "${NAME}" "pkg_${KEY}" "${${NAME}_${KEY}}")
    endforeach()

    meta_set(MODULE "${NAME}" found_version "${${NAME}_RESOLVED_VERSION}")
    _propagate_module("${NAME}")
endfunction()

# ---------------------------------------------------------------------------
# _set_metadata_file(<NAME>)  [internal]
# ---------------------------------------------------------------------------
function(_set_metadata_file NAME)
    meta_get(MODULE "${NAME}" lower _lower)
    meta_get(MODULE "${NAME}" hpp_only _hpp_only)
    if(_hpp_only)
        meta_set(MODULE "${NAME}" metadata_file_in "cmake/slim_header_lib.pc.in")
    else()
        meta_set(MODULE "${NAME}" metadata_file_in "cmake/slim_common_lib.pc.in")
    endif()
    meta_set(MODULE "${NAME}" metadata_file_out "${_lower}.pc")
    _propagate_module("${NAME}")
endfunction()

# ---------------------------------------------------------------------------
# _set_module_headers(<NAME>)  [internal]
# ---------------------------------------------------------------------------
function(_set_module_headers NAME)
    _derive_module_type("${NAME}" _type)

    if("${_type}" STREQUAL "SlimCommon")
        # need to make sure that correct sub-module headers are collected

    elseif("${_type}" STREQUAL "SlimLib")
        meta_set(MODULE "${NAME}" hpp_only        "ON")
        set(_hdr_in "include/slim/${NAME}.hpp.in")
        string(REGEX REPLACE "\.in$" "" _hdr_out "${_hdr_in}")
        meta_set(MODULE "${NAME}" header_prefix   "${NAME}")
        meta_set(MODULE "${NAME}" header_file_in  "${_hdr_in}")
        meta_set(MODULE "${NAME}" header_file_out "${_hdr_out}")
        meta_set(MODULE "${NAME}" include_dir     "include/slim")

    elseif("${_type}" STREQUAL "SlimCommonOtherlibSublib")
        string(REGEX REPLACE "^SlimCommon" "" _suffix "${NAME}")
        string(REGEX MATCHALL "[A-Z][a-z0-9]*" _words "${_suffix}")
        list(GET _words 0 _word0)
        string(TOLOWER "${_word0}" _word0)
        list(LENGTH _words _word_count)

        if(_word_count EQUAL 1)
            set(_hdr_in  "include/slim/common/${_word0}.h.in")
            set(_inc_dir "include/slim/common")
            meta_set(MODULE "${NAME}" header_prefix "${_word0}")
        elseif(_word_count EQUAL 2)
            list(GET _words 1 _word1)
            string(TOLOWER "${_word1}" _word1)
            set(_hdr_in  "include/slim/common/${_word0}/${_word1}.h.in")
            set(_inc_dir "include/slim/common/${_word0}")
            meta_set(MODULE "${NAME}" header_prefix "${_word1}")
        endif()
        string(REGEX REPLACE "\.in$" "" _hdr_out "${_hdr_in}")
        meta_set(MODULE "${NAME}" header_file_in  "${_hdr_in}")
        meta_set(MODULE "${NAME}" header_file_out "${_hdr_out}")
        meta_set(MODULE "${NAME}" include_dir     "${_inc_dir}")

    endif()

    _propagate_module("${NAME}")
endfunction()

# ---------------------------------------------------------------------------
# _set_package_info(<NAME>)  [internal]
# ---------------------------------------------------------------------------
function(_set_package_info NAME)
    string(TOUPPER "${NAME}" _upper)
    string(TOLOWER "${NAME}" _lower)
    meta_set(MODULE "${NAME}" upper "${_upper}")
    meta_set(MODULE "${NAME}" lower "${_lower}")

    if(ARGC GREATER 3 AND "${ARGV3}" STREQUAL "ON")
        meta_set(MODULE "${NAME}" primary ON)
    endif()

    if(ARGC GREATER 1 AND NOT "${ARGV1}" STREQUAL "")
        meta_set(MODULE "${NAME}" min_version   "${ARGV1}")
    endif()
    if(ARGC GREATER 2 AND NOT "${ARGV2}" STREQUAL "")
        meta_set(MODULE "${NAME}" max_version   "${ARGV2}")
    endif()
    _propagate_module("${NAME}")
endfunction()

# ---------------------------------------------------------------------------
# _set_source_info(<NAME>)  [internal]
# ---------------------------------------------------------------------------
function(_set_source_info NAME)
    meta_get(MODULE "${NAME}" primary _primary)

    if(_primary)
        if(SLIM_USE_LOCAL_SOURCE)
            meta_set(MODULE "${NAME}" using_local_src "ON")
            meta_set(MODULE "${NAME}" src_dir "${CMAKE_SOURCE_DIR}")
        else()
            meta_get(MODULE "${NAME}" git_repo       _repo_url)
            meta_get(MODULE "${NAME}" git_latest_tag _git_tag)

            include(FetchContent)
            FetchContent_Declare(
                "${NAME}"
                GIT_REPOSITORY "${_repo_url}"
                GIT_TAG        "${_git_tag}"
            )
            FetchContent_MakeAvailable("${NAME}")

            string(TOLOWER "${NAME}" _lower)
            meta_set(MODULE "${NAME}" src_dir "${${_lower}_SOURCE_DIR}")
        endif()
    else()
        if(NOT SLIM_USE_LOCAL_SOURCE)
            meta_get(MODULE "${NAME}" git_repo       _repo_url)
            meta_get(MODULE "${NAME}" git_latest_tag _git_tag)

            include(FetchContent)
            FetchContent_Declare(
                "${NAME}"
                GIT_REPOSITORY "${_repo_url}"
                GIT_TAG        "${_git_tag}"
            )
            FetchContent_MakeAvailable("${NAME}")

            string(TOLOWER "${NAME}" _lower)
            meta_set(MODULE "${NAME}" src_dir "${${_lower}_SOURCE_DIR}")
        endif()
    endif()

    _propagate_module("${NAME}")
endfunction()

# -------------------------------------------------------------------------------
# define_module([NAME] [min_version] [max_version] [ON])
#   No args: derives name from CMAKE_SOURCE_DIR and auto-loads required_packages.
# -------------------------------------------------------------------------------
function(define_module)
    # ------------------------------------------------------------------
    # No-arg branch: primary module derived from CMAKE_SOURCE_DIR
    # ------------------------------------------------------------------
    if(ARGC EQUAL 0)
        cmake_path(GET CMAKE_SOURCE_DIR FILENAME NAME)

        define_module("${NAME}" "${_EMPTY_SENTINEL}" "${_EMPTY_SENTINEL}" ON)
        set(REQUIRED_PACKAGE_FILE "${CMAKE_SOURCE_DIR}/required_packages")
        _load_required_packages(${REQUIRED_PACKAGE_FILE})
        _propagate_module("${NAME}")
        return()
    endif()

    # ---------------------------------------------------------------------
    # Re-entrant branch: compute and store all derived fields incrementally
    # ---------------------------------------------------------------------
    _set_package_info("${ARGV0}" ${ARGV1} ${ARGV2} ${ARGV3})
    _set_metadata_file("${ARGV0}")
    _set_module_headers("${ARGV0}")
    _set_git_repo("${ARGV0}")
    _set_check_module("${ARGV0}" "${ARGV1}" "${ARGV2}")
    _set_source_info("${ARGV0}")
    _propagate_module("${ARGV0}")
endfunction()