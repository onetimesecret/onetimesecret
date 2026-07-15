// src/apps/admin/composables/useAdminMutation.ts

import { ref, type Ref } from 'vue';

import { classifyError } from '@/schemas/errors';

export interface UseAdminMutation<TArgs extends unknown[]> {
  /** True while the mutation is in flight. Wire to AdminConfirmDialog `:loading`. */
  loading: Ref<boolean>;
  /**
   * The last failure message (already user-facing), or null. Wire to
   * AdminConfirmDialog `:error` so a failed action shows its reason IN the
   * dialog and the operator can retry or cancel.
   */
  error: Ref<string | null>;
  /**
   * Run the mutation. Resolves `true` on success and `false` on failure (the
   * message is captured in {@link error}) — it never throws, so the caller can
   * branch on the boolean to close the dialog + refresh only on success.
   */
  run: (...args: TArgs) => Promise<boolean>;
  /** Clear loading + error (e.g. when the dialog is cancelled/re-opened). */
  reset: () => void;
}

/**
 * The reusable half of the D4 guarded-mutation flow (CONTRACT 3).
 *
 * Wraps a single admin mutation (a POST/DELETE against a Slice-2 colonel
 * endpoint) with the two pieces every guarded action needs: an in-flight
 * `loading` flag and a user-facing `error` string, both shaped to drop straight
 * into {@link AdminConfirmDialog}'s frozen `:loading` / `:error` props. The
 * dialog itself owns the typed-confirmation gate; this owns the request.
 *
 * Deliberately does NOT own the dialog's open/close state (that is view UI
 * state) and does NOT emit audit events (audit is recorded server-side by the
 * operation — CONTRACT 3). Error messages come from the shared `classifyError`,
 * which surfaces the backend's user-facing `error` field.
 *
 * @example
 * const purge = useAdminMutation((id: string) => $api.delete(`/api/colonel/users/${id}`));
 * // in the dialog's @confirm handler:
 * if (await purge.run(extid)) { open.value = false; notify(); resource.refresh(); }
 */
export function useAdminMutation<TArgs extends unknown[]>(
  perform: (...args: TArgs) => Promise<unknown>
): UseAdminMutation<TArgs> {
  const loading = ref(false);
  const error = ref<string | null>(null);

  async function run(...args: TArgs): Promise<boolean> {
    loading.value = true;
    error.value = null;
    try {
      await perform(...args);
      return true;
    } catch (err) {
      // classifyError extracts the backend's user-facing `error` message for
      // 4xx (form/validation) and a safe generic for the rest.
      error.value = classifyError(err).message;
      return false;
    } finally {
      loading.value = false;
    }
  }

  function reset(): void {
    loading.value = false;
    error.value = null;
  }

  return { loading, error, run, reset };
}
