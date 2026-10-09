// src/schemas/check.ts

import type { z } from 'zod';

import { responseSchemas as incoming } from './api/incoming/responses/registry';
import { responseSchemas as internal } from './api/internal/responses/registry';
import { responseSchemas as v1 } from './api/v1/responses/registry';
import { responseSchemas as v2 } from './api/v2/responses/registry';
import { responseSchemas as v3 } from './api/v3/responses/registry';
import { schemaRegistry } from './registry';

type Path = readonly PropertyKey[];

const registries: Record<string, Record<string, z.ZodType>> = { v1, v2, v3, incoming, internal };

export function allSchemas(): Map<string, z.ZodType> {
  const map = new Map<string, z.ZodType>();
  for (const [prefix, registry] of Object.entries(registries)) {
    for (const [key, schema] of Object.entries(registry)) map.set(`${prefix}.${key}`, schema);
  }
  for (const [key, schema] of Object.entries(schemaRegistry)) map.set(key, schema as z.ZodType);
  return map;
}

// =============================================================================
// Paths and values
// =============================================================================

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' && value !== null && Object.getPrototypeOf(value) === Object.prototype
  );
}

/** Exact path, used to match issues to input positions. */
function pathKey(path: Path): string {
  return JSON.stringify(path.map(String));
}

/** Display path. Array indices collapse to [*] so list items group together. */
function formatPath(path: Path): string {
  let out = '';
  for (const seg of path) {
    if (typeof seg === 'number') out += '[*]';
    else out += out ? `.${String(seg)}` : String(seg);
  }
  return out || '(root)';
}

function valueAt(input: unknown, path: Path): unknown {
  let current = input;
  for (const seg of path) {
    if (current === null || typeof current !== 'object') return undefined;
    current = (current as Record<PropertyKey, unknown>)[seg];
  }
  return current;
}

/** Type and size of a value, never its content. */
function describe(value: unknown): string {
  if (value === undefined) return 'missing';
  if (value === null) return 'null';
  if (typeof value === 'string') return `string(${value.length})`;
  if (Array.isArray(value)) return `array(${value.length})`;
  if (typeof value === 'object') return `object(${Object.keys(value).length} keys)`;
  return typeof value;
}

function reveal(value: unknown): string {
  const json = JSON.stringify(value) ?? String(value);
  return json.length > 80 ? `${json.slice(0, 77)}...` : json;
}

// =============================================================================
// Schema introspection
// =============================================================================

interface Def {
  type: string;
  innerType?: z.core.$ZodType;
  in?: z.core.$ZodType;
  out?: z.core.$ZodType;
  getter?: () => z.core.$ZodType;
  shape?: Record<string, z.core.$ZodType>;
  /** Schema for object keys outside `shape`: unknown when loose, never when strict. */
  catchall?: z.core.$ZodType;
  element?: z.core.$ZodType;
}

function defOf(schema: z.core.$ZodType): Def {
  return schema._zod.def as unknown as Def;
}

/**
 * Strip wrappers (optional, nullable, default, lazy, transform pipes) down to
 * the schema that checks the input. `z.preprocess` is a pipe whose input side
 * is a transform, so its output side is the one that describes the shape.
 */
function unwrap(schema: z.core.$ZodType): z.core.$ZodType {
  let current = schema;
  for (let depth = 0; depth < 32; depth++) {
    const def = defOf(current);
    let next: z.core.$ZodType | undefined;
    if (def.innerType) next = def.innerType;
    else if (def.type === 'lazy') next = def.getter?.();
    else if (def.type === 'pipe' && def.in) {
      next = defOf(unwrap(def.in)).type === 'transform' ? def.out : def.in;
    }
    if (!next) return current;
    current = next;
  }
  return current;
}

interface Coverage {
  /** Leaf positions in the input that the schema declares and accepted. */
  matched: number;
  /** Input keys the schema does not declare, by display path. */
  undeclared: Map<string, Path>;
  /** Input keys a loose object keeps without checking, by display path. */
  unchecked: Map<string, Path>;
}

/**
 * How an object treats keys outside its shape. Plain objects strip them and
 * strict ones reject them (`never`); both leave them undeclared. A loose
 * object (`unknown`/`any`) keeps them unchecked, so they earn no credit and
 * their values are not walked. Any other catchall checks them like fields.
 */
function extraKeys(def: Def): 'undeclared' | 'unchecked' | 'checked' {
  if (!def.catchall) return 'undeclared';
  const type = defOf(unwrap(def.catchall)).type;
  if (type === 'never') return 'undeclared';
  return type === 'unknown' || type === 'any' ? 'unchecked' : 'checked';
}

