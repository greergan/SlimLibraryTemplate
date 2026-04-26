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
    HEADER_DIR="${DEST_DIR}/include/slim"
    HEADER_FILE="${DIR_NAME}.hpp"
elif [[ ${WORD_COUNT} -eq 2 ]]; then
    SUBDIR="$(echo "${WORDS[0]}" | tr '[:upper:]' '[:lower:]')"
    FILENAME="$(echo "${WORDS[1]}" | tr '[:upper:]' '[:lower:]').h"
    HEADER_DIR="${DEST_DIR}/include/slim/${SUBDIR}"
    HEADER_FILE="${FILENAME}"
elif [[ ${WORD_COUNT} -eq 3 ]]; then
    SUBDIR="$(echo "${WORDS[0]}" | tr '[:upper:]' '[:lower:]')"
    SUBDIR2="$(echo "${WORDS[1]}" | tr '[:upper:]' '[:lower:]')"
    FILENAME="$(echo "${WORDS[2]}" | tr '[:upper:]' '[:lower:]').h"
    HEADER_DIR="${DEST_DIR}/include/slim/${SUBDIR}/${SUBDIR2}"
    HEADER_FILE="${FILENAME}"
else
    echo -e "${RED}Error: Directory '${DIR_NAME}' has an unsupported format. Expected 'Slim' + 1, 2, or 3 words.${NC}"
    exit 1
fi

download_file() {
    local relative_path="$1"
    local dest="${DEST_DIR}/${relative_path}"
    local dest_dir
    dest_dir="$(dirname "${dest}")"

    if [[ -e "${dest}" ]]; then
        echo -en "${YELLOW}File '${relative_path}' already exists. Overwrite? [y/N]: ${NC}"
        read -r answer
        if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
            echo -e "  ${YELLOW}Skipped:${NC} ${relative_path}"
            return
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

# Download top-level files
for file in CMakeLists.txt Makefile; do
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

# Create src directory and empty TU files if not already present
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
        touch "${tu_path}"
        echo -e "  ${GREEN}Created:${NC} src/${tu}"
    else
        echo -e "  ${RED}Skipped:${NC} src/${tu} (already exists)"
    fi
done

# Build header guard from directory name words
ALL_WORDS=("Slim" "${WORDS[@]}")
EXTENSION="${HEADER_FILE##*.}"
GUARD_PARTS=()
for word in "${ALL_WORDS[@]}"; do
    GUARD_PARTS+=("$(echo "${word}" | tr '[:lower:]' '[:upper:]')")
done
GUARD_PARTS+=("$(echo "${EXTENSION}" | tr '[:lower:]' '[:upper:]')")
HEADER_GUARD="$(IFS='__'; echo "${GUARD_PARTS[*]}")"

# Create include/slim header file
echo ""
if [[ ! -d "${HEADER_DIR}" ]]; then
    mkdir -p "${HEADER_DIR}"
    echo -e "  ${GREEN}Created:${NC} ${HEADER_DIR#${DEST_DIR}/}/"
else
    echo -e "  ${RED}Skipped:${NC} ${HEADER_DIR#${DEST_DIR}/}/ (already exists)"
fi

HEADER_PATH="${HEADER_DIR}/${HEADER_FILE}"
if [[ ! -e "${HEADER_PATH}" ]]; then
    cat > "${HEADER_PATH}" << EOF
#ifndef ${HEADER_GUARD}
#define ${HEADER_GUARD}

#endif // ${HEADER_GUARD}
EOF
    echo -e "  ${GREEN}Created:${NC} ${HEADER_PATH#${DEST_DIR}/}"
else
    echo -e "  ${RED}Skipped:${NC} ${HEADER_PATH#${DEST_DIR}/} (already exists)"
fi

echo ""
echo -e "${GREEN}Done.${NC}"
echo ""
