// src/tests/composables/useAuthOverrideState.spec.ts
//
// Pins the badge-driver invariant for the shared auth-override display state
// (ADR-024, used by both useSigninConfig and useSignupConfig):
//
//   isWorkspaceDefault is driven by record.enabled ONLY — never by
//   details.effective_enabled.
//
// This independence is what kept the #3814 resolver change (unconfigured
// custom domains now resolve effective_enabled: false) from breaking the
// "Workspace default" badge. The full cross-product below makes any future
// coupling of the badge to effective_enabled an immediate failure.

import {
  asExplicitOverride,
  createAuthOverrideState,
} from '@/shared/composables/useAuthOverrideState';
import { describe, expect, it } from 'vitest';
import { ref } from 'vue';

import type { AuthOverrideDetails } from '@/shared/composables/useAuthOverrideState';

type TestRecord = { enabled: boolean };

function makeState(record: TestRecord | null, details: AuthOverrideDetails | null) {
  return createAuthOverrideState(ref(record), ref(details));
}

describe('createAuthOverrideState', () => {
  describe('isWorkspaceDefault is driven by record.enabled, not effective_enabled (#3814 invariant)', () => {
    it('record.enabled true → NOT workspace default, even with effective_enabled false', () => {
      // Pinned domain whose resolver output is off (e.g. explicit
      // signin_enabled: false override): still explicitly configured.
      const state = makeState(
        { enabled: true },
        { global_enabled: true, effective_enabled: false }
      );

      expect(state.isWorkspaceDefault.value).toBe(false);
      expect(state.isExplicitlyConfigured.value).toBe(true);
    });

    it('record.enabled true → NOT workspace default with effective_enabled true', () => {
      const state = makeState({ enabled: true }, { global_enabled: true, effective_enabled: true });

      expect(state.isWorkspaceDefault.value).toBe(false);
      expect(state.isExplicitlyConfigured.value).toBe(true);
    });

    it('record null → workspace default, even with effective_enabled true (SSO-only tenant carve-out)', () => {
      // #3814: an unconfigured SSO-only tenant resolves effective_enabled
      // true, but it is still following workspace defaults — no pin exists.
      const state = makeState(null, { global_enabled: true, effective_enabled: true });

      expect(state.isWorkspaceDefault.value).toBe(true);
      expect(state.isExplicitlyConfigured.value).toBe(false);
    });

    it('record null → workspace default with effective_enabled false', () => {
      const state = makeState(null, { global_enabled: true, effective_enabled: false });

      expect(state.isWorkspaceDefault.value).toBe(true);
      expect(state.isExplicitlyConfigured.value).toBe(false);
    });

    it('legacy record with enabled false → workspace default, regardless of effective_enabled', () => {
      // The resolver treats an enabled=false record like no record at all.
      const offEffective = makeState(
        { enabled: false },
        { global_enabled: true, effective_enabled: false }
      );
      const onEffective = makeState(
        { enabled: false },
        { global_enabled: true, effective_enabled: true }
      );

      expect(offEffective.isWorkspaceDefault.value).toBe(true);
      expect(onEffective.isWorkspaceDefault.value).toBe(true);
    });

    it('record null and details null (nothing loaded) → workspace default', () => {
      const state = makeState(null, null);

      expect(state.isWorkspaceDefault.value).toBe(true);
      expect(state.isExplicitlyConfigured.value).toBe(false);
    });
  });

  describe('globalEnabled / effectiveEnabled / isGloballyDisabled', () => {
    it('surface the details verbatim; null until details load', () => {
      const state = makeState(null, null);
      expect(state.globalEnabled.value).toBeNull();
      expect(state.effectiveEnabled.value).toBeNull();
      // Null global is "unknown", not "disabled".
      expect(state.isGloballyDisabled.value).toBe(false);

      const loaded = makeState(null, { global_enabled: false, effective_enabled: false });
      expect(loaded.globalEnabled.value).toBe(false);
      expect(loaded.effectiveEnabled.value).toBe(false);
      expect(loaded.isGloballyDisabled.value).toBe(true);
    });

    it('tracks record/details ref changes reactively', () => {
      const record = ref<TestRecord | null>(null);
      const details = ref<AuthOverrideDetails | null>(null);
      const state = createAuthOverrideState(record, details);

      expect(state.isWorkspaceDefault.value).toBe(true);

      record.value = { enabled: true };
      details.value = { global_enabled: true, effective_enabled: true };

      expect(state.isWorkspaceDefault.value).toBe(false);
      expect(state.effectiveEnabled.value).toBe(true);
    });
  });

  describe('asExplicitOverride', () => {
    it('forces enabled: true onto any payload (the writes-materialize chokepoint)', () => {
      expect(asExplicitOverride({ signin_enabled: false, enabled: false })).toEqual({
        signin_enabled: false,
        enabled: true,
      });
      expect(asExplicitOverride({})).toEqual({ enabled: true });
    });
  });
});
