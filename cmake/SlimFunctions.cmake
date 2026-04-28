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
    set(MODULE_NAMES          "${MODULE_NAMES}"          PARENT_SCOPE)
    set(MODULE_${NAME}_FIELDS "${MODULE_${NAME}_FIELDS}" PARENT_SCOPE)
    foreach(_prop_key IN LISTS MODULE_${NAME}_FIELDS)
        set(MODULE_${NAME}_${_prop_key} "${MODULE_${NAME}_${_prop_key}}" PARENT_SCOPE)
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
# _set_git_repo(<NAME>)  [internal]
# ---------------------------------------------------------------------------
function(_set_git_repo NAME)
    meta_get(MODULE "${NAME}" git_repo _repo_url)

    find_program(_CURL_EXEC curl)
    if(NOT _CURL_EXEC)
        message(WARNING "_set_git_repo: curl not found, skipping repo check for '${NAME}'")
        meta_set(MODULE "${NAME}" git_repo_found "OFF")
        _propagate_module("${NAME}")
        return()
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
        message(WARNING "_set_git_repo: '${_repo_url}' returned ${_http_code}, expected 301")
        meta_set(MODULE "${NAME}" git_repo_found "OFF")
    endif()

    _propagate_module("${NAME}")
endfunction()

# ---------------------------------------------------------------------------
# _set_git_tag(<NAME>)  [internal] — primary module only
# ---------------------------------------------------------------------------
function(_set_git_tag NAME)
    if(SLIM_USE_LOCAL_SOURCE)
        meta_set(MODULE "${NAME}" git_tag  "0.0.0")
        meta_set(MODULE "${NAME}" git_hash "none")
        _propagate_module("${NAME}")
        return()
    endif()

    meta_get(MODULE "${NAME}" git_repo _repo_url)

    execute_process(
        COMMAND git ls-remote --tags --sort=-v:refname "${_repo_url}"
        OUTPUT_VARIABLE _tags_raw
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    string(REGEX MATCH "refs/tags/([^\^\\n]+)" _ "${_tags_raw}")
    set(_tag "${CMAKE_MATCH_1}")

    if("${_tag}" STREQUAL "")
        meta_set(MODULE "${NAME}" git_tag  "")
        meta_set(MODULE "${NAME}" git_hash "")
        _propagate_module("${NAME}")
        return()
    endif()

    execute_process(
        COMMAND git ls-remote "${_repo_url}" "refs/tags/${_tag}"
        OUTPUT_VARIABLE _hash_raw
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

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
        meta_set(MODULE "${NAME}" git_latest_tag "")
        _propagate_module("${NAME}")
        return()
    endif()

    meta_get(MODULE "${NAME}" git_repo _repo_url)

    find_program(_GIT_EXEC git)
    if(NOT _GIT_EXEC)
        message(WARNING "_set_git_repo_latest_tag: git not found, skipping tag fetch for '${NAME}'")
        meta_set(MODULE "${NAME}" git_latest_tag "")
        _propagate_module("${NAME}")
        return()
    endif()

    execute_process(
        COMMAND "${_GIT_EXEC}" ls-remote --tags --sort=-version:refname "${_repo_url}"
        OUTPUT_VARIABLE _tag_output
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    string(REGEX MATCH "refs/tags/([^\n^]+)" _ "${_tag_output}")
    meta_set(MODULE "${NAME}" git_latest_tag "${CMAKE_MATCH_1}")
    _propagate_module("${NAME}")
endfunction()

# ---------------------------------------------------------------------------
# _set_check_module(<NAME> <MIN_VERSION> <MAX_VERSION>)  [internal]
# ---------------------------------------------------------------------------
function(_set_check_module NAME MIN_VERSION MAX_VERSION)
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
# define_module([NAME] [min_version] [max_version])
#   No args: derives name from CMAKE_SOURCE_DIR and auto-loads required_packages.
# ---------------------------------------------------------------------------
function(define_module)
    # ------------------------------------------------------------------
    # No-arg branch: primary module derived from CMAKE_SOURCE_DIR
    # ------------------------------------------------------------------
    if(ARGC EQUAL 0)
        cmake_path(GET CMAKE_SOURCE_DIR FILENAME NAME)

        define_module("${NAME}" "${_EMPTY_SENTINEL}" "${_EMPTY_SENTINEL}" ON)
        _set_git_repo("${NAME}")
        _set_git_tag("${NAME}")
        _set_git_repo_latest_tag("${NAME}")
        _propagate_module("${NAME}")

        if(EXISTS "${CMAKE_SOURCE_DIR}/required_packages")
            file(STRINGS "${CMAKE_SOURCE_DIR}/required_packages" _package_lines REGEX "^[^#\n]")
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
                    _set_check_module("${_pkg}" "${_pkg_min}" "${_pkg_max}")
                    _set_git_repo("${_pkg}")
                    _set_git_tag("${_pkg}")
                    _set_git_repo_latest_tag("${_pkg}")
                    _propagate_module("${_pkg}")
                endif()
            endforeach()
        else()
            message(WARNING "define_module: no required_packages file found at ${CMAKE_SOURCE_DIR}")
        endif()

        return()
    endif()

    # ------------------------------------------------------------------
    # Named branch: compute and store all derived fields incrementally
    # ------------------------------------------------------------------
    set(NAME "${ARGV0}")

    set(_primary OFF)
    if(ARGC GREATER 3 AND "${ARGV3}" STREQUAL "ON")
        set(_primary ON)
    endif()

    set(_min_version "${_EMPTY_SENTINEL}")
    set(_max_version "${_EMPTY_SENTINEL}")
    if(ARGC GREATER 1 AND NOT "${ARGV1}" STREQUAL "")
        set(_min_version "${ARGV1}")
    endif()
    if(ARGC GREATER 2 AND NOT "${ARGV2}" STREQUAL "")
        set(_max_version "${ARGV2}")
    endif()

    _derive_module_type("${NAME}" _type)

    string(TOUPPER "${NAME}" _upper)
    string(TOLOWER "${NAME}" _lower)

    meta_set(MODULE "${NAME}" upper         "${_upper}")
    meta_set(MODULE "${NAME}" lower         "${_lower}")
    meta_set(MODULE "${NAME}" primary       "${_primary}")
    meta_set(MODULE "${NAME}" min_version   "${_min_version}")
    meta_set(MODULE "${NAME}" max_version   "${_max_version}")
    meta_set(MODULE "${NAME}" git_repo      "${_SLIM_GIT_BASE}/${NAME}.git")
    meta_set(MODULE "${NAME}" metadata_file "${_lower}.pc")

    if("${_type}" STREQUAL "SlimLib")
        meta_set(MODULE "${NAME}" hpp_only "ON")
    else()
        meta_set(MODULE "${NAME}" hpp_only "OFF")
    endif()

    if("${_type}" STREQUAL "SlimCommon")
        meta_set(MODULE "${NAME}" header_prefix   "")
        meta_set(MODULE "${NAME}" header_file_in  "")
        meta_set(MODULE "${NAME}" header_file_out "")
        meta_set(MODULE "${NAME}" include_dir     "")

    elseif("${_type}" STREQUAL "SlimCommonOtherlibSublib")
        string(REGEX REPLACE "^SlimCommon" "" _suffix "${NAME}")
        string(REGEX MATCHALL "[A-Z][a-z0-9]*" _words "${_suffix}")
        list(GET _words 0 _word0)
        string(TOLOWER "${_word0}" _word0)
        list(LENGTH _words _word_count)

        if(_word_count EQUAL 1)
            set(_hdr_in  "include/slim/${_word0}.h.in")
            set(_inc_dir "include/slim")
            meta_set(MODULE "${NAME}" header_prefix "${_word0}")
        else()
            list(GET _words 1 _word1)
            string(TOLOWER "${_word1}" _word1)
            set(_hdr_in  "include/slim/${_word0}/${_word1}.h.in")
            set(_inc_dir "include/slim/${_word0}")
            meta_set(MODULE "${NAME}" header_prefix "${_word1}")
        endif()
        string(REGEX REPLACE "\.in$" "" _hdr_out "${_hdr_in}")
        meta_set(MODULE "${NAME}" header_file_in  "${_hdr_in}")
        meta_set(MODULE "${NAME}" header_file_out "${_hdr_out}")
        meta_set(MODULE "${NAME}" include_dir     "${_inc_dir}")

    else() # SlimLib
        set(_hdr_in "include/slim/${NAME}.hpp.in")
        string(REGEX REPLACE "\.in$" "" _hdr_out "${_hdr_in}")
        meta_set(MODULE "${NAME}" header_prefix   "${NAME}")
        meta_set(MODULE "${NAME}" header_file_in  "${_hdr_in}")
        meta_set(MODULE "${NAME}" header_file_out "${_hdr_out}")
        meta_set(MODULE "${NAME}" include_dir     "include/slim")
    endif()

    _propagate_module("${NAME}")
endfunction()