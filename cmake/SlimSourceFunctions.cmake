# ---------------------------------------------------------------------------
# generate_main_cpp()
# Generates src/main.cpp containing only #include lines — one per non-primary
# sub-module's resolved header.
# Only runs when SLIM_USE_LOCAL_SOURCE is ON.
# ---------------------------------------------------------------------------
function(generate_main_cpp)
    if(NOT SLIM_USE_LOCAL_SOURCE)
        message(STATUS "generate_main_cpp: skipped (SLIM_USE_LOCAL_SOURCE is OFF)")
        return()
    endif()
 
    get_primary_module(_primary)
    if(NOT _primary)
        message(FATAL_ERROR "generate_main_cpp: no primary module defined")
    endif()
 
    meta_get(MODULE "${_primary}" src_dir _src_dir)
 
    # --- Collect #include lines from every non-primary sub-module ---------
    set(_includes "")
    foreach(_name IN LISTS MODULE_NAMES)
        meta_get(MODULE "${_name}" primary _is_primary)
        if(_is_primary)
            continue()
        endif()
 
        meta_get(MODULE "${_name}" header_file_out _hdr)
        if(NOT _hdr)
            message(WARNING "generate_main_cpp: module '${_name}' has no header_file_out, skipping")
            continue()
        endif()
 
        # header_file_out is relative to src_dir, e.g. include/slim/common/foo/bar.h
        # Strip the leading include/ so the path matches the compiler's -I include/ root
        string(REGEX REPLACE "^include/" "" _hdr_rel "${_hdr}")
        list(APPEND _includes "#include <${_hdr_rel}>")
    endforeach()
 
    if(NOT _includes)
        message(WARNING "generate_main_cpp: no sub-module headers found, aborting")
        return()
    endif()
 
    # --- Write src/main.cpp -----------------------------------------------
    list(JOIN _includes "\n" _includes_block)
    set(_out_src "${_src_dir}/src/main.cpp")
    file(WRITE "${_out_src}" "${_includes_block}\n")
    message(STATUS "generate_main_cpp: wrote ${_out_src}")
endfunction()
