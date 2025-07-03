# RSFC Design Document
**Ruby Single File Components (.rue) for Server-to-SPA Handoff**

## Purpose & Value Proposition

**Ruby Single File Components (RSFCs)** provide Vue SFC-inspired organization for server-side templating, specifically targeting the **manifold** problem in modern web applications.

### Manifold Definition
The **manifold** is the critical handoff point between server-rendered initial state and client-side JavaScript framework hydration. Current solutions require manual coordination between server serializers and client component props, creating maintenance overhead and type safety gaps.

**RSFC eliminates this coordination step** by making server-to-client data flow declarative and co-located.

## File Format Specification

### Required Sections
```html
<data window="data" schema="@/src/schemas/component.ts">
{
  "user_id": "{{user.id}}",
  "is_authenticated": {{user.authenticated?}}
}
</data>

<template>
<div>{{> header}}</div>
<main>Content here</main>
</template>
```

### Optional Sections
- `<logic>` - Server-side Ruby processing before render

### Template Syntax
- **Rhales** - Ruby handlebars subset using Prism parser, based on the [Handlebars spec](https://handlebars-lang.github.io/spec/)
- **Partials** via `{{> partial_name}}` map to other `.rue` files
- **Logic-free** templates maintain separation of concerns

### Data Section Behavior
- **JSON structure** with Rhales interpolation for server variables
- **Automatic client hydration** - populates `window[attribute]` based on `window` attribute
- **Type safety bridge** via `schema` attribute pointing to TypeScript definitions (future)
- **Restricted scope** - only access to explicitly provided context

## Technical Architecture

### Parsing Pipeline
- **Prism** - Ruby expression parsing with proper semantics
- **Rhales** - Template rendering with handlebars subset interpolation
- **JSON Script Elements** - Secure data boundary using `<script type="application/json">`

### Context Resolution
1. **Runtime context** - CSRF tokens, nonces, request metadata
2. **Business context** - User data, application state from route handlers
3. **Computed context** - Server-side transformations and derived values

## Implemented Components ✅

### Core Parser (`lib/onetime/rsfc/parser.rb`)
- ✅ Parses `.rue` files into `<data>`, `<template>`, `<logic>` sections
- ✅ Extracts `window` and `schema` attributes from data tags
- ✅ Identifies partials and variables for validation
- ✅ Validates JSON structure in data sections

### RSFCContext (`lib/onetime/rsfc/context.rb`)
- ✅ Clean, focused context class following established patterns
- ✅ Three-layer data system: runtime, business, computed
- ✅ Single instance per page render (security boundary)
- ✅ Dot-notation variable access (`user.id`, `features.enabled`)
- ✅ Immutable after creation for thread safety

### Rhales Template Engine (`lib/onetime/rsfc/rhales.rb`)
- ✅ Pure Prism-based parsing (no external handlebars dependency)
- ✅ Variable interpolation: `{{variable}}` with HTML escaping
- ✅ Raw interpolation: `{{{variable}}}` without escaping
- ✅ Conditionals: `{{#if condition}}` / `{{#unless condition}}`
- ✅ Iteration: `{{#each items}}` with item context
- ✅ Partials: `{{> partial_name}}` with recursive processing
- ✅ XSS protection through automatic HTML escaping

### Data Hydrator (`lib/onetime/rsfc/hydrator.rb`)
- ✅ JSON script element generation (`<script type="application/json">`)
- ✅ Custom window attribute support (`window.data`, `window.customName`)
- ✅ API-like security boundary through serialization
- ✅ Variable interpolation in data sections using Rhales

### Ruequire Refinement (`lib/onetime/refinements/require_refinements.rb`)
- ✅ Intercepts `.rue` file requires with caching and file watching
- ✅ Smart path resolution (templates/, templates/web/)
- ✅ Development mode file watching with cache invalidation
- ✅ Performance optimization through AST caching

### RSFC View System (`lib/onetime/rsfc/view.rb`)
- ✅ Replaces Mustache with RSFC rendering
- ✅ Template + hydration integration
- ✅ Partial resolution system
- ✅ Error handling and debugging support

### Migrated BaseView (`apps/web/manifold/views/base.rb`)
- ✅ Extends RSFC::View instead of Mustache
- ✅ Maintains compatibility with existing helpers
- ✅ i18n and message system integration
- ✅ Backward compatibility for existing code

## Decided Design Elements

✅ **File extension**: `.rue`
✅ **Required sections**: `<template>` + `<data>`
✅ **Template syntax**: Rhales (handlebars subset)
✅ **Data format**: JSON with server interpolation
✅ **Parsing approach**: Prism-only (no external dependencies)
✅ **Client hydration**: JSON script elements → `window[attribute]`
✅ **Security model**: Single context per render, explicit data boundaries
✅ **Partial system**: Inherit parent context, cannot expand data access

## Security Architecture

### Data Flow Boundary
```
RSFCContext (superset) → <data> (filter/select) → JSON Script → window[attribute]
```

### Key Security Features
- **Explicit data declaration**: Templates can only access variables in `<data>`
- **Single context per render**: Partials cannot expand information surface area
- **JSON boundary**: Data serialized once, parsed once (like REST APIs)
- **Fail-fast validation**: Errors if templates reference undeclared variables

## Integration Points

### Server Framework Integration
```ruby
# Route handlers provide business data to RSFC renderer
get '/dashboard' do
  view = Manifold::Views::BaseView.new(request, session, current_user, locale,
                                       business_data: {
                                         user: current_user,
                                         products: recent_products
                                       })
  view.render('dashboard')
end
```

### Client Framework Handoff
```html
<!-- Automatically generated from <data window="pageData"> -->
<script id="rsfc-data-abc123" type="application/json">
{"user_id":123,"is_authenticated":true}
</script>
<script nonce="xyz789">
window.pageData = JSON.parse(document.getElementById('rsfc-data-abc123').textContent);
</script>
```

## Testing & Validation ✅

### Comprehensive Test Suite (`tests/unit/ruby/rsfc_test.rb`)
- ✅ Parser validation (sections, attributes, variables)
- ✅ Context resolution (nested variables, type handling)
- ✅ Template rendering (variables, conditionals, loops)
- ✅ Data hydration (JSON generation, window assignment)
- ✅ Full integration testing (end-to-end workflow)
- ✅ All 30+ test assertions passing

## Performance Features

### Optimization Strategies
- ✅ **AST Caching**: Parsed templates cached with modification time tracking
- ✅ **File Watching**: Development mode cache invalidation on file changes
- ✅ **Immutable Contexts**: Thread-safe context objects
- ✅ **Lazy Evaluation**: Expensive computations deferred until needed
- ✅ **Smart Path Resolution**: Efficient template file lookups

## Migration Strategy

### Backward Compatibility
- ✅ **Helper Compatibility**: Existing SanitizerHelpers, I18nHelpers, ViteManifest work unchanged
- ✅ **API Preservation**: BaseView initialization and render methods maintain compatibility
- ✅ **Incremental Adoption**: Can migrate templates one at a time
- ✅ **Error Handling**: Clear error messages with file paths and line numbers

## Next Steps (Future Development)

### Schema Integration
❓ **TypeScript Integration**: Generate TypeScript definitions from `schema` attributes
❓ **Runtime Validation**: Validate data against schemas before JSON serialization
❓ **Zod Pipeline**: Integration with existing Zod v4 configuration system

### Development Experience
❓ **Syntax Highlighting**: VSCode/editor support for `.rue` files
❓ **Hot Reload**: Enhanced file watching with WebSocket notifications
❓ **Debug Tools**: Template variable inspection and data flow visualization

### Advanced Features
❓ **Logic Sections**: Server-side Ruby processing in `<logic>` sections
❓ **Nested Contexts**: Support for component-scoped contexts
❓ **Performance Monitoring**: Template rendering performance metrics

## Success Metrics

**✅ Primary Goal Achieved**: Eliminated manual API design in server-to-SPA scenarios
**✅ Developer Experience**: Co-located data and templates improve development velocity
**✅ Type Safety Foundation**: Schema attribute ready for TypeScript integration
**✅ Performance**: Competitive with Mustache (cached parsing, minimal overhead)
**✅ Security**: Explicit data boundaries prevent accidental exposure

---

**Status**: ✅ **Core Implementation Complete and Tested**

The RSFC system is now largely implemented and ready for use in development. Core components are built, tested, and integrated with the existing OneTimeSecret codebase. The `.rue` template files (`index.rue`, `head.rue`) are compatible with the new system through the migrated `BaseView` class.
