# Examples

This directory contains executable examples that demonstrate how different parts of the OneTime Secret codebase work together. These examples are written using the [tryouts](https://github.com/delano/tryouts) testing framework and serve as both integration tests and documentation for contributors.

## Purpose

The examples show real workflows and system interactions without all the implementation details and "plumbing" code. They're particularly valuable for:

- **Contributors**: Understanding how components integrate
- **Developers**: Learning system behavior patterns
- **Maintenance**: Ensuring complex workflows continue to work
- **Documentation**: Executable examples of system capabilities

## Running Examples

Examples can be run individually using the tryouts command:

```bash
# Run a specific example
tryouts examples/authentication/routes_flow_example.rb

# Run all examples in a directory
tryouts examples/secret_workflows/

# Run all examples
tryouts examples/
```

## Writing Examples

Examples should:
- Focus on workflows and interactions between components
- Show realistic usage patterns
- Include expected outputs for verification
- Avoid implementation details when possible
- Demonstrate the "happy path" and common error scenarios

## Integration with CI

These examples serve as integration tests and should be run as part of the continuous integration process to ensure system workflows continue to function correctly.
