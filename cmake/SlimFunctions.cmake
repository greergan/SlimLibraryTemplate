set(_EMPTY_SENTINEL "__EMPTY__")
set(_SLIM_GIT_BASE "https://github.com/greergan")

# ---------------------------------------------------------------------------
# meta_set(<PREFIX> <NAME> <KEY> <VALUE>)
# ---------------------------------------------------------------------------
function(meta_set PREFIX NAME KEY VALUE)
    set(_fields "${${PREFIX}_${NAME}_FIELDS}")
    list(FIND _fields "${KEY}" _idx)
    if(_idx EQUAL -1)
        list(APPEND _fields "${KEY}")
        set("${PREFIX}_${NAME}_FIELDS" "${_fields}" PARENT_SCOPE)
    endif()

    if("${VALUE}" STREQUAL "")
        set("${PREFIX}_${NAME}_${KEY}" "${_EMPTY_SENTINEL}" PARENT_SCOPE)
    else()
        set("${PREFIX}_${NAME}_${KEY}" "${VALUE}" PARENT_SCOPE)
    endif()

    set(_names "${${PREFIX}_NAMES}")
    list(FIND _names "${NAME}" _name_idx)
    if(_name_idx EQUAL -1)
        list(APPEND _names "${NAME}")
        set("${PREFIX}_NAMES" "${_names}" PARENT_SCOPE)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# meta_get(<PREFIX> <NAME> <KEY> <OUT_VAR>)
# ---------------------------------------------------------------------------
function(meta_get PREFIX NAME KEY OUT_VAR)
    set(VAR "${PREFIX}_${NAME}_${KEY}")
    if(DEFINED ${VAR})
        set(_val "${${VAR}}")
        if("${_val}" STREQUAL "${_EMPTY_SENTINEL}")
            set(_val "")
        endif()
        set(${OUT_VAR} "${_val}" PARENT_SCOPE)
    else()
        set(${OUT_VAR} "" PARENT_SCOPE)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# _propagate_module(<NAME>)  [internal]
# ---------------------------------------------------------------------------
macro(_propagate_module NAME)
    set(MODULE_NAMES "${MODULE_NAMES}" PARENT_SCOPE)
    foreach(_prop_name IN LISTS MODULE_NAMES)
        set(MODULE_${_prop_name}_FIELDS "${MODULE_${_prop_name}_FIELDS}" PARENT_SCOPE)
        foreach(_prop_key IN LISTS MODULE_${_prop_name}_FIELDS)
            set(MODULE_${_prop_name}_${_prop_key} "${MODULE_${_prop_name}_${_prop_key}}" PARENT_SCOPE)
        endforeach()
    endforeach()
endmacro()

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
# _load_required_packages(<FILE>)  [internal]
# ---------------------------------------------------------------------------
function(_load_required_packages FILE)
    if(NOT EXISTS "${FILE}")
        message(WARNING "_load_required_packages: file not found '${FILE}'")
        return()
    endif()
    message(STATUS "_load_required_packages: processing file '${FILE}'")

    file(STRINGS "${FILE}" _package_lines REGEX "^[^#\n]")
    foreach(_line IN LISTS _package_lines)
        string(STRIP "${_line}" _line)
        if(NOT "${_line}" STREQUAL "")
            string(REGEX MATCHALL "[^ \t]+" _tokens "${_line}")
            list(GET _tokens 0 _pkg)
            list(LENGTH _tokens _token_count)

            set(_pkg_min "${_EMPTY_SENTINEL}")
            set(_pkg_max "${_EMPTY_SENTINEL}")
            if(_token_count GREATER 1)
                list(GET _tokens 1 _pkg_min)
                if("${_pkg_min}" STREQUAL "")
                    set(_pkg_min "${_EMPTY_SENTINEL}")
                endif()
            endif()
            if(_token_count GREATER 2)
                list(GET _tokens 2 _pkg_max)
                if("${_pkg_max}" STREQUAL "")
                    set(_pkg_max "${_EMPTY_SENTINEL}")
                endif()
            endif()

            define_module("${_pkg}" "${_pkg_min}" "${_pkg_max}")
            _propagate_module("${_pkg}")
        endif()
    endforeach()
endfunction()

