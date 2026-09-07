// src/plugins/core/globalErrorBoundary.ts

import { classifyError, errorGuards, type ApplicationError } from '@/schemas/errors';
import { captureException, isDiagnosticsEnabled } from '@/services/diagnostics.service';
import { loggingService } from '@/services/logging.service';
import { AsyncHandlerOptions } from '@/shared/composables/useAsyncHandler';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import type { VueComponentLike } from '@/types/ui/vue-internals';
import type { App, Plugin } from 'vue';

interface ErrorBoundaryOptions extends AsyncHandlerOptions {
  debug?: boolean;
}

/**
 * Extracts the Vue component name for Sentry context (#2966)
 * Works with both Options API ($options.name) and script setup ($.type.name/.__name)
 *
 * @param instance - Vue component instance (from error handler)
 * @returns Component name or 'unknown' if not extractable
 */
export function getComponentName(instance: unknown): string {
  if (!instance || typeof instance !== 'object') return 'unknown';
  const i = instance as VueComponentLike;
  // Options API: $options.name
  // Script setup: $.type.name or $.type.__name (Vue 3 internal component type)
  // Guard i.$ for edge cases (SSR hydration errors, corrupted instances)
  return i.$options?.name || i.$?.type?.name || i.$?.type?.__name || 'unknown';
}

/**
 * Optional jurisdiction/planid/role tags read from the bootstrap store,
 * omitting any that are not currently available.
 */
function optionalBootstrapTags(
  bootstrap: ReturnType<typeof useBootstrapStore>
): Record<string, unknown> {
  const tags: Record<string, unknown> = {};

  if (bootstrap.regions?.current_jurisdiction) {
    tags.jurisdiction = bootstrap.regions.current_jurisdiction;
  }
  if (bootstrap.organization?.planid) {
    tags.planid = bootstrap.organization.planid;
  }
  if (bootstrap.cust?.role) {
    tags.role = bootstrap.cust.role;
  }

  return tags;
}

interface ReportToSentryArgs {
  normalizedError: Error;
  classifiedError: ApplicationError;
  instance: unknown;
  info: string;
}

/**
 * Sends a classified error to Sentry via the diagnostics service, unless it
 * is human-facing — already shown to the user via `notify` in the caller, so
 * it is an expected outcome, not a defect. This is the same rule
 * useAsyncHandler.logTechnicalError applies; this handler is the OTHER place
 * an error can reach captureException, and it must apply it too (#4286).
 */
function reportToSentry({
  normalizedError,
  classifiedError,
  instance,
  info,
}: ReportToSentryArgs): void {
  if (!isDiagnosticsEnabled()) {
    console.debug('[GlobalErrorBoundary] Sentry not initialized');
    return;
  }
  if (errorGuards.isOfHumanInterest(classifiedError)) {
    console.debug('[GlobalErrorBoundary] Skipping Sentry capture for human-facing error');
    return;
  }

  console.debug('[GlobalErrorBoundary] Sending to Sentry');

  // Note: useBootstrapStore() is safe here because Pinia is installed before this plugin
  const context: Record<string, unknown> = {
    componentName: getComponentName(instance),
    componentInfo: info,
    errorType: classifiedError.type,
    errorSeverity: classifiedError.severity,
    ...optionalBootstrapTags(useBootstrapStore()),
  };

  captureException(normalizedError, context);
}

/**
 * Creates a Vue plugin that provides global error handling
 *
 * @param {ErrorBoundaryOptions} options - Configuration options
 * @returns {Plugin} Vue plugin instance
 *
 * @example
 * ```ts
 * const errorBoundary = createErrorBoundary({
 *   debug: true,
 *   notify: (msg, severity) => notifications.add(msg, severity)
 * });
 * app.use(errorBoundary);
 * ```
 */
export function createErrorBoundary(options: ErrorBoundaryOptions = {}): Plugin {
  return {
    install(app: App) {
      /**
       * Vue 3 global error handler
       *
       * @param error: The error that was thrown
       * @param instance: The component instance that triggered the error
       * @param info: A string containing information about where the error was caught
       *
       * @see https://vuejs.org/api/application#app-config-errorhandler
       */
      app.config.errorHandler = (error, instance, info) => {
        const normalizedError = error instanceof Error ? error : new Error(String(error));
        const classifiedError = classifyError(error);
        loggingService.error(normalizedError);

        // Only notify user for human-facing errors
        if (errorGuards.isOfHumanInterest(classifiedError) && options.notify) {
          options.notify(classifiedError.message, classifiedError.severity);
        }

        reportToSentry({ normalizedError, classifiedError, instance, info });

        if (options.debug) {
          loggingService.debug('[ErrorContext]', { instance, info });
        }
      };
    },
  };
}
