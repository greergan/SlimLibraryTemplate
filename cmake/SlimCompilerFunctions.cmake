function(set_compiler_flags)
    set(flags "")

    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
        list(APPEND flags
            -Wall
            -Wextra
            -Wpedantic
            -Wshadow
            -Wconversion
            -Wsign-conversion
        )
        if(CMAKE_BUILD_TYPE STREQUAL "RELEASE")
            list(APPEND flags -O2 -DNDEBUG)
        elseif(CMAKE_BUILD_TYPE STREQUAL "COMPACT")
            list(APPEND flags -O3)
        elseif(CMAKE_BUILD_TYPE STREQUAL "DEBUG")
            list(APPEND flags -g -O0)
        endif()

    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        list(APPEND flags
            /W4
            /WX-
            /permissive-
        )
        if(CMAKE_BUILD_TYPE STREQUAL "RELEASE")
            list(APPEND flags /O2 /DNDEBUG)
        elseif(CMAKE_BUILD_TYPE STREQUAL "COMPACT")
            list(APPEND flags /O1 /DNDEBUG)
        elseif(CMAKE_BUILD_TYPE STREQUAL "DEBUG")
            list(APPEND flags /Od /Zi)
        endif()

    else()
        message(WARNING "Unknown compiler '${CMAKE_CXX_COMPILER_ID}' — no flags set")
    endif()

    list(APPEND flags ${DEFAULT_CXX_FLAG})
    set(SLIM_CXX_FLAGS "${flags}" PARENT_SCOPE)  # propagate to caller
endfunction()