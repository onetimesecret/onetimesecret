# LLM-Optimized Test Cases

Intent-based test specifications for browser automation agents.

## Files

| File | Purpose |
|------|---------|
| `schema.yaml` | Field definitions and fixtures |
| `issue-2114-secret-context.yaml` | Example test cases |

## Example

```yaml
- id: OTS-2114-SC-001
  intent: Creator viewing their own secret sees ownership warning
  setup:
    auth: logged_in
    state: { has_created_secret: true }
  target: "{{secret_link}}"
  verify:
    - Yellow warning banner with "You created this secret"
    - Dashboard link visible (not signup CTA)
  priority: high
  covers: [useSecretContext, actorRole]
```

## Schema

See `schema.yaml` for full field definitions.

Required: `id`, `intent`, `setup`, `target`, `verify`, `priority`, `type`

## Converting from Qase

1. Extract ID and metadata
2. Write intent as one sentence
3. Convert preconditions to declarative `setup`
4. Collapse step tables into `verify` assertions
