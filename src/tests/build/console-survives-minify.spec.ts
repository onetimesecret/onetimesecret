// src/tests/build/console-survives-minify.spec.ts

/**
 * The production build's minifier drops every `console.*` call
 * (vite.config.ts: compress.dropConsole). The startup banner and the
 * self-XSS warning must still reach visitors, so logging.service.ts calls
 * `globalThis.console.log`, which the minifier leaves alone. If a Vite or
 * Rolldown upgrade starts matching that form too, the warning silently
 * disappears from production; this spec catches it.
 */

import path from 'path';
import { build, resolveConfig, type Rolldown } from 'vite';
import { describe, expect, it } from 'vitest';

const ROOT = process.cwd();

async function minifiedLoggingService(): Promise<string> {
  const config = await resolveConfig(
    { configFile: path.join(ROOT, 'vite.config.ts'), logLevel: 'silent' },
    'build',
    'production'
  );
  const minify = config.build.rolldownOptions?.output;
  const options = Array.isArray(minify) ? minify[0]?.minify : minify?.minify;
  expect(options, 'vite.config.ts no longer sets output.minify').toBeTruthy();

  const result = await build({
    configFile: false,
    logLevel: 'silent',
    root: ROOT,
    build: {
      write: false,
      lib: { entry: path.join(ROOT, 'src/services/logging.service.ts'), formats: ['es'] },
      rolldownOptions: { output: { minify: options } },
    },
  });
  const output = (Array.isArray(result) ? result[0] : result) as Rolldown.RolldownOutput;
  return output.output[0].code;
}

describe('logging.service.ts under the production minifier', () => {
  it('keeps the banner and warning calls and drops ordinary console calls', async () => {
    const code = await minifiedLoggingService();

    expect(code).toContain('┏┓┳┓┏┓┏┳┓┳┳┳┓┏┓');
    expect(code.match(/globalThis\.console\.log\(/g)).toHaveLength(3);
    // The level-gated methods still go: dropConsole is doing its job.
    expect(code).not.toMatch(/(?<!globalThis\.)console\.(debug|info|warn|error)\(/);
  }, 60_000);
});
