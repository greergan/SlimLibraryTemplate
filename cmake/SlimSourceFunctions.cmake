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
 
        string(REGEX REPLACE "^include/" "" _hdr_rel "${_hdr}")
        list(APPEND _includes "#include <${_hdr_rel}>")
    endforeach()
 
    if(NOT _includes)
        message(WARNING "generate_main_cpp: no sub-module headers found, aborting")
        return()
    endif()
 
    list(JOIN _includes "\n" _includes_block)
    set(_out_src "${_src_dir}/src/main.cpp")
    file(WRITE "${_out_src}" "${_includes_block}\n")
    message(STATUS "generate_main_cpp: wrote ${_out_src}")

    # --- Git commit the generated file ------------------------------------
    find_program(_GIT_EXEC git)
    if(NOT _GIT_EXEC)
        message(WARNING "generate_main_cpp: git not found, skipping auto-commit")
        return()
    endif()

    execute_process(
        COMMAND "${_GIT_EXEC}" -C "${_src_dir}" add src/main.cpp
        RESULT_VARIABLE _git_add_result
        ERROR_VARIABLE  _git_add_error
    )
    if(NOT _git_add_result EQUAL 0)
        message(WARNING "generate_main_cpp: git add failed\n${_git_add_error}")
        return()
    endif()

    execute_process(
        COMMAND "${_GIT_EXEC}" -C "${_src_dir}" diff --cached --quiet
        RESULT_VARIABLE _git_diff_result
    )
    if(_git_diff_result EQUAL 0)
        message(STATUS "generate_main_cpp: src/main.cpp unchanged, nothing to commit")
        return()
    endif()

    execute_process(
        COMMAND "${_GIT_EXEC}" -C "${_src_dir}" commit -m "automated: regenerate src/main.cpp"
        RESULT_VARIABLE _git_commit_result
        ERROR_VARIABLE  _git_commit_error
    )
    if(NOT _git_commit_result EQUAL 0)
        message(WARNING "generate_main_cpp: git commit failed\n${_git_commit_error}")
    else()
        message(STATUS "generate_main_cpp: committed src/main.cpp")
    endif()
endfunction()