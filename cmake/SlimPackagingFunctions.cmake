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

    meta_get(MODULE "${_primary}" header_file_in    _hdr_in)
    meta_get(MODULE "${_primary}" header_file_out   _hdr_out)
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

    # _hdr_out is e.g. "include/slim/SlimFoo.hpp" or
    # "include/slim/common/bar/baz.h".  Strip the leading "include/" segment
    # so the final installed path is:
    #   <prefix>/<CMAKE_INSTALL_INCLUDEDIR>/slim/SlimFoo.hpp
    cmake_path(GET _hdr_out PARENT_PATH _hdr_install_subdir)
    string(REGEX REPLACE "^include/" "" _hdr_install_subdir "${_hdr_install_subdir}")

    install(
        FILES "${CMAKE_CURRENT_BINARY_DIR}/${_hdr_out}"
        DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/${_hdr_install_subdir}"
    )

    # --- pkg-config metadata ----------------------------------------------
    configure_file(
        "${_metadata_file_in}"
        "${CMAKE_CURRENT_BINARY_DIR}/${_metadata_file_out}"
        @ONLY
    )

    install(
        FILES "${CMAKE_CURRENT_BINARY_DIR}/${_metadata_file_out}"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig"
    )

    message(STATUS "make_install_artifacts: configured for '${_primary}'")
endfunction()

# ---------------------------------------------------------------------------
# make_packages()
# Prepares all CPACK_* variables and propagates them to the calling directory
# scope. The caller (CMakeLists.txt) MUST call include(CPack) immediately
# after this function returns — include(CPack) must run at directory scope
# or CPACK_GENERATOR and CPACK_OUTPUT_FILE_PREFIX will not be captured
# correctly in the generated CPackConfig.cmake.
#
# Also registers a 'dist' custom target that invokes cpack to produce
# .deb / .rpm packages in the module's dist_dir.
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
    meta_get(MODULE "${_primary}" description _description)

    if(NOT _dist_dir)
        message(FATAL_ERROR "make_packages: no dist_dir defined for '${_primary}'")
    endif()

    file(MAKE_DIRECTORY "${_dist_dir}")

    # --- Architecture -----------------------------------------------------
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

    # Forces /usr so installed paths inside the package are correct.
    set(CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "" FORCE)

    # -----------------------------------------------------------------------
    # Propagate every CPACK_* variable to the parent (directory) scope.
    # include(CPack) must be called at directory scope by CMakeLists.txt
    # immediately after this function returns — variables set inside a
    # function() are invisible to include(CPack) if called here.
    # -----------------------------------------------------------------------
    set(CPACK_GENERATOR                  "DEB;RPM"                                              PARENT_SCOPE)
    set(CPACK_PACKAGE_NAME               "${_lower}"                                            PARENT_SCOPE)
    set(CPACK_PACKAGE_VERSION            "${_version}"                                          PARENT_SCOPE)
    set(CPACK_PACKAGE_CONTACT            "${GIT_USER_NAME} <${GIT_USER_EMAIL}>"                 PARENT_SCOPE)
    set(CPACK_PACKAGE_FILE_NAME          "${_lower}-${_version}-${_arch_name}"                  PARENT_SCOPE)
    set(CPACK_PACKAGING_INSTALL_PREFIX   "/usr"                                                 PARENT_SCOPE)
    set(CPACK_OUTPUT_FILE_PREFIX         "${_dist_dir}"                                         PARENT_SCOPE)
    set(CPACK_INSTALL_CMAKE_PROJECTS     "${CMAKE_BINARY_DIR};${PROJECT_NAME};ALL;/"            PARENT_SCOPE)

    set(CPACK_DEBIAN_PACKAGE_MAINTAINER  "${GIT_USER_NAME}"                                    PARENT_SCOPE)
    set(CPACK_DEBIAN_PACKAGE_SECTION     "devel"                                                PARENT_SCOPE)
    set(CPACK_DEBIAN_PACKAGE_PRIORITY    "optional"                                             PARENT_SCOPE)
    set(CPACK_DEBIAN_PACKAGE_ARCHITECTURE "${_arch_name}"                                       PARENT_SCOPE)
    set(CPACK_DEBIAN_PACKAGE_DESCRIPTION "${_description}"                                      PARENT_SCOPE)

    set(CPACK_RPM_PACKAGE_NAME           "${_lower}"                                            PARENT_SCOPE)
    set(CPACK_RPM_PACKAGE_VERSION        "${_version}"                                          PARENT_SCOPE)
    set(CPACK_RPM_PACKAGE_RELEASE        "1"                                                    PARENT_SCOPE)
    set(CPACK_RPM_PACKAGE_LICENSE        "MIT"                                                  PARENT_SCOPE)
    set(CPACK_RPM_PACKAGE_GROUP          "Development/Libraries"                                PARENT_SCOPE)
    set(CPACK_RPM_PACKAGE_ARCHITECTURE   "${_arch_name}"                                        PARENT_SCOPE)
    set(CPACK_RPM_PACKAGE_PREFIX         "/usr"                                                 PARENT_SCOPE)
    set(CPACK_RPM_PACKAGE_SUMMARY        "${_description}"                                      PARENT_SCOPE)

    # --- 'dist' target ---------------------------------------------------
    # CPack re-runs cmake_install.cmake internally into its own DESTDIR
    # staging tree, then packs it.
    add_custom_target(dist
        COMMAND "${CMAKE_CPACK_COMMAND}"
                --config  "${CMAKE_BINARY_DIR}/CPackConfig.cmake"
                -B        "${_dist_dir}"
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        COMMENT "Building DEB and RPM packages into ${_dist_dir}"
        VERBATIM
    )

    if(TARGET ${_lower}_shared)
        add_dependencies(dist ${_lower}_shared)
    endif()
    if(TARGET ${_lower}_static)
        add_dependencies(dist ${_lower}_static)
    endif()

    message(STATUS "make_packages: 'dist' target will write packages to '${_dist_dir}'")
    message(STATUS "make_packages: call include(CPack) at directory scope immediately after this function")
endfunction()