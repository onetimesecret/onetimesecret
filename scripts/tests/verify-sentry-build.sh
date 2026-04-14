#!/usr/bin/env bash
#
# verify-sentry-build.sh - Verify Sentry source map build configuration
#
# Issue: #2959 - Upload source maps to Sentry for readable stacktraces
#
# This script verifies build behavior with and without Sentry environment variables.
# It checks that:
# - Builds succeed when SENTRY_AUTH_TOKEN is NOT set (graceful degradation)
# - Source maps are generated after build
# - No credentials leak into build output
#
# Usage:
#   ./scripts/tests/verify-sentry-build.sh          # Run all checks
#   ./scripts/tests/verify-sentry-build.sh --quick  # Skip build, check existing output
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Configuration
DIST_DIR="public/web/dist"
ASSETS_DIR="${DIST_DIR}/assets"
QUICK_MODE="${1:-}"

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((SKIPPED++))
}

log_info() {
    echo -e "[INFO] $1"
}

# Check if we're in the project root
check_project_root() {
    if [[ ! -f "vite.config.ts" ]]; then
        echo "Error: Must run from project root (where vite.config.ts is located)"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required for manifest verification"
        exit 1
    fi
}

# Test: Build succeeds without SENTRY_AUTH_TOKEN
test_build_without_sentry() {
    log_info "Testing build without SENTRY_AUTH_TOKEN..."

    # Ensure SENTRY_AUTH_TOKEN is not set for this test
    unset SENTRY_AUTH_TOKEN 2>/dev/null || true
    unset SENTRY_ORG 2>/dev/null || true
    unset SENTRY_PROJECT 2>/dev/null || true

    # Clean previous build
    rm -rf "${DIST_DIR}" 2>/dev/null || true

    # Run build
    if NODE_ENV=production pnpm run build 2>&1; then
        log_pass "Build succeeds without SENTRY_AUTH_TOKEN"
        return 0
    else
        log_fail "Build failed without SENTRY_AUTH_TOKEN"
        return 1
    fi
}

# Test: Source maps are generated
test_source_maps_generated() {
    log_info "Checking for source map generation..."

    if [[ ! -d "${ASSETS_DIR}" ]]; then
        log_fail "Assets directory does not exist: ${ASSETS_DIR}"
        return 1
    fi

    # Check for .js.map files
    local map_count
    map_count=$(find "${ASSETS_DIR}" -name "*.map" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "${map_count}" -gt 0 ]]; then
        log_pass "Source maps generated: ${map_count} .map file(s) found"
        find "${ASSETS_DIR}" -name "*.map" -type f | head -5 | while read -r f; do
            log_info "  - $(basename "$f")"
        done
        return 0
    else
        log_fail "No source maps found in ${ASSETS_DIR}"
        return 1
    fi
}

# Test: JavaScript files are generated
test_js_files_generated() {
    log_info "Checking for JavaScript bundle generation..."

    if [[ ! -d "${ASSETS_DIR}" ]]; then
        log_fail "Assets directory does not exist: ${ASSETS_DIR}"
        return 1
    fi

    # Check for .js files
    local js_count
    js_count=$(find "${ASSETS_DIR}" -name "*.js" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "${js_count}" -gt 0 ]]; then
        log_pass "JavaScript bundles generated: ${js_count} .js file(s) found"
        return 0
    else
        log_fail "No JavaScript files found in ${ASSETS_DIR}"
        return 1
    fi
}

# Test: Manifest file is generated
test_manifest_generated() {
    log_info "Checking for manifest.json..."

    local manifest_path="${DIST_DIR}/.vite/manifest.json"

    if [[ -f "${manifest_path}" ]]; then
        log_pass "Manifest file generated at ${manifest_path}"

        # Verify it's valid JSON
        if jq empty "${manifest_path}" 2>/dev/null; then
            log_pass "Manifest is valid JSON"
        else
            log_fail "Manifest is not valid JSON"
        fi
        return 0
    else
        log_fail "Manifest file not found at ${manifest_path}"
        return 1
    fi
}

