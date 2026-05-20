# Docker Dev Environment

Provides a containerized Ubuntu build environment for compiling and packaging Slim libraries. Produces both Debian (`.deb`) and Red Hat (`.rpm`) packages from a single consistent toolchain.

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Visual Studio Code](https://code.visualstudio.com/) *(optional, for Dev Container)*
- [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) *(optional)*

---

## Toolchain

The image is based on `ubuntu:26.04` and includes:

| Tool | Purpose |
|---|---|
| `build-essential` | GCC, make, and core build utilities |
| `cmake` | Build system generator |
| `ninja-build` | Fast build backend |
| `catch2` | C++ unit testing framework |
| `curl` | Git repo reachability checks at configure time |
| `git` | Source fetching and tag resolution |
| `libtool` / `libtool-bin` | Shared library tooling |
| `openssh-client` | SSH-based Git access |
| `pkg-config` | Dependency discovery for installed libraries |
| `python3` / `pipx` | Runtime for pre-commit and tooling |
| `rpm` | RPM package creation |
| `pre-commit` | Git hook manager (installed globally via pipx) |

---

## Build the Image

From the repository root:

```bash
docker build -t slim-toolchain docker/
```

Or from inside the `docker/` directory:

```bash
docker build -t slim-toolchain .
```

---

## Run the Container

Mount your workspace and drop into a shell:

```bash
docker run --rm -it \
  -v "$(pwd):/workspace" \
  -w /workspace \
  slim-toolchain
```

From there, all standard `make` targets are available:

```bash
make build
make deb
make rpm
make packages
```

---

## VS Code Dev Container

A `devcontainer.json` is included for a one-click development environment in VS Code.

### Setup

1. Install the **Dev Containers** extension in VS Code.
2. Open the repository root folder.
3. When prompted, choose **Reopen in Container** — or open the Command Palette and run:
   ```
   Dev Containers: Reopen in Container
   ```

The container will build from the local `Dockerfile`, mount your workspace at `/workspace`, and install the extensions and settings below automatically.

### Container Details

| Setting | Value |
|---|---|
| Container name | `slim-toolchain-container` |
| Workspace mount | `<localWorkspaceFolder>` → `/workspace` |
| Timezone | `America/Los_Angeles` |
| Git editor | VS Code (`code --wait`) |

### Installed Extensions

| Extension | Purpose |
|---|---|
| `GridFlowTech.document-tabs` | Tab management |
| `ms-vscode.cmake-tools` | CMake configure, build, and debug integration |

### Editor Settings

| Setting | Value |
|---|---|
| Indentation | Tabs (not spaces) |
| Tab size | 4 |
| C++ standard | C++23 |
| Minimap | Disabled |
| Mouse wheel zoom | Enabled |
| Hover delay | 1000 ms |
| Tab completion | On |
| Auto-closing tags | Enabled (HTML, JS, TS) |

The Code Runner extension is configured to run `make install` from the workspace folder when executing a `.cpp` file directly.
