set(_EMPTY_SENTINEL "__EMPTY__")

# ---------------------------------------------------------------------------
# meta_create(<PREFIX> <NAME> key1 value1 key2 value2 ...)
# ---------------------------------------------------------------------------
function(meta_create PREFIX NAME)
    set(_fields "")
    set(_args ${ARGN})
    list(LENGTH _args _len)
    math(EXPR _pairs "${_len} / 2")

    if(_pairs EQUAL 0)
        set("${PREFIX}_${NAME}_FIELDS" "" PARENT_SCOPE)
        return()
    endif()

    math(EXPR _last "${_pairs} - 1")
    foreach(i RANGE 0 ${_last})
        math(EXPR k_idx "2 * ${i}")
        math(EXPR v_idx "2 * ${i} + 1")

        list(GET _args ${k_idx} KEY)
        list(GET _args ${v_idx} VAL)

        set("${PREFIX}_${NAME}_${KEY}" "${VAL}" PARENT_SCOPE)
        list(APPEND _fields "${KEY}")
    endforeach()

    set("${PREFIX}_${NAME}_FIELDS" "${_fields}" PARENT_SCOPE)
    set(_current "${${PREFIX}_NAMES}")
    list(APPEND _current "${NAME}")
    set("${PREFIX}_NAMES" "${_current}" PARENT_SCOPE)
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
# _store_pkgconfig_info(<NAME> <PKG_NAME>)  [internal]
# ---------------------------------------------------------------------------
function(_store_pkgconfig_info NAME PKG_NAME)
    foreach(KEY IN ITEMS CFLAGS LDFLAGS LIBRARIES INCLUDE_DIRS LIBRARY_DIRS VERSION)
        set(_val "${${NAME}_${KEY}}")
        if("${_val}" STREQUAL "")
            set(_val "${_EMPTY_SENTINEL}")
        endif()
        set(MODULE_${NAME}_pkg_${KEY} "${_val}" PARENT_SCOPE)
    endforeach()

    # use the explicitly fetched version from pkg_get_variable
    # pkg_check_modules does not reliably populate VERSION
    set(_found "${${NAME}_RESOLVED_VERSION}")
    if("${_found}" STREQUAL "")
        set(_found "${_EMPTY_SENTINEL}")
    endif()

    set(MODULE_${NAME}_found_version "${_found}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# _check_module(<NAME> <MIN_VERSION> <MAX_VERSION>)  [internal]
# ---------------------------------------------------------------------------
function(_check_module NAME MIN_VERSION MAX_VERSION)
    find_package(PkgConfig REQUIRED)

    meta_get(MODULE "${NAME}" lower _pkg_name)

    # build version constraints as separate tokens
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

    # pkg_check_modules does not reliably populate VERSION
    # fetch it explicitly from the .pc file instead
    #pkg_get_variable("${NAME}_RESOLVED_VERSION" "${_pkg_name}" "Version")
	find_program(_PKG_CONFIG_EXEC pkg-config)
	if(_PKG_CONFIG_EXEC)
		if(_PKG_CONFIG_EXEC)
			execute_process(
				COMMAND "${_PKG_CONFIG_EXEC}" --modversion "${_pkg_name}"
				OUTPUT_VARIABLE "${NAME}_RESOLVED_VERSION"
				OUTPUT_STRIP_TRAILING_WHITESPACE
				ERROR_QUIET
			)
		endif()
	endif()

    _store_pkgconfig_info("${NAME}" "${_pkg_name}")

    # propagate updated fields and values
    set(MODULE_${NAME}_FIELDS "${MODULE_${NAME}_FIELDS}" PARENT_SCOPE)
    foreach(KEY IN LISTS MODULE_${NAME}_FIELDS)
        set(MODULE_${NAME}_${KEY} "${MODULE_${NAME}_${KEY}}" PARENT_SCOPE)
    endforeach()
endfunction()

# ---------------------------------------------------------------------------
# define_module([NAME] [min_version] [max_version])
#   No args: derives name from CMAKE_SOURCE_DIR and auto-loads required_packages
# ---------------------------------------------------------------------------
function(define_module)
    if(ARGC EQUAL 0)
        cmake_path(GET CMAKE_SOURCE_DIR FILENAME NAME)
        set(_primary ON)
        set(_min_version "${_EMPTY_SENTINEL}")
        set(_max_version "${_EMPTY_SENTINEL}")

        # auto-load modules from required_packages
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

                    # propagate what the recursive call registered
                    set(MODULE_NAMES              "${MODULE_NAMES}"              PARENT_SCOPE)
                    set(MODULE_${_pkg}_FIELDS     "${MODULE_${_pkg}_FIELDS}"     PARENT_SCOPE)
                    foreach(KEY IN LISTS MODULE_${_pkg}_FIELDS)
                        set(MODULE_${_pkg}_${KEY} "${MODULE_${_pkg}_${KEY}}"     PARENT_SCOPE)
                    endforeach()

                    _check_module("${_pkg}" "${_pkg_min}" "${_pkg_max}")

                    # propagate pkg-config info
                    set(MODULE_${_pkg}_FIELDS     "${MODULE_${_pkg}_FIELDS}"     PARENT_SCOPE)
                    foreach(KEY IN LISTS MODULE_${_pkg}_FIELDS)
                        set(MODULE_${_pkg}_${KEY} "${MODULE_${_pkg}_${KEY}}"     PARENT_SCOPE)
                    endforeach()
                endif()
            endforeach()
        else()
            message(WARNING "define_module: no required_packages file found at ${CMAKE_SOURCE_DIR}")
        endif()

    else()
        set(NAME "${ARGV0}")
        set(_primary OFF)

        set(_min_version "${_EMPTY_SENTINEL}")
        set(_max_version "${_EMPTY_SENTINEL}")
        if(ARGC GREATER 1)
            if(NOT "${ARGV1}" STREQUAL "")
                set(_min_version "${ARGV1}")
            endif()
        endif()
        if(ARGC GREATER 2)
            if(NOT "${ARGV2}" STREQUAL "")
                set(_max_version "${ARGV2}")
            endif()
        endif()
    endif()

    _derive_module_type("${NAME}" _type)

    string(TOUPPER "${NAME}" _upper)
    string(TOLOWER "${NAME}" _lower)

    set(_metadata_file "${_lower}.pc")

    if("${_type}" STREQUAL "SlimCommon")
        set(_primary ON)
    endif()

    if("${_type}" STREQUAL "SlimLib")
        set(_hpp_only ON)
    else()
        set(_hpp_only OFF)
    endif()

    if("${_type}" STREQUAL "SlimCommon")
        set(_header_prefix   "${_EMPTY_SENTINEL}")
        set(_header_file_in  "${_EMPTY_SENTINEL}")
        set(_header_file_out "${_EMPTY_SENTINEL}")
        set(_include_dir     "${_EMPTY_SENTINEL}")

    elseif("${_type}" STREQUAL "SlimCommonOtherlibSublib")
        string(REGEX REPLACE "^SlimCommon" "" _suffix "${NAME}")
        string(REGEX MATCHALL "[A-Z][a-z0-9]*" _words "${_suffix}")

        list(GET _words 0 _word0)
        string(TOLOWER "${_word0}" _word0)
        list(LENGTH _words _word_count)

        if(_word_count EQUAL 1)
            set(_header_prefix   "${_word0}")
            set(_header_file_in  "include/slim/${_word0}.h.in")
            set(_include_dir     "include/slim")
        else()
            list(GET _words 1 _word1)
            string(TOLOWER "${_word1}" _word1)
            set(_header_prefix   "${_word1}")
            set(_header_file_in  "include/slim/${_word0}/${_word1}.h.in")
            set(_include_dir     "include/slim/${_word0}")
        endif()
        string(REGEX REPLACE "\.in$" "" _header_file_out "${_header_file_in}")

    else() # SlimLib
        set(_header_prefix   "${NAME}")
        set(_header_file_in  "include/slim/${NAME}.hpp.in")
        set(_include_dir     "include/slim")
        string(REGEX REPLACE "\.in$" "" _header_file_out "${_header_file_in}")
    endif()

    meta_create(MODULE "${NAME}"
        upper            "${_upper}"
        lower            "${_lower}"
        primary          "${_primary}"
        hpp_only         "${_hpp_only}"
        min_version      "${_min_version}"
        max_version      "${_max_version}"
        found_version    "${_EMPTY_SENTINEL}"
        header_prefix    "${_header_prefix}"
        header_file_in   "${_header_file_in}"
        header_file_out  "${_header_file_out}"
        include_dir      "${_include_dir}"
        metadata_file    "${_metadata_file}"
        pkg_CFLAGS       "${_EMPTY_SENTINEL}"
        pkg_LDFLAGS      "${_EMPTY_SENTINEL}"
        pkg_LIBRARIES    "${_EMPTY_SENTINEL}"
        pkg_INCLUDE_DIRS "${_EMPTY_SENTINEL}"
        pkg_LIBRARY_DIRS "${_EMPTY_SENTINEL}"
        pkg_VERSION      "${_EMPTY_SENTINEL}"
    )

    set(MODULE_NAMES          "${MODULE_NAMES}"          PARENT_SCOPE)
    set(MODULE_${NAME}_FIELDS "${MODULE_${NAME}_FIELDS}" PARENT_SCOPE)
    foreach(KEY IN LISTS MODULE_${NAME}_FIELDS)
        set(MODULE_${NAME}_${KEY} "${MODULE_${NAME}_${KEY}}" PARENT_SCOPE)
    endforeach()
endfunction()