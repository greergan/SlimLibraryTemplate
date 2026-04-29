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
