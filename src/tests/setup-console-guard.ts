// src/tests/setup-console-guard.ts
//
// Fails a test that writes to console.warn or console.error unless it says
// it expects to. Vue's dev warnings ("[Vue warn]: Missing required prop")
// and vue-i18n's go through console.warn, so they count too.
//
// A test that expects output takes it over before it happens, and asserts
// on it: captureAppLogs() for loggingService.warn/error, captureConsole()
// for a direct console call (src/tests/utils/appLogs.ts). Any vitest spy on
// console.warn/error works the same way: while one is installed, this guard
// records nothing on that channel; the spy belongs to the test.
//
// The check runs once the test's teardown is done: afterEach hooks,
// beforeEach cleanups and onTestFinished callbacks (the guard's own runs
// last, being registered first). Output from module load, beforeAll or
// afterAll is not attributed to any test and is not checked.
//
// Spec files listed in console-guard.exempt.ts still print but do not fail.

import { beforeEach, onTestFinished, vi } from 'vitest';
import { CONSOLE_GUARD_EXEMPT } from './console-guard.exempt';

type Channel = 'warn' | 'error';

let unexpected: string[] | null = null;

for (const channel of ['warn', 'error'] as const satisfies readonly Channel[]) {
  const write = console[channel];
  console[channel] = function guarded(this: Console, ...args: unknown[]) {
    if (unexpected && !vi.isMockFunction(console[channel])) {
      unexpected.push(`console.${channel}: ${summarize(args)}`);
    }
    return write.apply(this, args);
  };
}

beforeEach(() => {
  const lines: string[] = [];
  unexpected = lines;
  onTestFinished(({ task }) => {
    unexpected = null;
    if (lines.length === 0 || isExempt(task.file.filepath)) return;
    throw unexpectedOutput(lines);
  });
});

function unexpectedOutput(lines: string[]): Error {
  return new Error(
    [
      `Unexpected console output (${lines.length}):`,
      ...lines.slice(0, 5).map((line) => `  ${line}`),
      ...(lines.length > 5 ? [`  … and ${lines.length - 5} more`] : []),
      'Fix the cause, or take the output over and assert on it with',
      'captureAppLogs() or captureConsole() from src/tests/utils/appLogs.ts.',
    ].join('\n')
  );
}

function isExempt(testPath: string): boolean {
  const at = testPath.lastIndexOf('/src/tests/');
  return at >= 0 && CONSOLE_GUARD_EXEMPT.has(testPath.slice(at + 1));
}

function summarize(args: unknown[]): string {
  return args
    .map((arg) => {
      if (typeof arg === 'string') return arg;
      if (arg instanceof Error) return `${arg.name}: ${arg.message}`;
      return Object.prototype.toString.call(arg);
    })
    .join(' ')
    .replace(/\s+/g, ' ')
    .slice(0, 200);
}
