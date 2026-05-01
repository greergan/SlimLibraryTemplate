# ---------------------------------------------------------------------------
# make_install_artifacts()
# Installs headers, export targets, CMake config/version files, and the
# pkg-config metadata file derived from the primary module's metadata.
# For header-only modules only the generated .hpp is installed.
# ---------------------------------------------------------------------------
function(make_install_artifacts)
    get_primary_module(_primary)
    if(NOT _primary)
        message(FATAL_ERROR "make_install_artifacts: no primary module defined")
    endif()

    include(CMakePackageConfigHelpers)

    meta_get(MODULE "${_primary}" header_file_in    _hdr_in)
    meta_get(MODULE "${_primary}" header_file_out   _hdr_out)
    meta_get(MODULE "${_primary}" src_dir           _src_dir)
    meta_get(MODULE "${_primary}" metadata_file_in  _metadata_file_in)
    meta_get(MODULE "${_primary}" metadata_file_out _metadata_file_out)

    # --- Header -----------------------------------------------------------
    if(NOT _hdr_in)
        message(FATAL_ERROR "make_install_artifacts: no header_file_in defined for '${_primary}'")
    endif()

    configure_file(
        "${CMAKE_SOURCE_DIR}/${_hdr_in}"
        "${CMAKE_CURRENT_BINARY_DIR}/${_hdr_out}"
        @ONLY
    )

    # --- pkg-config metadata ----------------------------------------------
    configure_file(
        "${_metadata_file_in}"
        "${CMAKE_CURRENT_BINARY_DIR}/${_metadata_file_out}"
        @ONLY
    )

    message(STATUS "make_install_artifacts: configured for '${_primary}'")
endfunction()

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
    meta_get(MODULE "${_primary}" dist_dir    _dist_dir)

    if(NOT _dist_dir)
        message(FATAL_ERROR "make_packages: no dist_dir defined for '${_primary}'")
    endif()

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

endfunction()