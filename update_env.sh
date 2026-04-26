#!/usr/bin/env bash

REPO="greergan/SlimLibraryPackager"
BRANCH="master"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
API_BASE="https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1"
DEST_DIR="$(pwd)"
DIR_NAME="$(basename "${DEST_DIR}")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validate directory name starts with Slim
if [[ ! "${DIR_NAME}" =~ ^Slim ]]; then
    echo -e "${RED}Error: Directory '${DIR_NAME}' does not begin with 'Slim'. Aborting.${NC}"
    exit 1
fi

# Parse words after Slim using camel case splitting
AFTER_SLIM="${DIR_NAME#Slim}"
# Split CamelCase into words
WORDS=($(echo "${AFTER_SLIM}" | sed 's/\([A-Z]\)/ \1/g' | xargs -n1))
WORD_COUNT=${#WORDS[@]}

if [[ ${WORD_COUNT} -eq 1 ]]; then
    if [[ ${DIR_NAME} -ne "SlimCommon" ]]; then
        HEADER_DIR="${DEST_DIR}/include/slim"
        HEADER_FILE="${DIR_NAME}.hpp.in"
        INCLUDE_FILE="${DIR_NAME}.hpp"
    fi
elif [[ ${WORD_COUNT} -eq 2 ]]; then
    SUBDIR="$(echo "${WORDS[0]}" | tr '[:upper:]' '[:lower:]')"
    BASENAME="$(echo "${WORDS[1]}" | tr '[:upper:]' '[:lower:]')"
    HEADER_DIR="${DEST_DIR}/include/slim/${SUBDIR}"
    HEADER_FILE="${BASENAME}.h.in"
    INCLUDE_FILE="${BASENAME}.h"
elif [[ ${WORD_COUNT} -eq 3 ]]; then
    SUBDIR="$(echo "${WORDS[0]}" | tr '[:upper:]' '[:lower:]')"
    SUBDIR2="$(echo "${WORDS[1]}" | tr '[:upper:]' '[:lower:]')"
    BASENAME="$(echo "${WORDS[2]}" | tr '[:upper:]' '[:lower:]')"
    HEADER_DIR="${DEST_DIR}/include/slim/${SUBDIR}/${SUBDIR2}"
    HEADER_FILE="${BASENAME}.h.in"
    INCLUDE_FILE="${BASENAME}.h"
else
    echo -e "${RED}Error: Directory '${DIR_NAME}' has an unsupported format. Expected 'Slim' + 1, 2, or 3 words.${NC}"
    exit 1
fi

# Determine pc.in filename based on word count
if [[ ${WORD_COUNT} -eq 1 && ${DIR_NAME} -ne "SlimCommon" ]]; then
    PC_FILE="slim_header_lib.pc.in"
else
    PC_FILE="slim_common_lib.pc.in"
fi

download_file() {
    local relative_path="$1"
    local dest="${DEST_DIR}/${relative_path}"
    local dest_dir
    dest_dir="$(dirname "${dest}")"

    if [[ -e "${dest}" ]]; then
        if [[ "${SKIP_ALL}" == "true" ]]; then
            echo -e "  ${RED}Skipped:${NC} ${relative_path}"
            return
        elif [[ "${OVERWRITE_ALL}" == "true" ]]; then
            : # fall through to download
        else
            echo -en "${YELLOW}File '${relative_path}' already exists. Overwrite? [y/N]: ${NC}"
            read -r answer < /dev/tty
            if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
                echo -e "  ${YELLOW}Skipped:${NC} ${relative_path}"
                return
            fi
        fi
    fi

    mkdir -p "${dest_dir}"
    if curl -fsSL "${RAW_BASE}/${relative_path}" -o "${dest}"; then
        echo -e "  ${GREEN}Downloaded:${NC} ${relative_path}"
    else
        echo -e "  ${RED}Failed:${NC} ${relative_path}"
    fi
}

echo ""
echo "Updating Slim library environment in: ${DEST_DIR}"
echo ""

# Check if any downloadable files already exist
EXISTING_FILES=()
for f in CMakeLists.txt Makefile LICENSE "${PC_FILE}"; do
    [[ -e "${DEST_DIR}/${f}" ]] && EXISTING_FILES+=("${f}")
done

SKIP_ALL="false"
OVERWRITE_ALL="false"

if [[ ${#EXISTING_FILES[@]} -gt 0 ]]; then
    echo -en "${YELLOW}Some files already exist. Skip all existing files? [y/N]: ${NC}"
    read -r top_answer < /dev/tty
    if [[ "${top_answer}" =~ ^[Yy]$ ]]; then
        SKIP_ALL="true"
    else
        OVERWRITE_ALL="true"
    fi
    echo ""
fi

# Download top-level files
for file in CMakeLists.txt Makefile LICENSE "${PC_FILE}"; do
    download_file "${file}"
done

# Download required_packages only if not already present
if [[ ! -e "${DEST_DIR}/required_packages" ]]; then
    if curl -fsSL "${RAW_BASE}/required_packages" -o "${DEST_DIR}/required_packages"; then
        echo -e "  ${GREEN}Downloaded:${NC} required_packages"
    else
        echo -e "  ${RED}Failed:${NC} required_packages"
    fi
else
    echo -e "  ${RED}Skipped:${NC} required_packages (already exists)"
fi

# Discover and download cmake/ directory recursively via GitHub API
echo ""
echo "Fetching cmake/ directory listing from GitHub..."

api_response="$(curl -fsSL "${API_BASE}")"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Failed to reach GitHub API.${NC}"
    exit 1
fi

cmake_files="$(echo "${api_response}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('tree', []):
    if item['path'].startswith('cmake/') and item['type'] == 'blob':
        print(item['path'])
" 2>/dev/null)"

if [[ -z "${cmake_files}" ]]; then
    echo -e "${YELLOW}Warning: No files found under cmake/ in ${REPO}@${BRANCH}.${NC}"
else
    echo ""
    while IFS= read -r cmake_file; do
        download_file "${cmake_file}"
    done <<< "${cmake_files}"
fi

# Build header guard from directory name words
ALL_WORDS=("Slim" "${WORDS[@]}")
EXTENSION="${INCLUDE_FILE##*.}"
HEADER_GUARD=""
for word in "${ALL_WORDS[@]}"; do
    [[ -n "${HEADER_GUARD}" ]] && HEADER_GUARD="${HEADER_GUARD}__"
    HEADER_GUARD="${HEADER_GUARD}$(echo "${word}" | tr '[:lower:]' '[:upper:]')"
done
HEADER_GUARD="${HEADER_GUARD}__$(echo "${EXTENSION}" | tr '[:lower:]' '[:upper:]')"
HEADER_PATH="${HEADER_DIR}/${HEADER_FILE}"

if [[ ${DIR_NAME} -ne "SlimCommon" ]]; then
    if [[ ${WORD_COUNT} -eq 1 ]]; then
        INCLUDE_PATH="slim/${INCLUDE_FILE}"
    elif [[ ${WORD_COUNT} -eq 2 ]]; then
        INCLUDE_PATH="slim/${SUBDIR}/${INCLUDE_FILE}"
    elif [[ ${WORD_COUNT} -eq 3 ]]; then
        INCLUDE_PATH="slim/${SUBDIR}/${SUBDIR2}/${INCLUDE_FILE}"
    fi
fi

# Create include/slim header file
echo ""
if [[ -n "${INCLUDE_PATH}" ]]; then
    if [[ ! -d "${HEADER_DIR}" ]]; then
        mkdir -p "${HEADER_DIR}"
        echo -e "  ${GREEN}Created:${NC} ${HEADER_DIR#${DEST_DIR}/}/"
    else
        echo -e "  ${RED}Skipped:${NC} ${HEADER_DIR#${DEST_DIR}/}/ (already exists)"
    fi

    if [[ ! -e "${HEADER_PATH}" ]]; then
        cat > "${HEADER_PATH}" << EOF
#pragma once
#ifndef ${HEADER_GUARD}
#define ${HEADER_GUARD}

#endif // ${HEADER_GUARD}
EOF
        echo -e "  ${GREEN}Created:${NC} ${HEADER_PATH#${DEST_DIR}/}"
    else
        echo -e "  ${RED}Skipped:${NC} ${HEADER_PATH#${DEST_DIR}/} (already exists)"
    fi
fi

# ---------------------------------------------------------------------------
# Parse required_packages and derive sorted include lines
# Format per line: # PackageName [minVersion [maxVersion]]
# Only Slim* packages (excluding SlimCommon itself) generate includes.
# Non-Slim packages are skipped for now; they go in OTHER_INCLUDES if needed.
# ---------------------------------------------------------------------------
declare -a SLIM_INCLUDES=()
declare -a OTHER_INCLUDES=()

derive_slim_include() {
    local pkg_name="$1"
    local after="${pkg_name#Slim}"

    # Skip bare "Slim" or "SlimCommon"
    if [[ -z "${after}" || "${pkg_name}" == "SlimCommon" ]]; then
        return
    fi

    # Split CamelCase into words
    local pkg_words
    pkg_words=($(echo "${after}" | sed 's/\([A-Z]\)/ \1/g' | xargs -n1))
    local pkg_count=${#pkg_words[@]}

    local inc_path
    if [[ ${pkg_count} -eq 1 ]]; then
        inc_path="slim/${pkg_name}.hpp"
    elif [[ ${pkg_count} -eq 2 ]]; then
        local d1 b
        d1="$(echo "${pkg_words[0]}" | tr '[:upper:]' '[:lower:]')"
        b="$(echo "${pkg_words[1]}" | tr '[:upper:]' '[:lower:]')"
        inc_path="slim/${d1}/${b}.h"
    elif [[ ${pkg_count} -eq 3 ]]; then
        local d1 d2 b
        d1="$(echo "${pkg_words[0]}" | tr '[:upper:]' '[:lower:]')"
        d2="$(echo "${pkg_words[1]}" | tr '[:upper:]' '[:lower:]')"
        b="$(echo "${pkg_words[2]}" | tr '[:upper:]' '[:lower:]')"
        inc_path="slim/${d1}/${d2}/${b}.h"
    else
        return
    fi

    echo "#include <${inc_path}>"
}

if [[ -f "${DEST_DIR}/required_packages" ]]; then
    echo ""
    echo "Processing required_packages..."
    echo ""
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Skip blank lines and comment-only lines (e.g. the format header)
        [[ -z "${line}" || "${line}" == \#* ]] && continue

        # Extract package name (first whitespace-delimited token)
        pkg_name="${line%% *}"
        [[ -z "${pkg_name}" ]] && continue

        if [[ "${pkg_name}" == Slim* ]]; then
            inc="$(derive_slim_include "${pkg_name}")"
            if [[ -n "${inc}" ]]; then
                SLIM_INCLUDES+=("${inc}")
                echo -e "  ${GREEN}Resolved:${NC} ${pkg_name} → ${inc}"
            else
                echo -e "  ${YELLOW}Skipped:${NC} ${pkg_name} (no include derived)"
            fi
        else
            echo -e "  ${YELLOW}Skipped:${NC} ${pkg_name} (non-Slim package)"
        fi
        # Non-Slim packages: currently skipped; add to OTHER_INCLUDES here if needed
    done < "${DEST_DIR}/required_packages"
fi

# Sort each group alphabetically
IFS=$'\n' SLIM_INCLUDES=($(sort <<< "${SLIM_INCLUDES[*]}")); unset IFS
IFS=$'\n' OTHER_INCLUDES=($(sort <<< "${OTHER_INCLUDES[*]}")); unset IFS

# Build the full include block: non-Slim first, then Slim (blank line between groups)
build_include_block() {
    local block=""
    if [[ ${#OTHER_INCLUDES[@]} -gt 0 ]]; then
        for inc in "${OTHER_INCLUDES[@]}"; do
            block+="${inc}"$'\n'
        done
    fi
    if [[ ${#SLIM_INCLUDES[@]} -gt 0 ]]; then
        [[ -n "${block}" ]] && block+=$'\n'
        for inc in "${SLIM_INCLUDES[@]}"; do
            block+="${inc}"$'\n'
        done
    fi
    printf '%s' "${block}"
}

INCLUDE_BLOCK="$(build_include_block)"

# Inject includes into a TU file.
#   - Collects all existing #include lines from the file (if any)
#   - Merges them with the generated SLIM_INCLUDES and OTHER_INCLUDES
#   - Deduplicates, then sorts: non-Slim first (alphabetical), Slim second (alphabetical)
#   - Replaces the existing #include block (or prepends for new files)
inject_includes() {
    local filepath="$1"
    local is_new="$2"

    # Collect existing #include lines from the file (empty array for new files)
    local -a existing_includes=()
    if [[ "${is_new}" == "existing" ]]; then
        while IFS= read -r inc_line; do
            existing_includes+=("${inc_line}")
        done < <(grep '^#include ' "${filepath}")
    fi

    # Merge generated + existing, deduplicate
    local -a all_slim=()
    local -a all_other=()

    # Helper: classify and insert one #include line into the right bucket
    classify_include() {
        local inc="$1"
        # Slim includes match: #include <slim/...>
        if [[ "${inc}" =~ ^\#include\ \<slim/ ]]; then
            all_slim+=("${inc}")
        else
            all_other+=("${inc}")
        fi
    }

    for inc in "${OTHER_INCLUDES[@]}"; do classify_include "${inc}"; done
    for inc in "${SLIM_INCLUDES[@]}";  do classify_include "${inc}"; done
    for inc in "${existing_includes[@]}"; do classify_include "${inc}"; done

    # Deduplicate each bucket (preserve only unique entries)
    IFS=$'\n' all_slim=($(  printf '%s\n' "${all_slim[@]}"  | sort -u)); unset IFS
    IFS=$'\n' all_other=($(  printf '%s\n' "${all_other[@]}" | sort -u)); unset IFS

    # Build the merged, sorted include block
    local merged_block=""
    if [[ ${#all_other[@]} -gt 0 ]]; then
        for inc in "${all_other[@]}"; do
            merged_block+="${inc}"$'\n'
        done
    fi
    if [[ ${#all_slim[@]} -gt 0 ]]; then
        [[ -n "${merged_block}" ]] && merged_block+=$'\n'
        for inc in "${all_slim[@]}"; do
            merged_block+="${inc}"$'\n'
        done
    fi

    # Nothing to write
    if [[ -z "${merged_block}" ]]; then
        return
    fi

    if [[ "${is_new}" == "new" ]]; then
        local existing_body
        existing_body="$(cat "${filepath}")"
        printf '%s\n%s' "${merged_block}" "${existing_body}" > "${filepath}"
    else
        # Strip existing #include lines, collapse leading blank lines,
        # then prepend the merged sorted block
        local remainder
        remainder="$(grep -v '^#include ' "${filepath}" | sed '/./,$!d')"
        printf '%s\n%s\n' "${merged_block}" "${remainder}" > "${filepath}"
    fi
}

# ---------------------------------------------------------------------------
# Create src directory and TU files
# ---------------------------------------------------------------------------
echo ""
if [[ ! -d "${DEST_DIR}/src" ]]; then
    mkdir -p "${DEST_DIR}/src"
    echo -e "  ${GREEN}Created:${NC} src/"
else
    echo -e "  ${RED}Skipped:${NC} src/ (already exists)"
fi

for tu in main.cpp test.cpp; do
    tu_path="${DEST_DIR}/src/${tu}"
    if [[ ! -e "${tu_path}" ]]; then
        # Build the base content first, then inject includes
        if [[ "${tu}" == "test.cpp" ]]; then
            cat > "${tu_path}" << EOF

int main() {

    return 0;
}
EOF
        else
            # main.cpp starts empty so inject_includes prepends cleanly
            printf '\n' > "${tu_path}"
        fi
        inject_includes "${tu_path}" "new"
        echo -e "  ${GREEN}Created:${NC} src/${tu}"
    else
        inject_includes "${tu_path}" "existing"
        echo -e "  ${GREEN}Updated:${NC} src/${tu} (includes replaced)"
    fi
done

# Git repository setup
echo ""
if [[ ! -d "${DEST_DIR}/.git" ]]; then
    git -C "${DEST_DIR}" init
    echo -e "  ${GREEN}Initialized:${NC} git repository"

    # Create standard CMake .gitignore
    cat > "${DEST_DIR}/.gitignore" << EOF
# CMake
CMakeLists.txt.user
CMakeCache.txt
CMakeFiles/
CMakeScripts/
Testing/
Makefile
cmake_install.cmake
install_manifest.txt
compile_commands.json
CTestTestfile.cmake
_deps/
CMakeUserPresets.json
build*/

# IDE
.idea/
.vscode/
.vs/
.cache/
cmake-build-*/

# OS
.DS_Store

# Build artifacts
*.o
*.a
*.so
*.dylib
*.dll
*.deb
*.rpm

# Downloaded files
CMakeLists.txt
Makefile
cmake/
${PC_FILE}
EOF
    echo -e "  ${GREEN}Created:${NC} .gitignore"

    # Prompt for remote URL, retry until provided
    while true; do
        echo -en "${YELLOW}Enter remote URL: ${NC}"
        read -r remote_url < /dev/tty
        if [[ -n "${remote_url}" ]]; then
            break
        fi
        echo -e "  ${RED}Error:${NC} Remote URL is required."
    done

    git -C "${DEST_DIR}" remote add origin "${remote_url}"
    echo -e "  ${GREEN}Remote added:${NC} ${remote_url}"

    # Stage specific files and make initial commit
    git -C "${DEST_DIR}" add src/ include/ "${PC_FILE}" required_packages .gitignore 2>/dev/null
    git -C "${DEST_DIR}" commit -m "Initial commit: scaffold ${DIR_NAME} library environment"
    echo -e "  ${GREEN}Committed:${NC} initial library scaffold"

    git -C "${DEST_DIR}" push -u origin HEAD
    echo -e "  ${GREEN}Pushed:${NC} initial commit to ${remote_url}"
else
    echo -e "  ${RED}Skipped:${NC} git repository already exists"
fi

echo ""
echo -e "${GREEN}Done.${NC}"
echo ""
