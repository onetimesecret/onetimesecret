// src/tests/i18n.spec.ts

import { createI18nInstance } from '@/i18n';
import { readdirSync } from 'fs';
import { resolve } from 'path';
import { describe, expect, it } from 'vitest';

// src/i18n.ts loads generated/locales/*.json with import.meta.glob. A pattern
// anchored with a leading / resolves against the Vite root, which differs
// between vite.config.ts (./src) and vitest.config.ts (the repo root), and
// under vitest it matched nothing: every spec using the real module ran with
// no messages and no available locales. These cases fail if that happens again.
describe('i18n module locale loading', () => {
  // globalSetup runs locales:sync, so generated/locales/ is populated here.
  const generatedLocales = readdirSync(resolve(process.cwd(), 'generated/locales'))
    .filter((name) => name.endsWith('.json'))
    .map((name) => name.replace(/\.json$/, ''))
    .sort();

  it('finds generated locale files to compare against', () => {
    expect(generatedLocales).toContain('en');
  });

  it('makes every generated locale available', () => {
    const { composer } = createI18nInstance('en');
    expect([...composer.availableLocales].sort()).toEqual(generatedLocales);
  });

  it('translates from the loaded messages', () => {
    const { composer } = createI18nInstance('ja');
    expect(composer.t('web.LABELS.loading')).toBe('読み込み中...');
    expect(composer.t('web.LABELS.loading', {}, { locale: 'en' })).toBe('Loading...');
  });
});
