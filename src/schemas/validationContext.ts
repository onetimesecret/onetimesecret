// src/schemas/validationContext.ts

let suppressionDepth = 0;

/** Whether schema transforms may emit application diagnostics. */
export function schemaDiagnosticsEnabled(): boolean {
  return suppressionDepth === 0;
}

/**
 * Suppress schema diagnostics during a synchronous check, including nested checks.
 * State is restored on return or throw. Synchronous only: a returned Promise is
 * not awaited, so work after an await runs with the previous diagnostics state.
 * This gates participating schema side effects, not custom validation messages.
 */
export function withoutSchemaDiagnostics<T>(check: () => T): T {
  suppressionDepth++;
  try {
    return check();
  } finally {
    suppressionDepth--;
  }
}
