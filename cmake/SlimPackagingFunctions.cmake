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

    meta_get(MODULE "${_primary}" upper             _upper)
    meta_get(MODULE "${_primary}" lower             _lower)
    meta_get(MODULE "${_primary}" git_tag           _version)
    meta_get(MODULE "${_primary}" hpp_only          _hpp_only)
    meta_get(MODULE "${_primary}" header_file_in    _hdr_in)
    meta_get(MODULE "${_primary}" header_file_out   _hdr_out)
    meta_get(MODULE "${_primary}" include_dir       _inc_dir)
    meta_get(MODULE "${_primary}" src_dir           _src_dir)
    meta_get(MODULE "${_primary}" metadata_file_in  _metadata_file_in)
    meta_get(MODULE "${_primary}" metadata_file_out _metadata_file_out)

    set(_dist_dir "${CMAKE_CURRENT_BINARY_DIR}/dist")

    # --- Derive install sub-directory from include_dir --------------------
    string(REGEX REPLACE "^include/" "" _install_dir "${_inc_dir}")

    # --- Header -----------------------------------------------------------
    if(NOT _hdr_in)
        message(FATAL_ERROR "make_install_artifacts: no header_file_in defined for '${_primary}'")
    endif()

    configure_file(
        "${_src_dir}/${_hdr_in}"
        "${_dist_dir}/${_hdr_out}"
        @ONLY
    )
    install(FILES "${_dist_dir}/${_hdr_out}"
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${_install_dir}
    )

    # --- Export targets + CMake config files (compiled modules only) ------
    if(NOT _hpp_only)
        install(EXPORT ${_upper}Targets
            FILE        ${_upper}Targets.cmake
            NAMESPACE   Slim::
            DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/${_upper}
        )

        write_basic_package_version_file(
            "${_dist_dir}/${_upper}ConfigVersion.cmake"
            VERSION       ${_version}
            COMPATIBILITY AnyNewerVersion
        )

        file(WRITE "${_dist_dir}/${_upper}Config.cmake"
            "include(\"\${CMAKE_CURRENT_LIST_DIR}/${_upper}Targets.cmake\")\n"
        )

        install(FILES
            "${_dist_dir}/${_upper}Config.cmake"
            "${_dist_dir}/${_upper}ConfigVersion.cmake"
            DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/${_upper}
        )
    endif()

    # --- pkg-config metadata ----------------------------------------------
    configure_file(
        "${_src_dir}/${_metadata_file_in}"
        "${_dist_dir}/${_metadata_file_out}"
        @ONLY
    )

    install(FILES
        "${_dist_dir}/${_metadata_file_out}"
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig
    )

    message(STATUS "make_install_artifacts: configured for '${_upper}'")
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
        COMMAND ${CMAKE_COMMAND} --install "${CMAKE_BINARY_DIR}" --prefix "${CMAKE_CURRENT_BINARY_DIR}/dist"
        COMMAND ${CMAKE_CPACK_COMMAND} --config "${CMAKE_BINARY_DIR}/CPackConfig.cmake"
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Installing and building distribution packages for '${_lower}'"
        VERBATIM
    )

    message(STATUS "make_packages: added target 'dist'")
endfunction()