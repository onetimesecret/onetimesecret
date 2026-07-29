// src/apps/admin/components/domains/domainConfigTypes.ts

/**
 * Shared presentation types for the colonel domain-configs section family
 * ({@link DomainConfigsSection} and its extracted children). Lives in a plain
 * module because `<script setup>` blocks cannot export types.
 */

/**
 * Honest per-row lifecycle state for one config record. `missing` covers both
 * a truly absent record AND an `exists:true` entry whose serialized config
 * failed to hydrate (the parent's single `recordPresent` predicate decides).
 * `enabledNotReady` is the incoming-kind special case: enabled but without a
 * ready recipients configuration.
 */
export type DomainConfigStatus = 'missing' | 'disabled' | 'enabled' | 'enabledNotReady';

/** The two guarded actions that share the section's confirm dialog. */
export type DomainConfigAction = 'ensure' | 'delete';