# ---------------------------------------------------------------------------
# _set_git_repo(<NAME>)  [internal]
# ---------------------------------------------------------------------------
function(_set_git_repo NAME)
    meta_set(MODULE "${NAME}" git_repo  "${_SLIM_GIT_BASE}/${NAME}.git")
    meta_get(MODULE "${NAME}" git_repo _repo_url)

    find_program(_CURL_EXEC curl)
    if(NOT _CURL_EXEC)
        message(FATAL_ERROR "_set_git_repo: curl not found, '${NAME}'")
    endif()

    execute_process(
        COMMAND "${_CURL_EXEC}"
            --silent --output /dev/null --write-out "%{http_code}"
            --max-time 5 "${_repo_url}"
        OUTPUT_VARIABLE _http_code
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    if("${_http_code}" EQUAL 301)
        meta_set(MODULE "${NAME}" git_repo_found "ON")
    else()
        message(FATAL_ERROR "_set_git_repo: '${_repo_url}' returned ${_http_code}, expected 301")
    endif()

    _set_git_tag("${NAME}")  
    _set_git_repo_latest_tag("${NAME}")

    _propagate_module("${NAME}")
endfunction()

# ---------------------------------------------------------------------------
# _set_git_tag(<NAME>)  [internal] — primary module only
# ---------------------------------------------------------------------------
function(_set_git_tag NAME)

    meta_get(MODULE "${NAME}" primary _primary)

    if(SLIM_USE_LOCAL_SOURCE)
        if(_primary)
            meta_set(MODULE "${NAME}" git_tag  "0.0.0")
            meta_set(MODULE "${NAME}" git_hash "local-src")
        else()
            meta_set(MODULE "${NAME}" git_tag  "0.0.0")
            meta_set(MODULE "${NAME}" git_hash "pkg-config")
        endif()
        _propagate_module("${NAME}")
        return()
    endif()

    meta_get(MODULE "${NAME}" git_repo _repo_url)

    execute_process(
        COMMAND git ls-remote --tags --sort=-v:refname "${_repo_url}"
        OUTPUT_VARIABLE _tags_raw
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _result
        ERROR_VARIABLE  _error
    )
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR "_set_get_git_tag: git ls-remote failed for '${_repo_url}'\n${_error}")
    endif()

    string(REGEX MATCH "refs/tags/([^\^\\n]+)" _ "${_tags_raw}")
    set(_tag "${CMAKE_MATCH_1}")

    execute_process(
        COMMAND git ls-remote "${_repo_url}" "refs/tags/${_tag}"
        OUTPUT_VARIABLE _hash_raw
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _result
        ERROR_VARIABLE  _error
    )
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR "_set_get_git_tag: git ls-remote failed for '${_repo_url}' refs/tags/${_tag}\n${_error}")
    endif()

    string(REGEX MATCH "^([a-f0-9]+)" _ "${_hash_raw}")
    set(_hash "${CMAKE_MATCH_1}")
    string(SUBSTRING "${_hash}" 0 7 _hash)

    meta_set(MODULE "${NAME}" git_tag  "${_tag}")
    meta_set(MODULE "${NAME}" git_hash "${_hash}")
    _propagate_module("${NAME}")
endfunction()

# ---------------------------------------------------------------------------
# _set_git_repo_latest_tag(<NAME>)  [internal] — auto-loaded modules
# ---------------------------------------------------------------------------
function(_set_git_repo_latest_tag NAME)
    meta_get(MODULE "${NAME}" git_repo_found _repo_found)
    if(NOT _repo_found)
        message(FATAL_ERROR "_set_git_repo_latest_tag: _repo_found not found, for '${NAME}'")
    endif()

    meta_get(MODULE "${NAME}" git_repo _repo_url)

    find_program(_GIT_EXEC git)
    if(NOT _GIT_EXEC)
        message(FATAL_ERROR "_set_git_repo_latest_tag: git not found, skipping tag fetch for '${NAME}'")
    endif()

    execute_process(
        COMMAND "${_GIT_EXEC}" ls-remote --tags --sort=-version:refname "${_repo_url}"
        OUTPUT_VARIABLE _tag_output
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _result
        ERROR_VARIABLE  _error
    )
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR "_set_get_git_repo_latest_tag: git ls-remote failed for '${_repo_url}'\n${_error}")
    endif()

    string(REGEX MATCH "refs/tags/([^\n^]+)" _ "${_tag_output}")
    meta_set(MODULE "${NAME}" git_latest_tag "${CMAKE_MATCH_1}")
    _propagate_module("${NAME}")
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
    meta_set(MODULE "${NAME}" metadata_file "${_lower}.pc")
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