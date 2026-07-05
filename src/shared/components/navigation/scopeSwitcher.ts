// src/shared/components/navigation/scopeSwitcher.ts

/**
 * Shared contract for the featurized <ScopeSwitcher> engine.
 *
 * The engine renders a HeadlessUI Menu dropdown for switching between "scopes"
 * (organizations, domains, …) without knowing what a scope actually is. Each
 * concrete switcher (OrganizationScopeSwitcher, DomainContextSwitcher) maps its
 * domain objects into this normalized item shape and feeds it to the engine.
 */

/**
 * A single selectable row in a scope switcher dropdown.
 *
 * `id` is the stable identity the engine echoes back through the `select` and
 * `open-settings` emits; the adapter resolves it back to its own object. Use a
 * value that is unique and stable per row (an extid, or a sentinel like
 * `'canonical'` for the domain that has none).
 */
export interface ScopeSwitcherItem {
  /** Stable, unique key echoed back via `select` / `open-settings`. */
  id: string;
  /** Human-readable row label. */
  label: string;
  /** Whether this row is the currently active scope (checkmark + emphasis). */
  isCurrent: boolean;
  /** When true the row is non-interactive (e.g. canonical domain with nowhere to go). */
  disabled?: boolean;
  /** Tooltip explaining why the row is disabled. */
  disabledReason?: string;
  /**
   * Whether this row exposes the hover "settings" (gear) affordance. The adapter
   * bakes any role/entitlement gating into this flag, so the engine only has to
   * check the boolean.
   */
  hasSettings?: boolean;
}
