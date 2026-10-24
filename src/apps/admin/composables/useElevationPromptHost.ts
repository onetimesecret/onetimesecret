// src/apps/admin/composables/useElevationPromptHost.ts

import { computed, onScopeDispose, ref, watch, type ComputedRef } from 'vue';

import { cancelElevationPrompt, elevationPromptOpen } from './useColonelElevation';

/**
 * Where the console's ONE step-up prompt (ElevationPrompt) renders.
 *
 * headlessui treats a Dialog as nested only when it is rendered inside the
 * parent Dialog's component subtree (the same rule behind #4732's confirm
 * dialogs inside the drawer). A prompt mounted as a SIBLING of an open drawer
 * or confirm dialog is "outside" to it: a click into the prompt closes that
 * dialog (and the click's default is prevented, so the prompt's submit never
 * fires), Escape closes that dialog instead of the prompt, and anything the
 * prompt renders inside #app is inert.
 *
 * So the prompt renders inside the top-most open admin kit dialog, and in
 * AdminLayout only while none is open. Exactly one instance is mounted at a
 * time. Each kit dialog registers while it is open; the most recently opened
 * one is the host.
 *
 * Invariant: the stack never changes under an open prompt (a change would
 * remount the prompt mid-entry). A top host that closes or unmounts under the
 * open prompt cancels it first; a caller that unmounts cancels its request; and
 * openers of a shared dialog are serialised by their views.
 */
const hosts = ref<symbol[]>([]);

function release(token: symbol): void {
  const index = hosts.value.indexOf(token);
  if (index !== -1) hosts.value.splice(index, 1);
}

/**
 * A host leaving the stack. The `open` prop flips false before headlessui's
 * leave transition ends, so the slot content (and the caller waiting on the
 * prompt) is disposed only ~200 ms later; releasing the token at once would
 * hand the still-open prompt to the layout meanwhile. The top host cancels the
 * prompt before it goes.
 */
function releaseHost(token: symbol): void {
  if (hosts.value[hosts.value.length - 1] === token && elevationPromptOpen.value) {
    cancelElevationPrompt();
  }
  release(token);
}

export interface ElevationPromptHost {
  /** True while this dialog is the top-most open one: render the prompt inside it. */
  hostsPrompt: ComputedRef<boolean>;
  /**
   * True while the prompt is open. The dialog ignores its headlessui `close`
   * (outside click, Escape) then: a gesture aimed at the prompt must not
   * dismiss the dialog the operator is about to act in.
   */
  promptOpen: ComputedRef<boolean>;
}

/**
 * For an admin kit dialog. Call from `setup`; `isOpen` reads the dialog's
 * `open` prop.
 */
export function useElevationPromptHost(isOpen: () => boolean): ElevationPromptHost {
  const token = Symbol('elevation-prompt-host');

  watch(
    isOpen,
    (open) => {
      releaseHost(token);
      if (open) hosts.value.push(token);
    },
    { immediate: true }
  );
  onScopeDispose(() => releaseHost(token));

  const hostsPrompt = computed(() => hosts.value[hosts.value.length - 1] === token);

  // A guard for the invariant above, not a mechanism: nothing here recovers
  // from the transition, it only makes one visible in development.
  if (import.meta.env.DEV) {
    watch(hostsPrompt, () => {
      if (!elevationPromptOpen.value) return;
      console.warn(
        '[useElevationPromptHost] the host stack changed while the step-up prompt is open; the prompt remounts. A caller that unmounts must cancel its request.'
      );
    });
  }

  return {
    hostsPrompt,
    promptOpen: elevationPromptOpen,
  };
}

/** For AdminLayout: host the prompt while no admin kit dialog is open. */
export function useLayoutElevationPromptHost(): ComputedRef<boolean> {
  return computed(() => hosts.value.length === 0);
}

/** Test seam: forget every registered host. */
export function __resetElevationPromptHosts(): void {
  hosts.value = [];
}
