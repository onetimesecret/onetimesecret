// src/tests/utils/appLogs.ts

import { loggingService } from '@/services/logging.service';
import { onTestFinished, vi } from 'vitest';

/**
 * Takes over loggingService.warn and loggingService.error for a spec whose
 * tests drive failure paths on purpose. The calls are recorded instead of
 * printed, so src/tests/setup-console-guard.ts never sees them: assert on
 * the ones the test is about.
 *
 *   let logs: AppLogs;
 *   beforeEach(() => { logs = captureAppLogs(); });
 *   ...
 *   expect(logs.error).toHaveBeenCalledWith(expect.objectContaining({ type: 'technical' }));
 *
 * Call it from a test or a beforeEach. The logger is restored when the test
 * finishes, whatever the spec's own teardown does.
 */
export function captureAppLogs() {
  const logs = {
    warn: vi.spyOn(loggingService, 'warn').mockImplementation(() => {}),
    error: vi.spyOn(loggingService, 'error').mockImplementation(() => {}),
  };
  onTestFinished(() => {
    logs.warn.mockRestore();
    logs.error.mockRestore();
  });
  return logs;
}

export type AppLogs = ReturnType<typeof captureAppLogs>;

/**
 * The same for code that writes to console.warn or console.error directly.
 * Restored when the test finishes.
 */
export function captureConsole(channel: 'warn' | 'error') {
  const spy = vi.spyOn(console, channel).mockImplementation(() => {});
  onTestFinished(() => spy.mockRestore());
  return spy;
}
