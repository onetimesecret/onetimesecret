# LLM-Optimized Test Cases

Intent-based test specifications for browser automation agents.

## Design Rationale

- **Intent as a sentence** - agent determines approach from goal
- **Declarative setup** - states preconditions (`auth: logged_in`) rather than procedural steps
- **Verify as assertions** - what to check, not how to check it

LLM agents infer mechanics from intent, so step-by-step instructions are unnecessary.

## Agent Execution Rules

1. **ALL tests must be executed** - do not skip tests
2. **Fixtures are declarative** - you CREATE the state dynamically during test execution
3. **No pre-built test data** - create accounts, invitations, secrets as needed
4. **Valid skip reasons** - only specific technical blockers (e.g., "MFA requires TOTP app not available")
5. **Invalid skip reasons** - "time constraints", "missing fixtures", "would need to create data"

## Files

- `schema.ts` - Zod v4 schema (source of truth for field types)
- `issue-{number}-{feature}.yaml` - Test cases linked to GitHub issues

## Running

Use @browser-tester which has access to chrome devtools MCP and serena tools.

Before you start:
- Run Caddy, use TLS certs
- Clean mail from Mailpit inbox

Example prompt:

> Use @browser-tester to run this testplan. Use https://dev.onetime.dev and
> https://dev.onetime.dev:8025/ for mailpit UI. When dealing with accounts,
> the email addresses must use a valid domain that will pass Truemail checks.


## Converting from Qase

1. Extract ID and metadata
2. Write intent as one sentence
3. Convert preconditions to declarative `setup`
4. Collapse step tables into `verify` assertions
