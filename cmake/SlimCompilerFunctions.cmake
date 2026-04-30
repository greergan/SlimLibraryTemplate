function(set_compiler_flags)
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
        list(APPEND SLIM_CXX_FLAGS
            -Wall
            -Wextra
            -Wpedantic
            -Wshadow
            -Wconversion
            -Wsign-conversion
        )
        if(CMAKE_BUILD_TYPE STREQUAL "RELEASE")
            list(APPEND SLIM_CXX_FLAGS -O2 -DNDEBUG)
        elseif(CMAKE_BUILD_TYPE STREQUAL "COMPACT")
            list(APPEND SLIM_CXX_FLAGS -O3)
        elseif(CMAKE_BUILD_TYPE STREQUAL "DEBUG")
            list(APPEND SLIM_CXX_FLAGS -g -O0)
        endif()
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        list(APPEND SLIM_CXX_FLAGS
            /W4
            /WX-
            /permissive-
        )
        if(CMAKE_BUILD_TYPE STREQUAL "RELEASE")
            list(APPEND SLIM_CXX_FLAGS /O2 /DNDEBUG)
        elseif(CMAKE_BUILD_TYPE STREQUAL "COMPACT")
            list(APPEND SLIM_CXX_FLAGS /O1 /DNDEBUG)
        elseif(CMAKE_BUILD_TYPE STREQUAL "DEBUG")
            list(APPEND SLIM_CXX_FLAGS /Od /Zi)
        endif()
    else()
        message(WARNING "Unknown compiler '${CMAKE_CXX_COMPILER_ID}' — no flags set")
    endif()
    list(APPEND SLIM_CXX_FLAGS ${SLIM_CXX_STANDARD})
endfunction()