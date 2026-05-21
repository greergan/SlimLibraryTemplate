# Slim Build System

A CMake-based build framework for C++ libraries targeting Linux. Handles module discovery, source fetching, header generation, shared/static compilation, Catch2 testing, and DEB/RPM packaging — all driven from a consistent naming convention and a small `required_packages` file.

---

## Table of Contents

- [Overview](#overview)
- [Module Naming Conventions](#module-naming-conventions)
- [Directory Structure](#directory-structure)
- [Build Variables](#build-variables)
- [Quick Start](#quick-start)
- [Make Targets](#make-targets)
- [Required Packages](#required-packages)
- [Module Metadata System](#module-metadata-system)
- [Testing](#testing)
- [Packaging](#packaging)
- [Docker Dev Environment](#docker-dev-environment)
- [CMake Function Reference](#cmake-function-reference)

---

## Overview

The Slim build system derives everything it needs from a few conventions:

- The **project name** is taken from the source directory name (`cmake_path(GET CMAKE_SOURCE_DIR FILENAME ...)`).
- **Dependencies** are declared in a `required_packages` file at the repo root.
- **Module type** is inferred from the name prefix (`SlimCommon`, `Slim<Lib>`, `SlimCommon<Lib><Sub>`).
- **Git tags and hashes** are resolved automatically at configure time from GitHub.
- **Headers** are generated from `.h.in` / `.hpp.in` templates with version metadata substituted in.

Two source modes are supported, selected via `-DSLIM_USE_LOCAL_SOURCE`:

| Mode | `SLIM_USE_LOCAL_SOURCE` | Behaviour |
|------|------------------------|-----------|
| Local | `ON` (default) | Uses `CMAKE_SOURCE_DIR`; marks version as `0.0.0` |
| Remote | `OFF` | Fetches the latest tagged release via `FetchContent` |

---

## Module Naming Conventions

All module names must start with `Slim`. The suffix determines the module type:

| Name pattern | Type | Example |
|---|---|---|
| `SlimCommon` | Aggregate library — includes all sub-modules | `SlimCommon` |
| `Slim<Word>` | Header-only library | `SlimValue` |
| `SlimCommon<Lib>` | Sub-module (one word after `SlimCommon`) | `SlimCommonLog` |
| `SlimCommon<Lib><Sub>` | Sub-module with nested header path | `SlimCommonHttpUrl` |

Names that don't match one of these patterns are rejected at configure time with a `FATAL_ERROR`.

---

## Directory Structure

```
<project>/
├── cmake/
│   ├── SlimFunctions.cmake          # Top-level include aggregator
│   ├── SlimCompilerFunctions.cmake  # set_compiler_flags()
│   ├── SlimGitFunctions.cmake       # Git tag/hash resolution
│   ├── SlimLoadRequiredPackages.cmake
│   ├── SlimMetaFunctions.cmake      # meta_set / meta_get / _propagate_module
│   ├── SlimModuleFunctions.cmake    # define_module() and friends
│   ├── SlimPackagingFunctions.cmake # make_install_artifacts(), make_packages()
│   ├── SlimSourceFunctions.cmake    # generate_main_cpp()
│   ├── SlimTargetFunctions.cmake    # compile_targets(), test_targets(), test_catch2_targets()
│   ├── slim_common_lib.pc.in        # pkg-config template (compiled library)
│   └── slim_header_lib.pc.in        # pkg-config template (header-only library)
├── docker/
│   ├── Dockerfile
│   ├── devcontainer.json
│   └── README.md
├── include/
│   └── slim/
│       └── ...                      # Generated / hand-written headers
├── src/
│   ├── main.cpp                     # Auto-generated for SlimCommon
│   └── test.cpp                     # Optional manual test driver
├── tests/
│   └── *.cpp                        # Catch2 test sources
├── required_packages                # Dependency list (see below)
├── CMakeLists.txt
└── Makefile
```

---

## Build Variables

| Variable | Default | Description |
|---|---|---|
| `SLIM_USE_LOCAL_SOURCE` | `ON` | Build from the local source tree; `OFF` fetches the latest release tag |
| `SLIM_SHARED_ONLY` | `ON` | Build only a shared library; `OFF` also builds a static archive |
| `CMAKE_BUILD_TYPE` | `DEBUG` | `DEBUG`, `RELEASE`, or `COMPACT` |
| `CMAKE_INSTALL_PREFIX` | `/usr` | Install root (overridden to `/usr` during packaging) |

---

## Quick Start

```bash
# Configure and build (local source, debug, shared only)
make

# Configure with custom options
make configure RELEASE_TYPE=RELEASE SHARED_ONLY=OFF LOCAL_SRC=OFF

# Build
make build

# Run tests
cd build && ctest --output-on-failure

# Build and install DEB (Debian/Ubuntu)
make install

# Build and install DEB from local source
make local
```

---

## Make Targets

| Target | Description |
|---|---|
| `all` / `build` | Configure then compile |
| `configure` | Run CMake configure step only |
| `install` | Build a release package and install it via `dpkg` or `rpm` |
| `local` | Build a `0.0.0` local package and install it |
| `deb` | Build a `.deb` package into `dist/` |
| `rpm` | Build an `.rpm` package into `dist/` |
| `packages` | Build both `.deb` and `.rpm` |
| `clean` | Remove `build/`, `*.deb`, and `*.rpm` |

---

## Required Packages

Declare dependencies in a `required_packages` file at the project root. Each non-blank, non-comment line specifies a package name and optional version bounds:
These dependencies are used to include Submodules as part of the SlimCommon library build.

```
# format: <ModuleName> [min_version] [max_version]
SlimCommonLog
SlimValue 0.0.0  2.9.9
```

Each listed name must follow the [module naming conventions](#module-naming-conventions). At configure time the system resolves the package via `pkg-config` (for installed libraries) or `FetchContent` (for remote Slim modules).

---

## Module Metadata System

All module state is stored in CMake variables using a structured key-value approach provided by `SlimMetaFunctions.cmake`.

```cmake
meta_set(MODULE "SlimFoo" git_tag "1.2.3")
meta_get(MODULE "SlimFoo" git_tag GIT_TAG)   # → GIT_TAG = "1.2.3"
```

Because CMake functions create a new variable scope, call `_propagate_module(<NAME>)` (a macro) after any batch of `meta_set` calls to surface the data to the calling scope.

Fields written per module:

`primary`, `upper`, `lower`, `description`, `git_tag`, `git_hash`, `git_repo`, `git_repo_found`, `git_latest_tag`, `hpp_only`, `min_version`, `max_version`, `found_version`, `header_prefix`, `header_file_in`, `header_file_out`, `include_dir`, `metadata_file_in`, `metadata_file_out`, `pkg_CFLAGS`, `pkg_LDFLAGS`, `pkg_LIBRARIES`, `pkg_INCLUDE_DIRS`, `pkg_LIBRARY_DIRS`, `using_local_src`, `src_dir`, `dist_dir`

---

## Testing

### Catch2 tests (`tests/`)

Place any number of `.cpp` files under `tests/`. The `test_catch2_targets()` function globs them all, links against Catch2 v3 (must be installed), and registers every `TEST_CASE` with CTest via `catch_discover_tests`. The suite also runs automatically as a `POST_BUILD` step.

```bash
# Run via CTest
cd build && ctest --output-on-failure

# Or run the binary directly
./build/<libname>_catch2_tests
```

### Manual test driver (`src/test.cpp`)

An optional `src/test.cpp` is compiled into `<libname>_test_shared` (and `_test_static` when `SLIM_SHARED_ONLY=OFF`). This is useful for quick smoke tests outside of the Catch2 harness.

---

## Packaging

Packages are generated by CPack and placed in `dist/` (one directory above the build tree).

```bash
# Both formats at once
make packages

# Individual formats
make deb
make rpm
```

The file name follows the pattern `<libname>-<version>-<arch>.(deb|rpm)`. When `SLIM_USE_LOCAL_SOURCE=ON` the version is always `0.0.0`; a remote build uses the latest Git tag resolved at configure time.

> **Note:** `include(CPack)` must appear at directory scope in `CMakeLists.txt`, after `make_packages()` returns. Calling it inside a CMake function causes `CPACK_GENERATOR` and `CPACK_OUTPUT_FILE_PREFIX` to be lost.

---

## Docker Dev Environment

A ready-to-use Ubuntu-based toolchain image is provided under `docker/`.

```bash
# Build the image
docker build -t slim-toolchain docker/

# Run interactively with your workspace mounted
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -w /workspace \
  slim-toolchain
```

The image ships with: `build-essential`, `cmake`, `ninja-build`, `catch2`, `curl`, `git`, `libtool`, `pkg-config`, `python3`, `pipx`, and `rpm`.

### VS Code Dev Container

Open the project in VS Code and select **Dev Containers: Reopen in Container**. The `docker/devcontainer.json` configuration mounts the workspace, sets the timezone, and installs the CMake Tools extension automatically.

---

## CMake Function Reference

| Function | File | Description |
|---|---|---|
| `set_compiler_flags()` | `SlimCompilerFunctions` | Populates `SLIM_CXX_FLAGS` for GCC/Clang/MSVC |
| `define_module([name] ...)` | `SlimModuleFunctions` | Registers a module and runs all derivation steps |
| `get_primary_module(OUT)` | `SlimModuleFunctions` | Returns the name of the primary module |
| `apply_module_flags(TARGET)` | `SlimModuleFunctions` | Applies pkg-config flags from all non-primary modules |
| `generate_main_cpp()` | `SlimSourceFunctions` | Generates `src/main.cpp`  and `include/slim/common.h` when building the `SlimCommon` library|
| `compile_targets()` | `SlimTargetFunctions` | Creates shared (and optionally static) library targets |
| `test_targets()` | `SlimTargetFunctions` | Compiles `src/test.cpp` against the built libraries |
| `test_catch2_targets()` | `SlimTargetFunctions` | Globs `tests/*.cpp` and wires up Catch2 + CTest |
| `make_install_artifacts()` | `SlimPackagingFunctions` | Installs headers, `.pc` file, and export targets |
| `make_packages()` | `SlimPackagingFunctions` | Sets all `CPACK_*` vars and registers the `dist` target |
| `dump_target_properties(TARGET)` | `SlimTargetFunctions` | Prints common target properties to STATUS output |
| `meta_set(PREFIX NAME KEY VAL)` | `SlimMetaFunctions` | Stores a key-value pair for a named module |
| `meta_get(PREFIX NAME KEY OUT)` | `SlimMetaFunctions` | Retrieves a stored value into `OUT` |
