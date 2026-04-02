# Onetime Secret - API Documentation

The authoritative API documentation is published at [api.onetimesecret.com](https://api.onetimesecret.com).

## API Versions

Onetime Secret provides three versions of its API:

* **v1**: The original API for creating and viewing secrets. Requests are form-encoded and responses are JSON. This version receives limited support mainly to keep parity with new fields but in general does not receive new features (new or renamed fields are added but existing fields are not removed or renamed). For new integrations, we recommend using v2 or v3.
* **v2**: A modern, fully JSON REST API. All field values are returned as strings which can be both a blessing because it eliminates guesswork about field types but also a curse because it requires more parsing on the client side. This version has been superseded by v3 but is still maintained for backward compatibility.
* **v3**: Our most recent API version, used by the UI (Vue-based frontend). The API is substantially similar to v2 but field values are returned as JSON primitive types (strings, numbers, booleans, arrays, objects). This version is the most actively developed and receives all new features and updates.

## OpenAPI Definitions

Generated OpenAPI definitions are available at:
- `generated/openapi/api-v1.json`
- `generated/openapi/api-v2.json`
- `generated/openapi/api-v3.json`

Run `pnpm run openapi:generate` to regenerate from source schemas.

---

Remember to keep your API keys and sensitive information secure and never commit them to version control systems.
