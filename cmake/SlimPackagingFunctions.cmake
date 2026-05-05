# ---------------------------------------------------------------------------
# make_install_artifacts()
# Installs headers, export targets, CMake config/version files, and the
# pkg-config metadata file derived from the primary module's metadata.
# For header-only modules only the generated .hpp is installed.
# ---------------------------------------------------------------------------
function(make_install_artifacts)
    get_primary_module(_module_name)
    if(NOT _module_name)
        message(FATAL_ERROR "make_install_artifacts: no primary module defined")
    endif()

    meta_get(MODULE "${_module_name}" description       _description)
    meta_get(MODULE "${_module_name}" git_tag           _version)
    meta_get(MODULE "${_module_name}" git_repo          _git_repo)
    meta_get(MODULE "${_module_name}" hpp_only          _hpp_only)
    meta_get(MODULE "${_module_name}" lower             _library_name)
    meta_get(MODULE "${_module_name}" metadata_file_in  _metadata_file_in)
    meta_get(MODULE "${_module_name}" metadata_file_out _metadata_file_out)

    # --- Headers (primary + all sub-modules) --------------------------------
    # Stage configured headers under a dedicated subdirectory so they are
    # isolated from other generated files in the binary directory.
    set(_hdr_staging "${CMAKE_CURRENT_BINARY_DIR}/include_staging")

    foreach(_name IN LISTS MODULE_NAMES)
        meta_get(MODULE "${_name}" header_file_in  _hdr_in)
        meta_get(MODULE "${_name}" header_file_out _hdr_out)
        meta_get(MODULE "${_name}" git_tag         _git_tag)
        meta_get(MODULE "${_name}" git_hash        _git_hash)
        meta_get(MODULE "${_name}" upper           _module)
        meta_get(MODULE "${_name}" src_dir         _src_dir)

        if(NOT _hdr_in)
            message(FATAL_ERROR "make_install_artifacts: no header_file_in defined for '${_name}'")
        endif()

        # For sub-modules, header_file_in is relative to their own src_dir.
        # For the primary module, fall back to CMAKE_SOURCE_DIR.
        if(_src_dir)
            set(_hdr_in_path "${_src_dir}/${_hdr_in}")
        else()
            set(_hdr_in_path "${CMAKE_SOURCE_DIR}/${_hdr_in}")
        endif()

        if(NOT EXISTS "${_hdr_in_path}")
            message(FATAL_ERROR "make_install_artifacts: header_file_in not found: '${_hdr_in_path}'")
        endif()

        # Variables substituted into the header template:
        #   @SLIMFOO_VERSION@  and  @SLIMFOO_GIT_HASH@
        set(${_module}_VERSION  "${_git_tag}")
        set(${_module}_GIT_HASH "${_git_hash}")

        message(STATUS "make_install_artifacts: ${_module}_VERSION  = ${${_module}_VERSION}")
        message(STATUS "make_install_artifacts: ${_module}_GIT_HASH = ${${_module}_GIT_HASH}")

        configure_file(
            "${_hdr_in_path}"
            "${_hdr_staging}/${_hdr_out}"
        )

        # _hdr_out is e.g. "include/slim/SlimFoo.hpp" or
        # "include/slim/common/bar/baz.h".  Strip the leading "include/" segment
        # so the final installed path is:
        #   <prefix>/<CMAKE_INSTALL_INCLUDEDIR>/slim/SlimFoo.hpp
        cmake_path(GET _hdr_out PARENT_PATH _hdr_install_subdir)
        string(REGEX REPLACE "^include/" "" _hdr_install_subdir "${_hdr_install_subdir}")

        install(
            FILES "${_hdr_staging}/${_hdr_out}"
            DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/${_hdr_install_subdir}"
        )

        message(STATUS "make_install_artifacts: header configured for '${_name}'")
    endforeach()

    # --- pkg-config metadata ----------------------------------------------
    # @ONLY is required: the .pc template intentionally contains pkg-config
    # variable references like ${includedir} and ${libdir} that must survive
    # to the installed file for pkg-config to expand at query time.
    # Without @ONLY, configure_file would blank every ${VAR} it cannot resolve.
    #
    configure_file(
        "${_metadata_file_in}"
        "${CMAKE_CURRENT_BINARY_DIR}/${_metadata_file_out}"
        @ONLY
    )

    install(
        FILES "${CMAKE_CURRENT_BINARY_DIR}/${_metadata_file_out}"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig"
    )

    message(STATUS "make_install_artifacts: configured for '${_module_name}'")
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
        COMMAND "${CMAKE_CTEST_COMMAND}" --output-on-failure
        COMMAND "${CMAKE_CPACK_COMMAND}"
                --config  "${CMAKE_BINARY_DIR}/CPackConfig.cmake"
                -B        "${_dist_dir}"
        WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
        COMMENT "Running tests then building DEB and RPM packages into ${_dist_dir}"
        VERBATIM
    )

    if(TARGET ${_lower}_catch2_tests)
        add_dependencies(dist ${_lower}_catch2_tests)
    endif()

    if(TARGET ${_lower}_test_shared)
        add_dependencies(dist ${_lower}_test_shared)
    endif()

    if(TARGET ${_lower}_test_static)
        add_dependencies(dist ${_lower}_test_static)
    endif()

    if(TARGET ${_lower}_shared)
        add_dependencies(dist ${_lower}_shared)
    endif()

    if(TARGET ${_lower}_static)
        add_dependencies(dist ${_lower}_static)
    endif()

    message(STATUS "make_packages: 'dist' target will write packages to '${_dist_dir}'")
    message(STATUS "make_packages: call include(CPack) at directory scope immediately after this function")
endfunction()