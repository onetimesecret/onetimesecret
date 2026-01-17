// docs/test-plans/schema.ts

/**
 * LLM-Optimized Test Case Schema
 *
 * Intent-based test specifications for browser automation agents.
 * Agents infer navigation mechanics from goals - no step-by-step instructions needed.
 *
 * Key principles:
 * - Intent as a sentence: agent determines approach from goal
 * - Declarative setup: states preconditions, not procedures
 * - Verify as assertions: what to check, not how
 */

import { z } from 'zod/v4';

// -----------------------------------------------------------------------------
// Enums
// -----------------------------------------------------------------------------

/** Authentication state required for test setup */
export const AuthState = z.enum(['logged_in', 'logged_out', 'incognito']);

/** Action types the agent can perform */
export const ActionType = z.enum(['click', 'submit', 'navigate', 'wait', 'none']);

/** Assertion types for structured verification */
export const AssertionType = z.enum(['visible', 'hidden', 'contains', 'equals', 'exists']);

/** Test priority levels */
export const Priority = z.enum(['critical', 'high', 'medium', 'low']);

/** Defect severity if test fails */
export const Severity = z.enum(['blocker', 'major', 'minor', 'trivial']);

/** Test classification types */
export const TestType = z.enum([
  'functional',
  'ui',
  'error',
  'integration',
  'smoke',
  'edge',
  'accessibility',
  'security',
]);

// -----------------------------------------------------------------------------
// Fixtures & Setup
// -----------------------------------------------------------------------------

/** Data fixture to create before test */
export const Fixture = z.object({
  /** Fixture type: "secret", "team", "user", etc. */
  type: z.string(),
  /** Fixture properties */
  props: z.record(z.string(), z.unknown()).optional(),
  /** Variable name to capture for use in target/verify */
  capture_as: z.string().optional(),
  /** Account that creates this fixture */
  created_by: z.string().optional(),
});

/** Declarative state before test begins */
export const Setup = z.object({
  /** Authentication state required */
  auth: AuthState,
  /** Specific user type: "creator", "recipient", "admin" */
  user_type: z.string().optional(),
  /** Human-readable setup description */
  description: z.string().optional(),
  /** Preconditions as key-value pairs */
  state: z.record(z.string(), z.unknown()).optional(),
  /** Data fixtures to create */
  fixtures: z.array(Fixture).optional(),
});

// -----------------------------------------------------------------------------
// Actions & Assertions
// -----------------------------------------------------------------------------

/** Action to perform during test */
export const Action = z.object({
  /** Action type to perform */
  type: ActionType,
  /** CSS selector, text content, or descriptive element */
  element: z.string().optional(),
  /** Form data or action parameters */
  data: z.record(z.string(), z.unknown()).optional(),
});

/** Structured assertion with selector precision */
export const StructuredAssertion = z.object({
  /** CSS selector or accessibility query */
  selector: z.string(),
  /** Assertion type */
  assertion: AssertionType,
  /** Expected value for contains/equals */
  value: z.string().optional(),
});

/** Verification assertion - simple string or structured */
export const Assertion = z.union([z.string(), StructuredAssertion]);

// -----------------------------------------------------------------------------
// Skip Conditions
// -----------------------------------------------------------------------------

/** Conditions for skipping a test */
export const Skip = z.object({
  /** Why the test is skipped */
  reason: z.string(),
  /** Condition for skipping: "CI", "standalone_mode" */
  when: z.string().optional(),
});

// -----------------------------------------------------------------------------
// Test Case
// -----------------------------------------------------------------------------

/** Individual test case specification */
export const TestCase = z.object({
  /** Unique case identifier (e.g., "TC-SS-001") */
  id: z.string(),
  /** What behavior we verify - the agent's goal */
  intent: z.string(),

  /** Declarative state before test begins */
  setup: Setup,
  /** Target URL or navigation goal */
  target: z.string(),

  /** Action to perform (if not just observing) */
  action: Action.optional(),
  /** Observable outcomes to verify (min 1) */
  verify: z.array(Assertion).min(1),

  /** Test priority */
  priority: Priority,
  /** Defect severity if test fails */
  severity: Severity.optional(),
  /** Test classification */
  type: TestType,

  /** Code/features this test covers */
  covers: z.array(z.string()).optional(),
  /** Post-conditions to verify */
  postconditions: z.array(z.string()).optional(),
  /** Notes for human reviewers or agent context */
  notes: z.string().optional(),
  /** Skip conditions */
  skip: Skip.optional(),
});

// -----------------------------------------------------------------------------
// Suite
// -----------------------------------------------------------------------------

/** Test suite metadata */
export const Suite = z.object({
  /** Unique suite identifier (e.g., "scope-switcher-ux") */
  id: z.string(),
  /** Human-readable suite name */
  name: z.string(),
  /** Feature/component being tested */
  feature: z.string(),
  /** Link to GitHub issue */
  issue: z.url().optional(),
  /** Tags for categorization */
  tags: z.array(z.string()).optional(),
  /** Suite-level priority (inherited by tests without explicit priority) */
  priority: Priority.optional(),
  /** Execution notes for test agents (e.g., multi-context requirements) */
  notes: z.string().optional(),
});

// -----------------------------------------------------------------------------
// Definitions (reusable across tests via YAML anchors)
// -----------------------------------------------------------------------------

/** Reusable user definition */
export const UserDefinition = z.object({
  auth: AuthState,
  user_type: z.string().optional(),
  description: z.string().optional(),
  state: z.record(z.string(), z.unknown()).optional(),
});

/** Reusable fixture definition */
export const FixtureDefinition = z.object({
  type: z.string(),
  props: z.record(z.string(), z.unknown()).optional(),
});

/** Shared definitions for YAML anchors */
export const Definitions = z.object({
  users: z.record(z.string(), UserDefinition).optional(),
  fixtures: z.record(z.string(), FixtureDefinition).optional(),
});

// -----------------------------------------------------------------------------
// Complete Test File
// -----------------------------------------------------------------------------

/** Complete LLM test file structure */
export const LLMTestFile = z.object({
  suite: Suite,
  definitions: Definitions.optional(),
  tests: z.array(TestCase).min(1),
});

// -----------------------------------------------------------------------------
// Type exports
// -----------------------------------------------------------------------------

export type AuthState = z.infer<typeof AuthState>;
export type ActionType = z.infer<typeof ActionType>;
export type AssertionType = z.infer<typeof AssertionType>;
export type Priority = z.infer<typeof Priority>;
export type Severity = z.infer<typeof Severity>;
export type TestType = z.infer<typeof TestType>;
export type Fixture = z.infer<typeof Fixture>;
export type Setup = z.infer<typeof Setup>;
export type Action = z.infer<typeof Action>;
export type StructuredAssertion = z.infer<typeof StructuredAssertion>;
export type Assertion = z.infer<typeof Assertion>;
export type Skip = z.infer<typeof Skip>;
export type TestCase = z.infer<typeof TestCase>;
export type Suite = z.infer<typeof Suite>;
export type Definitions = z.infer<typeof Definitions>;
export type LLMTestFile = z.infer<typeof LLMTestFile>;
