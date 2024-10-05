
# OneTimeSecret Test Suite

This directory contains the test suite for the OneTimeSecret project. The structure is organized as follows:

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
│   └── ... (Performance and load tests)
└── security/
    └── ... (Security-related tests)
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
