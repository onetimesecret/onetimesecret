# Ongoing API Development with Postman: Managing Scripts and Tests

## Overview
The OpenAPI schema defines your API's structure but doesn't include Postman-specific components like pre-request scripts, tests, and collection variables. This guide explains how to effectively version control and maintain these components alongside your schema-driven development.

## Prerequisites
- Git repository for version control
- Postman workspace and collections
- OpenAPI schema defining your API
- Newman or Postman CLI tools for automation

## Version Control Strategy

### Collection Components to Track
The Postman collection JSON file includes:
```json
{
  "info": {
    "name": "API Collection",
    "version": "1.0.0"
  },
  "item": [
    {
      "name": "Create User",
      "event": [
        {
          "listen": "prerequest",
          "script": {
            "exec": ["// Pre-request script content"]
          }
        },
        {
          "listen": "test",
          "script": {
            "exec": ["// Test script content"]
          }
        }
      ],
      "request": { /* Request details */ }
    }
  ],
  "variable": [
    {
      "key": "currentUserId",
      "value": "",
      "type": "string"
    }
  ]
}
```

### Implementation Steps

1. Export Collection for Version Control
```bash
# Using Postman CLI
postman collection export "Your Collection Name" > ./api/collections/api.postman_collection.json

# Using Newman
newman export-collection -c "Collection ID" -o ./api/collections/api.postman_collection.json
```

2. Repository Structure
```
api/
├── schemas/
│   └── openapi.json       # API schema
├── collections/
│   └── api.postman_collection.json  # Complete collection with scripts
└── automation/
  └── sync-collection.js   # Synchronization script
```

3. Synchronization Script
```javascript
const postman = require('postman-api');
const fs = require('fs');

async function syncCollection() {
  // Export collection from Postman
  const collection = await postman.getCollection(process.env.COLLECTION_ID);

  // Write to repository
  await fs.writeFileSync(
    './api/collections/api.postman_collection.json',
    JSON.stringify(collection, null, 2)
  );
}
```

## CI/CD Integration

### Automated Synchronization
```yaml
# .github/workflows/postman-sync.yml
name: Sync Postman Collection
on:
  push:
  paths:
    - 'api/schemas/**'
    - 'api/collections/**'

jobs:
  sync:
  runs-on: ubuntu-24.04
  steps:
    - uses: actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955 # v4
    - name: Sync Collection
    run: node automation/sync-collection.js
    env:
      POSTMAN_API_KEY: ${{ secrets.POSTMAN_API_KEY }}
      COLLECTION_ID: ${{ secrets.COLLECTION_ID }}
```

### Validation Steps
1. Export current collection
2. Run schema validation
3. Execute collection tests
4. Commit updates if tests pass

## Documentation and Mapping

### Code Mapping Example
```javascript
/**
 * Create User Endpoint
 * Route: POST /api/users
 * Codebase Location: src/controllers/user/create.js
 * Collection Request: "Create User"
 *
 * Pre-request Script:
 * - Validates request payload
 * - Sets authentication headers
 *
 * Tests:
 * - Verifies response structure
 * - Stores userId for subsequent requests
 */
```

### Collection Documentation
```javascript
pm.test("Create User Response", function() {
  // Maps to: src/controllers/user/create.js
  const response = pm.response.json();
  pm.expect(response).to.have.property('id');
  // Store for workflow
  pm.collectionVariables.set("currentUserId", response.id);
});
```

## Best Practices

### Version Control
- Commit collection updates with meaningful messages
- Track script changes separately from schema changes
- Include documentation updates in commits

### Script Management
- Keep scripts modular and focused
- Document dependencies between requests
- Maintain clear variable naming conventions

### Synchronization
- Automate collection exports
- Validate collection updates before commit
- Maintain backup copies of collections

## Troubleshooting

### Common Issues
1. Script Conflicts
   - Solution: Review and merge scripts manually after schema updates

2. Variable Scope Issues
   - Solution: Document variable lifecycles and validate scopes

3. Synchronization Failures
   - Solution: Verify API keys and permissions

## Related Documentation
- OpenAPI Schema Guidelines
- Postman API Documentation
- Newman CLI Documentation
- Git Best Practices

## Prompts

```prompt
We're working with postman collection "API Reference (2024-10-11)" (921ac7a7-6ef2-4b90-8fed-9b33df220a96).

@apps/api/v1/routes

@apps/api/v1/endpoints.rb

* Route files contain the literal URL paths that are supported by the API.
* Endpoint files are like the controllers in MVC. Each route is mapped to one endpoint.
* Logic Files contain the REST API implementation details (processed request params, body etc) and defines response JSON format in `success_data`:.

@apps/api/v2/logic

Our ultimate goal is for the Collection to be be the source of truth, accurate and complete representation of the codebase. We need to ensure that each request in Postman matches a corresponding route and logic file, and that all necessary fields are correctly defined.

Work methodically through the routes, matching each up with the appropriate endpoint and logic files. For each route, follow these steps:
1. **Identify the Route**: Find the route in `@apps/api/v1/routes`.
2. **Match with Endpoint**: Ensure there is a corresponding endpoint method in `@apps/api/v1/endpoints.rb` that maps to this route.
3. **Check Logic File**: Verify that the logic for handling requests and generating responses is correctly defined in the appropriate logic file within `@lib/onetime/logic`.
4. **Validate Fields**: Ensure all necessary fields (e.g., request parameters, response structure) are accurately represented in Postman.
```
