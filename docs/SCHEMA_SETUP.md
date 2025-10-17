# Rhales Schema Generation and Validation Setup

This document describes the schema generation and validation infrastructure for Onetime Secret's Rhales templates.

## Overview

The schema infrastructure provides:

1. **JSON Schema Generation** - Automatically generates JSON schemas from Zod definitions in `.rue` template files
2. **Schema Validation** - Validates hydration data at runtime (development mode)
3. **Type Safety** - Ensures backend data matches frontend expectations

## Architecture

```
.rue Template Files (with <schema> blocks)
    ↓
Schema Extraction (Rhales::SchemaExtractor)
    ↓
Zod → JSON Schema Conversion (via pnpm exec tsx)
    ↓
JSON Schema Files (public/schemas/*.json)
    ↓
Runtime Validation (Rhales::Middleware::SchemaValidator)
```

## Setup Complete

The following has been configured:

### 1. Rakefile

**Location:** `/Users/d/Projects/opensource/onetime/onetimesecret/Rakefile`

Loads Rhales rake tasks for schema operations:
- `rhales:schema:generate` - Generate JSON schemas
- `rhales:schema:stats` - Show schema statistics
- `rhales:schema:validate` - Validate generated schemas

### 2. Package.json Scripts

**Location:** `/Users/d/Projects/opensource/onetime/onetimesecret/package.json`

Added convenience scripts:
```json
{
  "scripts": {
    "build:schemas": "Generate JSON schemas from .rue templates",
    "build:schemas:stats": "Show schema statistics",
    "build:schemas:validate": "Validate generated schemas"
  }
}
```

### 3. Schema Validator Middleware

**Location:** `/Users/d/Projects/opensource/onetime/onetimesecret/config.ru`

Configured middleware for development mode:
- Validates hydration data matches schemas
- Fails loudly on mismatches in development
- Only active when `RACK_ENV=development`

### 4. Generated Schemas

**Location:** `/Users/d/Projects/opensource/onetime/onetimesecret/public/schemas/`

Current schemas:
- `index.json` - Schema for index.rue template

## Usage

### Generate Schemas

After adding or modifying `<schema>` sections in `.rue` files:

```bash
# Using pnpm (recommended)
pnpm run build:schemas

# Or directly with rake
ruby -I ../rhales/lib -r rake -e "load 'Rakefile'; Rake.application.run" -- rhales:schema:generate TEMPLATES_DIR=./apps/web/core/templates OUTPUT_DIR=./public/schemas
```

### View Schema Statistics

```bash
pnpm run build:schemas:stats
```

Output:
```
Schema Statistics
============================================================
Templates directory: ./apps/web/core/templates

Total .rue files: 2
Files with <schema>: 1
Files without <schema>: 1

By language:
  js-zod: 1
```

### Validate Schemas

```bash
pnpm run build:schemas:validate
```

## Adding Schemas to Templates

In your `.rue` template files, add a `<schema>` block:

```handlebars
<schema lang="js-zod" version="2" window="__ONETIME_STATE__">
import { z } from 'zod';

const schema = z.object({
  authenticated: z.boolean(),
  custid: z.string().nullable(),
  locale: z.string(),
  // ... more fields
});
</schema>

<template layout="">
<!doctype html>
<html>
  <!-- template content -->
</html>
</template>
```

### Schema Attributes

- `lang="js-zod"` - Schema language (currently only js-zod supported)
- `version="2"` - Schema version
- `window="__ONETIME_STATE__"` - JavaScript window variable for hydration

## Runtime Validation

When running in development mode (`RACK_ENV=development`), the middleware will:

1. Extract hydration data from HTML responses
2. Load the corresponding JSON schema
3. Validate data against schema
4. Raise `ValidationError` if mismatches found

### Error Example

```
Schema validation failed for template: index
Validation time: 12.34ms

Window variable: __ONETIME_STATE__
Errors:
  - The property '/authenticated' of type string did not match the following type: boolean
  - The property '/custid' is missing required field(s): custid

This means your backend is sending data that doesn't match the contract
defined in the <schema> section of index.rue

To fix:
1. Check the schema definition in index.rue
2. Verify the data passed to render('index', ...)
3. Ensure types match (string vs number, required fields, etc.)
```

## Skipped Paths

The middleware automatically skips validation for:
- `/assets/*` - Static assets
- `/api/*` - API endpoints
- `/public/*` - Public files
- Files with extensions: `.css`, `.js`, `.png`, `.jpg`, `.svg`, `.ico`, etc.

## Dependencies

### Required
- **Ruby 3.4+** - For rake tasks
- **Node.js with pnpm** - For Zod to JSON Schema conversion
- **tsx** - TypeScript execution (installed via pnpm)
- **Zod v4** - Schema definition library (installed via pnpm)

### Optional
- **json_schemer** - For runtime validation (Ruby gem)
  - If not installed, validation middleware will be disabled
  - Schema generation will still work

## File Locations

| Component | Location |
|-----------|----------|
| Rake Tasks | `/Users/d/Projects/opensource/onetime/rhales/lib/tasks/rhales_schema.rake` |
| Schema Generator | `/Users/d/Projects/opensource/onetime/rhales/lib/rhales/schema_generator.rb` |
| Schema Extractor | `/Users/d/Projects/opensource/onetime/rhales/lib/rhales/schema_extractor.rb` |
| Validator Middleware | `/Users/d/Projects/opensource/onetime/rhales/lib/rhales/middleware/schema_validator.rb` |
| Templates | `/Users/d/Projects/opensource/onetime/onetimesecret/apps/web/core/templates/` |
| Generated Schemas | `/Users/d/Projects/opensource/onetime/onetimesecret/public/schemas/` |

## Troubleshooting

### Issue: pnpm not found

**Solution:** Schema generation requires pnpm for running TypeScript
```bash
npm install -g pnpm
```

### Issue: Schema generation fails

**Checklist:**
1. Zod v4 is installed in frontend dependencies
2. Templates directory path is correct
3. Schema TypeScript code is valid
4. tsx package is available

### Issue: Middleware reports validation errors

**Steps:**
1. Compare actual hydration data with schema definition
2. Check for type mismatches (string vs boolean, etc.)
3. Verify nullable fields are properly marked
4. Ensure all required fields are present

### Issue: Middleware not loading

**Cause:** `json_schemer` gem not available

**Solution:** Either:
1. Add `json_schemer` to Gemfile and run `bundle install`, or
2. Validation will be disabled (schema generation still works)

## Best Practices

1. **Generate schemas after template changes**
   - Run `pnpm run build:schemas` after modifying `<schema>` blocks
   - Commit generated schemas to version control

2. **Keep schemas in sync**
   - Schema changes should be coordinated with backend data changes
   - Update both schema definition and serializer code together

3. **Use in development only**
   - Runtime validation has performance overhead
   - Production should rely on pre-validated schemas

4. **Validate schemas in CI/CD**
   - Add `pnpm run build:schemas:validate` to CI pipeline
   - Catch schema issues before deployment

## Next Steps

1. Add schema validation to CI/CD pipeline
2. Generate schemas for remaining templates
3. Consider adding schemas to build process
4. Monitor validation statistics in development

## Resources

- [Rhales Documentation](https://github.com/delano/rhales)
- [Zod Documentation](https://zod.dev)
- [JSON Schema Specification](https://json-schema.org)
