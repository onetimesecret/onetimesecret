#!/bin/bash

# update-version.sh - Update package.json version from git tags or provided version
#
# Usage:
#   ./bin/update-version.sh           # Auto-detect from git
#   ./bin/update-version.sh v1.2.3    # Use provided version
#   VERSION=v1.2.3 ./bin/update-version.sh  # Use environment variable
#
# @see ./.github/workflows/.build-and-publish-oci-images-reusable.yml

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
log() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Get version from various sources
get_version() {
    local version=""

    # 1. Command line argument
    if [ -n "$1" ]; then
        version="$1"
        log "Using version from argument: $version"
    # 2. Environment variable
    elif [ -n "$VERSION" ]; then
        version="$VERSION"
        log "Using version from environment: $version"
    # 3. GitHub Actions ref
    elif [ -n "$GITHUB_REF" ] && [[ "$GITHUB_REF" =~ ^refs/tags/v ]]; then
        version=${GITHUB_REF#refs/tags/}
        log "Using version from GitHub ref: $version"
    # 4. Git tag (exact match to the current commit)
    elif git describe --tags --exact-match >/dev/null 2>&1; then
        version=$(git describe --tags --exact-match)
        log "Using version from exact git tag: $version"
    else
        error "No version found. Provide version as argument or ensure git tags exist."
        exit 1
    fi

    echo "$version"
}

# Validate version format
validate_version() {
    local version="$1"

    # Remove 'v' prefix if present
    local clean_version="${version#v}"

    # Basic semver validation
    if [[ ! "$clean_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?(\+[a-zA-Z0-9\.-]+)?$ ]]; then
        error "Invalid version format: $version"
        error "Expected format: v1.2.3, v1.2.3-rc1, or 1.2.3"
        exit 1
    fi

    echo "$clean_version"
}

# Update package.json
update_package_json() {
    local version="$1"
    local package_file="package.json"

    if [ ! -f "$package_file" ]; then
        error "package.json not found in current directory"
        exit 1
    fi

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        error "jq is required but not installed"
        exit 1
    fi

    # Backup original file
    cp "$package_file" "${package_file}.backup"

    # Update version using jq
    if jq --arg version "$version" '.version = $version' "$package_file" > "${package_file}.tmp"; then
        mv "${package_file}.tmp" "$package_file"
        log "Updated $package_file version to $version"

        # Show the change
        grep '"version"' "$package_file"

        # Clean up backup
        rm -f "${package_file}.backup"
    else
        error "Failed to update $package_file"
        # Restore backup
        mv "${package_file}.backup" "$package_file"
        exit 1
    fi
}

# Main execution
main() {
    log "Starting version update process..."

    # Get and validate version
    local raw_version
    raw_version=$(get_version "$1")
    local clean_version
    clean_version=$(validate_version "$raw_version")

    # Update package.json
    update_package_json "$clean_version"

    log "Version update completed successfully!"
}

# Run main function with all arguments
main "$@"