# Test: No credentials in build output
test_no_credentials_in_output() {
    log_info "Checking for leaked credentials in build output..."

    if [[ ! -d "${ASSETS_DIR}" ]]; then
        log_skip "Assets directory does not exist, skipping credential check"
        return 0
    fi

    local leaked=0

    # Check for Sentry auth token patterns
    if grep -r "sntrys_" "${ASSETS_DIR}" 2>/dev/null; then
        log_fail "Found Sentry auth token pattern in build output"
        leaked=1
    fi

    # Check for SENTRY_AUTH_TOKEN literal
    if grep -r "SENTRY_AUTH_TOKEN" "${ASSETS_DIR}" 2>/dev/null; then
        log_fail "Found SENTRY_AUTH_TOKEN string in build output"
        leaked=1
    fi

    if [[ "${leaked}" -eq 0 ]]; then
        log_pass "No credentials found in build output"
        return 0
    else
        return 1
    fi
}

# Test: vite.config.ts has conditional Sentry plugin
test_config_conditional_sentry() {
    log_info "Checking vite.config.ts for conditional Sentry plugin..."

    # Check for import
    if ! grep -q "sentryVitePlugin" vite.config.ts; then
        log_fail "sentryVitePlugin not imported in vite.config.ts"
        return 1
    fi

    log_pass "sentryVitePlugin is imported in vite.config.ts"

    # Check for conditional activation (common patterns)
    if grep -qE "process\.env\.SENTRY_AUTH_TOKEN.*sentryVitePlugin|sentryVitePlugin.*process\.env\.SENTRY_AUTH_TOKEN" vite.config.ts; then
        log_pass "Sentry plugin appears to be conditionally activated"
    else
        # It's imported but may not be conditionally used yet
        log_info "Note: Sentry plugin conditional activation pattern not detected"
        log_info "      Expected: process.env.SENTRY_AUTH_TOKEN && sentryVitePlugin({...})"
    fi

    return 0
}

# Test: .env.reference documents Sentry variables
test_env_reference_complete() {
    log_info "Checking .env.reference for Sentry documentation..."

    local env_ref=".env.reference"
    local missing=0

    if [[ ! -f "${env_ref}" ]]; then
        log_fail ".env.reference file not found"
        return 1
    fi

    for var in SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT SENTRY_URL SENTRY_RELEASE; do
        if grep -q "^${var}=" "${env_ref}" || grep -q "^#${var}=" "${env_ref}"; then
            log_pass "${var} documented in .env.reference"
        else
            log_fail "${var} missing from .env.reference"
            missing=1
        fi
    done

    return "${missing}"
}

# Summary
print_summary() {
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo -e "Passed:  ${GREEN}${PASSED}${NC}"
    echo -e "Failed:  ${RED}${FAILED}${NC}"
    echo -e "Skipped: ${YELLOW}${SKIPPED}${NC}"
    echo "========================================"

    if [[ "${FAILED}" -gt 0 ]]; then
        echo -e "${RED}Some tests failed${NC}"
        return 1
    else
        echo -e "${GREEN}All tests passed${NC}"
        return 0
    fi
}

# Main
main() {
    check_project_root

    echo "========================================"
    echo "Sentry Source Map Build Verification"
    echo "========================================"
    echo ""

    # Configuration checks (always run)
    test_config_conditional_sentry || true
    test_env_reference_complete || true

    if [[ "${QUICK_MODE}" == "--quick" ]]; then
        log_info "Quick mode: skipping build, checking existing output"
    else
        # Build test
        test_build_without_sentry || true
    fi

    # Build output checks
    test_js_files_generated || true
    test_source_maps_generated || true
    test_manifest_generated || true
    test_no_credentials_in_output || true

    print_summary
}

main "$@"
