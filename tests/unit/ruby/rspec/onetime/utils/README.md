# About these tests

Test coverage for utility methods in `Onetime::Utils`.

## Key Testing Principles Applied
- **Failure-driven**: Tests demonstrate exact scenarios that would fail without fixes
- **Security-focused**: Tests verify configuration tampering prevention
- **Real-world**: Tests mirror actual OneTimeSecret config system usage
- **Edge case coverage**: Empty objects, nil values, error conditions
- **Mutation isolation**: Verifies independent modification capabilities
