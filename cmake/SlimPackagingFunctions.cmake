# ---------------------------------------------------------------------------
# make_packages()
# Configures CPack and creates a 'dist' custom target that produces DEB and
# RPM packages. All CPack variables follow the logic from RunPackager.cmake.
# Requires install_targets() to have been called first.
# ---------------------------------------------------------------------------
function(make_packages)
    get_primary_module(_primary)
    if(NOT _primary)
        message(FATAL_ERROR "make_packages: no primary module defined")
    endif()
 
    meta_get(MODULE "${_primary}" lower       _lower)
    meta_get(MODULE "${_primary}" git_tag     _version)
    meta_get(MODULE "${_primary}" upper       _upper)
 
    # --- Architecture ---------------------------------------------------------
    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _arch)
    if(_arch MATCHES "x86_64|amd64")
        set(_arch_name "amd64")
    elseif(_arch MATCHES "i386|i686")
        set(_arch_name "x86")
    elseif(_arch MATCHES "aarch64|arm64")
        set(_arch_name "arm64")
    elseif(_arch MATCHES "armv7|arm")
        set(_arch_name "arm")
    else()
        set(_arch_name "unknown")
    endif()
 
    # --- Align install prefix with CPack packaging prefix -----------------
    set(CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "" FORCE)
 
    # --- CPack common -----------------------------------------------------
    set(CPACK_GENERATOR "DEB;RPM")
    set(CPACK_PACKAGE_NAME              ${_lower})
    set(CPACK_PACKAGE_VERSION           ${_version})
    set(CPACK_PACKAGE_CONTACT           "${GIT_USER_NAME} <${GIT_USER_EMAIL}>")
    set(CPACK_PACKAGE_FILE_NAME         "${_lower}-${_version}-${_arch_name}")
    set(CPACK_PACKAGING_INSTALL_PREFIX  "/usr")
 
    # --- DEB --------------------------------------------------------------
    set(CPACK_DEBIAN_PACKAGE_MAINTAINER  ${GIT_USER_NAME})
    set(CPACK_DEBIAN_PACKAGE_SECTION     "devel")
    set(CPACK_DEBIAN_PACKAGE_PRIORITY    "optional")
    set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE ${_arch_name})
 
    # --- RPM --------------------------------------------------------------
    set(CPACK_RPM_PACKAGE_NAME         ${_lower})
    set(CPACK_RPM_PACKAGE_VERSION      ${_version})
    set(CPACK_RPM_PACKAGE_RELEASE      "1")
    set(CPACK_RPM_PACKAGE_LICENSE      "MIT")
    set(CPACK_RPM_PACKAGE_GROUP        "Development/Libraries")
    set(CPACK_RPM_PACKAGE_ARCHITECTURE ${_arch_name})
    set(CPACK_RPM_PACKAGE_PREFIX       ${CMAKE_INSTALL_PREFIX})
 
    meta_get(MODULE "${_primary}" description _description)
    if(_description)
        set(CPACK_RPM_PACKAGE_SUMMARY ${_description})
    endif()
 
    include(CPack)
 
    add_custom_target(dist
        COMMAND ${CMAKE_CPACK_COMMAND} --config "${CMAKE_BINARY_DIR}/CPackConfig.cmake"
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Building distribution packages for '${_lower}'"
        VERBATIM
    )
 
    message(STATUS "make_packages: added target 'dist'")
endfunction()