// src/plugins/core/globalErrorBoundary.ts

import { AsyncHandlerOptions } from '@/shared/composables/useAsyncHandler';
import { classifyError, errorGuards } from '@/schemas/errors';
import { captureException, isDiagnosticsEnabled } from '@/services/diagnostics.service';
import { loggingService } from '@/services/logging.service';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
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
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const i = instance as any;
  // Options API: $options.name
  // Script setup: $.type.name or $.type.__name (Vue 3 internal component type)
  // Guard i.$ for edge cases (SSR hydration errors, corrupted instances)
  return i.$options?.name || i.$?.type?.name || i.$?.type?.__name || 'unknown';
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

        // Send to Sentry via diagnostics service
        if (isDiagnosticsEnabled()) {
          console.debug('[GlobalErrorBoundary] Sending to Sentry');

          // Extract searchable tags from bootstrap store
          // Note: useBootstrapStore() is safe here because Pinia is installed before this plugin
          const bootstrap = useBootstrapStore();
          const context: Record<string, unknown> = {
            componentName: getComponentName(instance),
            componentInfo: info,
            errorType: classifiedError.type,
            errorSeverity: classifiedError.severity,
          };

          // Add jurisdiction if regions are configured (optional field)
          if (bootstrap.regions?.current_jurisdiction) {
            context.jurisdiction = bootstrap.regions.current_jurisdiction;
          }

          // Add planid from organization if present (organization is optional)
          if (bootstrap.organization?.planid) {
            context.planid = bootstrap.organization.planid;
          }

          // Add role from customer if present (cust is nullable)
          if (bootstrap.cust?.role) {
            context.role = bootstrap.cust.role;
          }

          captureException(normalizedError, context);
        } else {
          console.debug('[GlobalErrorBoundary] Sentry not initialized');
        }

        if (options.debug) {
          loggingService.debug('[ErrorContext]', { instance, info });
        }
      };
    },
  };
}
