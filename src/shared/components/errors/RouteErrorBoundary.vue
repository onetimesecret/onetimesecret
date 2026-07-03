<!-- src/shared/components/errors/RouteErrorBoundary.vue -->

<!--
  Route-level render error boundary.

  WHY THIS EXISTS
  ---------------
  Vue's `app.config.errorHandler` (wired in src/plugins/core/globalErrorBoundary.ts)
  only *logs* render/setup errors to Sentry — it renders no fallback. When a
  route component throws synchronously during setup()/render, Vue tears that
  subtree down and the `<router-view>` slot is left empty. With no fallback,
  the user sees a silent BLANK PAGE instead of an error.

  This boundary wraps the active route component and, via `onErrorCaptured`,
  swaps a thrown subtree for a visible "something went wrong" panel with a
  reload affordance — so a render failure is never a blank screen.

  It reports the error to Sentry itself (mirroring the global handler) and
  returns `false` from `onErrorCaptured` to stop propagation — the boundary
  has fully handled the failure by rendering a fallback, so there is nothing
  left for `app.config.errorHandler` to do, and double-reporting the same
  error is avoided.

  The boundary resets whenever the route changes (`resetKey`), so navigating
  away from a broken route recovers without a hard reload.
-->

<script setup lang="ts">
  import { captureException, isDiagnosticsEnabled } from '@/services/diagnostics.service';
  import { loggingService } from '@/services/logging.service';
  import { onErrorCaptured, ref, watch } from 'vue';

  interface Props {
    /**
     * Changes on every navigation (pass `$route.fullPath`). Watching it clears
     * a captured error so a subsequent, healthy route renders normally.
     */
    resetKey?: string;
  }

  const props = defineProps<Props>();

  const caughtError = ref<Error | null>(null);
  const isDev = import.meta.env.DEV;

  onErrorCaptured((err, _instance, info) => {
    // Record the error so the template swaps in the fallback panel.
    const normalized = err instanceof Error ? err : new Error(String(err));
    caughtError.value = normalized;

    // Best-effort log + Sentry report; never let reporting throw out of the
    // hook (the boundary must not fail while handling a failure).
    try {
      loggingService.error(normalized);
      if (isDiagnosticsEnabled()) {
        captureException(normalized, { boundary: 'RouteErrorBoundary', componentInfo: info });
      }
    } catch {
      /* no-op */
    }

    // Return false: the boundary has handled the error by rendering a
    // fallback, so stop propagation to app.config.errorHandler (avoids a
    // duplicate Sentry event for the same failure).
    return false;
  });

  // Recover on navigation: a new route gets a clean render.
  watch(
    () => props.resetKey,
    () => {
      caughtError.value = null;
    }
  );

  const reload = () => {
    window.location.reload();
  };

  const goHome = () => {
    // Hard navigation (not router.push) so we leave the broken component tree
    // entirely rather than risk re-entering the same failing route via the SPA.
    window.location.assign('/');
  };
</script>

<template>
  <div
    v-if="caughtError"
    role="alert"
    data-testid="route-error-boundary"
    class="mx-auto flex min-h-[60vh] max-w-md flex-col items-center justify-center px-4 text-center">
    <svg
      class="size-12 text-amber-500 dark:text-amber-400"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      aria-hidden="true">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
    </svg>

    <!--
      Fallback copy is intentionally hardcoded (not i18n-wrapped). This is a
      last-resort render boundary: the failure it catches may itself be a
      broken i18n/bootstrap state, so calling t() here risks throwing while
      handling an error. Plain English keeps the panel dependency-free and
      guaranteed to render.
    -->
    <h1 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">Something went wrong</h1>
    <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
      This page couldn’t be displayed. Reloading usually fixes it.
    </p>

    <div class="mt-6 flex flex-wrap items-center justify-center gap-3">
      <button
        type="button"
        data-testid="route-error-reload"
        @click="reload"
        class="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-brand-500 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:bg-brand-500 dark:hover:bg-brand-400">
        Reload page
      </button>
      <button
        type="button"
        data-testid="route-error-home"
        @click="goHome"
        class="rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600">
        Go to homepage
      </button>
    </div>

    <!-- Error detail: development only, to avoid surfacing internals in prod.
         caughtError is always truthy inside the outer v-if, so isDev alone gates this. -->
    <pre
      v-if="isDev"
      class="mt-6 max-w-full overflow-x-auto rounded-md bg-gray-100 p-3 text-left text-xs text-red-700 dark:bg-gray-800 dark:text-red-300"
      >{{ caughtError.message }}</pre
    >
  </div>

  <slot v-else></slot>
</template>
