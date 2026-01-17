# LLM-Optimized Test Cases

Intent-based test specifications for browser automation agents.

## Design Rationale

- **Intent as a sentence** - agent determines approach from goal
- **Declarative setup** - states preconditions (`auth: logged_in`) rather than procedural steps
- **Verify as assertions** - what to check, not how to check it

LLM agents infer mechanics from intent, so step-by-step instructions are unnecessary.

## Files

- `schema.ts` - Zod v4 schema (source of truth for field types)
- `issue-{number}-{feature}.yaml` - Test cases linked to GitHub issues

## Running

Use @browser-tester which has access to chrome devtools MCP and serena tools.

## Converting from Qase

1. Extract ID and metadata
2. Write intent as one sentence
3. Convert preconditions to declarative `setup`
4. Collapse step tables into `verify` assertions
