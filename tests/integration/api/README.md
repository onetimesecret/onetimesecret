# Onetime Secret - API Definition

This directory contains the API definition for the Onetime Secret API in OpenAPI 3.0 format.

## Overview

Onetime Secret provides two versions of its API:

1. **API v1**: The original API for creating and viewing secrets.
2. **API v2**: An updated version with significant additions and changes. Used by the onetimesecret.com UI (Vue-based frontend). Currently designed for internal use but may be polished for more convenient public consumption in the future.

These API versions are currently maintained in a single file due to technical constraints, but we plan to separate them in the future.
## Files

- `index.json`: OpenAPI v3.0 definition containing both API v1 and v2.

## API Version Separation: Future Plans

While we currently maintain both v1 and v2 APIs in a single OpenAPI 3 definition file, we intend to separate these versions in the future. Our goal is to eventually maintain separate API definitions for the following reasons:

1. **Clarity and organization**: Separate definitions will provide clearer documentation and prevent confusion for API consumers.
2. **Independent maintenance**: Updates and changes can be made to each version without affecting the other.
3. **Improved developer experience**: API consumers will be able to easily choose the version they need without navigating through mixed documentation.
4. **Version-specific testing**: Facilitating independent testing and validation for each version.
5. **Efficient deprecation management**: Easier to manage if we plan to deprecate the older version in the future.
6. **Scalability**: As our API evolves, separate files will be more manageable for future versions.

We recognize the benefits of this approach and plan to implement this separation as soon as the technical limitations are addressed. This will allow us to better serve our API consumers and maintain a more organized and efficient API ecosystem.

## Using the API Definition

### For Developers

- Refer to the specific version's documentation within the OpenAPI definition for endpoint details, request parameters, and response formats.
- Ensure you're using the correct API version for your integration.
- Check the changelog (if available) for updates and changes between versions.

## Version Differences

While both API versions serve the core functionality of Onetime Secret, they differ in several aspects:

- Endpoint naming conventions
- Request and response structures
- Available features and capabilities

There is only about 20% overlap in terms of fields and endpoint naming between v1 and v2. Refer to each version's specific documentation within the OpenAPI definition for detailed information on endpoints and usage.

## Support and Questions

If you have any questions about using this API definition or need clarification on version differences, please contact our support team or refer to the official Onetime Secret documentation.

---

Remember to keep your API keys and sensitive information secure and never commit them to version control systems.
