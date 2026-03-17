# Onetime Secret - OpenAPI Definition

> [!NOTE]
> These docs are a WIP -- March 2026

This directory contains the API definition for the Onetime Secret API in OpenAPI 3.1 format.

## Overview

Onetime Secret provides two versions of its API:

* **v1**: The original API for creating and viewing secrets. Requests are form-encoded and responses are JSON. This version receives limited supported mainly to keep parity with new fields but in general does not receive new features (new or renamed fields are added but existing fields are not removed or renamed). For new integrations, we recommend using v2 or v3.
* **v2**: A modern, fully JSON REST API. All field values are returned as strings which can be both a blessing because it elimites guesswork about field types but also a curse because it requires more parsing on the client side. This version has been superceded by v3 but is still maintained for backward compatibility and for users who prefer a stringier experience.
** **v3**: Our most recent API version, used by the UI (Vue-based frontend). The API is substantially similar to v2 but field values are returned as JSON primitive types (strings, numbers, booleans, arrays, objects). This version is the most actively developed and receives all new features and updates.

---

Remember to keep your API keys and sensitive information secure and never commit them to version control systems.
