
# Onetime Secret Test Suite

This directory contains the test suite for the Onetime Secret project. The structure is organized as follows:

```plaintext
tests/
├── unit/
│   ├── vue/
│   │   └── ... (Vue component unit tests)
│   └── ruby/
│       └── ... (Ruby unit tests)
├── integration/
│   ├── api/
│   │   └── ... (API integration tests)
│   └── web/
│       └── ... (Playwright Frontend integration tests)
├── data/
│   ├── fixtures/
│   └── ... (Test fixtures for integration tests)
├── performance/
│   └── ... (Performance and load tests - WIP)
└── security/
    └── ... (Security-related tests - WIP)
```

## Test Types

1. **Unit Tests**: Located in `unit/`, separated by technology (Vue and Ruby).
2. **Integration Tests**: In `integration/`, covering both API and web frontend testing.
3. **Performance Tests**: Found in `performance/` for load and stress testing. (WIP)
4. **Security Tests**: Placed in `security/` for vulnerability and penetration testing. (WIP)

## Running Tests

Use the script in the `supports/test-runners/` directory to run tests:

- `run-unit-tests.sh`: Executes all unit tests
- `run-integration-tests.sh`: Runs all integration tests
- `run-all-tests.sh`: Performs a full test suite run

## CI/CD

GitHub Actions workflows for automated testing are defined in `.github/workflows/`:

- `playwright.yml`: Runs Playwright tests
- `vue.yml`: Executes Vue-related tests
- `ruby.yml`: Performs Ruby-specific tests

For more detailed information on each test type, refer to the README files in their respective directories.

### Playwright Github Action

Currently running locally in our dev environments. Our github actions don't yet run all the things. Playwright itself has config settings for web server commands to run, but we have ruby, caddy, and redis to run so it'll require a little more setup. If we had an all-in-one OCI image, we might be able to simply run it with podman and then run the playwright tests against that.

```yaml
# This workflow runs Playwright tests for the project.
# It is triggered on push to fix/* and rel/* branches,
# pull requests to main, develop, and feature/* branches,
# and can also be manually triggered.

name: Playwright Tests

on:
  push:
    branches:
      - 'fix/*'
      - 'rel/*'
  pull_request:
    branches:
      - main
      - develop
      - 'feature/*'
  workflow_dispatch:
    inputs:
      debug_enabled:
        type: boolean
        description: 'Run the build with tmate debugging enabled (https://github.com/marketplace/actions/debugging-with-tmate)'
        required: false
        default: false

jobs:
  test:
    name: Run Playwright Tests
    timeout-minutes: 60
    runs-on: ubuntu-24.04

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: lts/*

    - name: Install dependencies
      run: |
        npm install -g pnpm
        pnpm install
        cp -p tests/.env.example-dev tests/.env--dev

    - name: Install Playwright Browsers
      run: pnpm exec playwright install --with-deps

    - name: Run Playwright tests
      run: pnpm exec playwright test

    - name: Upload test results
      uses: actions/upload-artifact@v4
      if: ${{ !cancelled() }}
      with:
        name: playwright-report
        path: playwright-report/
        retention-days: 5
```