function coverage(schema: z.ZodType, input: unknown, issuePaths: Set<string>): Coverage {
  const result: Coverage = { matched: 0, undeclared: new Map(), unchecked: new Map() };
  const visit = (node: z.core.$ZodType, value: unknown, path: Path): void => {
    const def = defOf(unwrap(node));
    if (def.type === 'object' && def.shape && isPlainObject(value)) {
      const extra = extraKeys(def);
      for (const [key, child] of Object.entries(value)) {
        const childPath = [...path, key];
        // Own keys only: `constructor` or `__proto__` must not resolve to
        // Object.prototype members.
        if (Object.hasOwn(def.shape, key)) visit(def.shape[key], child, childPath);
        else if (extra === 'checked') visit(def.catchall!, child, childPath);
        else result[extra].set(formatPath(childPath), childPath);
      }
    } else if (def.type === 'array' && def.element && Array.isArray(value)) {
      value.forEach((item, i) => visit(def.element!, item, [...path, i]));
    } else if (!issuePaths.has(pathKey(path))) {
      result.matched++;
    }
  };
  visit(schema, input, []);
  return result;
}

// =============================================================================
// Reporting
// =============================================================================

export interface Group {
  missing: Map<string, number>;
  problems: Map<string, number>;
  undeclared: Set<string>;
}

export interface CheckResult {
  success: boolean;
  issueCount: number;
  groups: Map<string, Group>;
  undeclared: string[];
  /** Keys a loose object keeps without checking. Not grouped: they are not problems. */
  unchecked: string[];
}

export function counted(map: Map<string, number>): string[] {
  return [...map].map(([text, n]) => (n > 1 ? `${text} (x${n})` : text));
}

function explain(issue: z.core.$ZodIssue, value: unknown, showValues: boolean): string {
  const got = showValues ? `${describe(value)} ${reveal(value)}` : describe(value);
  switch (issue.code) {
    case 'invalid_type':
      return `expected ${issue.expected}, got ${got}`;
    case 'invalid_value':
      return `expected ${issue.values.map((v) => reveal(v)).join(' | ')}, got ${got}`;
    default:
      return `${issue.message} (input: ${got})`;
  }
}

interface Report {
  input: unknown;
  issues: z.core.$ZodIssue[];
  undeclared: Iterable<Path>;
}

/** Issues and undeclared keys, grouped by the object that holds them. */
function groupIssues(
  { input, issues, undeclared }: Report,
  showValues: boolean
): Map<string, Group> {
  const groups = new Map<string, Group>();
  const groupFor = (path: Path): Group => {
    const key = formatPath(path);
    let group = groups.get(key);
    if (!group) {
      group = { missing: new Map(), problems: new Map(), undeclared: new Set() };
      groups.set(key, group);
    }
    return group;
  };
  const bump = (map: Map<string, number>, text: string) => map.set(text, (map.get(text) ?? 0) + 1);

  for (const issue of issues) {
    const leaf = issue.path.length > 0 ? formatPath(issue.path.slice(-1)) : '(root)';
    const value = valueAt(input, issue.path);
    const group = groupFor(issue.path.slice(0, -1));
    if (value === undefined && issue.path.length > 0) bump(group.missing, leaf);
    else bump(group.problems, `${leaf}: ${explain(issue, value, showValues)}`);
  }

  for (const path of undeclared) {
    groupFor(path.slice(0, -1)).undeclared.add(formatPath(path.slice(-1)));
  }
  return groups;
}

/**
 * Check the original input without returning parsed data or raw Zod issues.
 * Values are hidden by default; key names and schema-provided messages remain
 * visible. Custom messages must not embed input values when reports are shared.
 * Parsing exceptions propagate so callers can handle throwing transforms or
 * async refinements according to their environment.
 */
export function checkPayload(schema: z.ZodType, input: unknown, showValues = false): CheckResult {
  const result = schema.safeParse(input);
  const issues = result.success ? [] : result.error.issues;
  const cov = coverage(schema, input, new Set(issues.map((issue) => pathKey(issue.path))));
  return {
    success: result.success,
    issueCount: issues.length,
    groups: groupIssues({ input, issues, undeclared: cov.undeclared.values() }, showValues),
    undeclared: [...cov.undeclared.keys()],
    unchecked: [...cov.unchecked.keys()],
  };
}

export interface Candidate {
  name: string;
  issues: number;
  matched: number;
  undeclared: number;
}

/** Rank API schemas by how much of the input they recognise. */
export function closest(input: unknown, schemas: Map<string, z.ZodType>, limit = 3): Candidate[] {
  const candidates: Candidate[] = [];
  const seen = new Set<z.ZodType>();
  for (const [name, schema] of schemas) {
    // Registry aliases (api/v3/secret-response is v3.secret) would rank twice.
    if (name.startsWith('config/') || seen.has(schema)) continue;
    seen.add(schema);
    let issues: z.core.$ZodIssue[];
    try {
      const result = schema.safeParse(input);
      issues = result.success ? [] : result.error.issues;
    } catch {
      continue; // async refinements or a transform that throws
    }
    const cov = coverage(schema, input, new Set(issues.map((issue) => pathKey(issue.path))));
    candidates.push({
      name,
      issues: issues.length,
      matched: cov.matched,
      undeclared: cov.undeclared.size,
    });
  }
  return candidates
    .sort((a, b) => b.matched - a.matched || a.issues - b.issues || a.undeclared - b.undeclared)
    .slice(0, limit);
}
