# Architecture Overview

Onetime Secret is a Ruby application with a Vue 3 frontend. This page is an
entry point to the architecture notes below.

## Architecture Map

| Topic | Use this document when you need to understand… |
| --- | --- |
| [Accounts and Workspaces](./accounts-and-workspaces.md) | account origin, organization membership, and workspace behavior |
| [Authentication Strategies](./authentication-strategies.md) | route authentication and the session contract |
| [Audit Logging](./audit-logging.md) | Secret Activity, Security Events, and the colonel operator trail |
| [Guest Routes](./guest-routes.md) | anonymous V3 secret API routes and their configuration |
| [Organization Authorization Discriminators](./org-authorization-discriminators.md) | default organizations, domain-scoped memberships, and organization selection |
| [Terminology](./terminology.md) | project-specific framework and deployment terms |

## System Components

**Ruby backend**
- Shared logic and authorization helpers live in `lib/onetime/logic/`.
- API applications keep endpoint-specific logic under `apps/api/<version>/logic/`
  and declare routes in the corresponding `apps/api/<version>/routes.txt`.
- Logic classes commonly validate in `raise_concerns`, transform or perform work
  in `process`, and return response data through `success_data`.

**Vue 3 frontend** (`src/`)
- TypeScript and Zod validate API data at the frontend boundary.
- Schemas, services, stores, composables, and components form the main layers.
- `src/schemas/README.md` describes the schema and wire-format boundary in more
  detail.

## Architecture Principles

### Layered Frontend Design
Each layer has a distinct responsibility:
- **Schemas**: Data structures and validation
- **Services**: API communication
- **Stores**: State management
- **Composables**: Reusable business logic
- **Components**: UI presentation

### Type Safety Strategy
- Schemas define types that flow through all layers
- Runtime validation at API boundaries
- Compile-time checking throughout the stack

### Error Handling
- Vue error boundaries for component errors
- Explicit handling for async operations
- Result types for expected failures
- Clear separation between recoverable and system errors

## Current Challenges

**Type Complexity**: Multiple transformation layers in frontend create maintenance overhead. The codebase currently over-engineers type safety at the cost of development velocity.

**API Integration**: Inconsistent serialization between Ruby and TypeScript requires complex frontend transformations.

**Error Handling**: Need consistent patterns across layers for both expected business errors and unexpected system failures.
