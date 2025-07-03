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
- `<context>` - Business data transformation
- `<schema>` - Validation/type definitions

### Template Syntax
- ~Handlebars for variable interpolation and control flow~ **Rhales** The ruby handlebars lib is not maintained. We also want to use a Prism parser so our Rue templates will support a subset of Handlebars syntax, based on the spec: https://handlebars-lang.github.io/spec/. Ours will be called Rhales ("Mustache" is the original name -> "Handlebars" is a visual analog for a mustache and successor to the format -> "Two Whales Kissing" is another visual analog -> "Two Whales Kissing" for Ruby -> Rhales combines Ruby and Whales into a one-word name for our library).
- **Partials** via `{{> partial_name}}` map to other `.rue` files
- **Logic-free** templates maintain separation of concerns

### Data Section Behavior
- **JSON structure** with rhales interpolation for server variables
- **Automatic client hydration** - populates `window.data` based on `window` attribute
- **Type safety bridge** via `schema` attribute pointing to TypeScript definitions
- **Restricted scope** - only access to explicitly provided context

## Technical Architecture

### Parsing Pipeline
- **Prism** - Ruby expression parsing with proper semantics
- **Pattern Matching** - AST processing and template logic dispatch
- **Rhales** - Template rendering with interpolation

### Context Resolution
1. **Runtime context** - CSRF tokens, nonces, request metadata
2. **Business context** - User data, application state from route handlers
3. **Computed context** - Server-side transformations in `<logic>` section

## Integration Points

### Server Framework Integration
Route handlers provide business data to RSFC renderer:
```ruby
get '/dashboard' do
  rsfc :dashboard, data: { user: current_user, products: recent_products }
end
```

### Client Framework Handoff
Generated hydration script provides structured data to Vue/React:
```javascript
// Automatically generated from <data> section
window.data = { user_id: 123, is_authenticated: true };
```

## Decided Design Elements

✅ **File extension**: `.rue`
✅ **Required sections**: `<template>` + `<data>`
✅ **Template syntax**: Rhales
✅ **Data format**: JSON with server interpolation
✅ **Parsing approach**: Prism + Pattern Matching
✅ **Client hydration**: Automatic via `window` attribute

## Open Design Questions

❓ **Rack Integration Method**
- Middleware vs helper method approach
- Context provider pattern specifics
- CSRF/nonce integration strategy

❓ **Partial Resolution**
- Nested partial dependency handling
- Circular reference prevention
- Performance implications of file lookups

❓ **Development Experience**
- Syntax highlighting for `.rue` files
- Hot reload behavior during development
- Error reporting and debugging tools

❓ **Schema Integration**
- TypeScript definition generation from `<data>` sections
- Runtime validation vs compile-time checking
- Integration with existing Zod pipeline

❓ **State Management**
- Familia integration for stateful components
- Redis-backed component persistence patterns
- Real-time update mechanisms

❓ **Migration Strategy**
- Conversion tools from existing ERB/Mustache templates
- Incremental adoption pathway
- Backwards compatibility considerations

## Success Metrics

**Primary Goal**: Eliminate manual API design in server-to-SPA scenarios
**Developer Experience**: Faster development velocity through co-location
**Type Safety**: Reduced runtime errors via schema integration
**Performance**: Competitive with existing template engines

## Next Steps

1. **Prototype Rack integration** patterns
2. **Validate syntax highlighting** feasibility
3. **Test migration** from existing OTS templates
4. **Benchmark performance** vs current Mustache implementation

---

**Status**: Technical foundation validated, integration details in progress
