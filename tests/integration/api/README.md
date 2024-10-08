# Onetime Secret API Definitions

This directory contains the API definitions for Onetime Secret in JSON format, compatible with Postman collections.

## Overview

Onetime Secret provides two versions of its API:

1. **API v1**: The original API version
2. **API v2**: An updated version with significant changes

These API versions are tracked separately due to substantial differences in their structure and functionality.

## Files

- `onetime-secret-api-v1.json`: Postman collection for API v1
- `onetime-secret-api-v2.json`: Postman collection for API v2

## Why Separate API Versions?

The decision to maintain separate API definitions was made based on the following factors:

1. **Significant differences**: There is only about 20% overlap in terms of fields and endpoint naming between v1 and v2.
2. **Clarity**: Separate definitions provide clearer documentation and prevent confusion for API consumers.
3. **Maintenance**: Independent updates and changes can be made without affecting the other version.
4. **Developer experience**: API consumers can easily choose the version they need without navigating through mixed documentation.
5. **Version-specific testing**: Facilitates independent testing and validation for each version.
6. **Deprecation management**: Easier to manage if we plan to deprecate the older version in the future.

## Using the API Definitions

### In Postman

1. Open Postman and click on "Import" in the top left corner.
2. Choose the JSON file for the API version you want to use (`onetime-secret-api-v1.json` or `onetime-secret-api-v2.json`).
3. The collection will be imported into your Postman workspace.
4. Set up environment variables for base URLs, authentication tokens, etc., as needed.

### For Developers

- Refer to the specific version's documentation for endpoint details, request parameters, and response formats.
- Ensure you're using the correct API version for your integration.
- Check the changelog (if available) for updates and changes between versions.

## Version Differences

While both API versions serve the core functionality of Onetime Secret, they differ in several aspects:

- Endpoint naming conventions
- Request and response structures
- Available features and capabilities

Refer to each version's specific documentation for detailed information on endpoints and usage.

## Support and Questions

If you have any questions about using these API definitions or need clarification on version differences, please contact our support team or refer to the official Onetime Secret documentation.

---

Remember to keep your API keys and sensitive information secure and never commit them to version control systems.
