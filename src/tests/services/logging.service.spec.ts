// src/tests/services/logging.service.spec.ts

import { ConsoleLoggingService, defaultLogLevel, flameArgs } from '@/services/logging.service';
import { afterEach, describe, expect, it, vi } from 'vitest';

describe('defaultLogLevel', () => {
  it('is warn under the test runner', () => {
    expect(defaultLogLevel({ MODE: 'test', DEV: true })).toBe('warn');
  });

  it('is debug in a development build', () => {
    expect(defaultLogLevel({ MODE: 'development', DEV: true })).toBe('debug');
  });

  it('is warn in a production build', () => {
    expect(defaultLogLevel({ MODE: 'production', DEV: false })).toBe('warn');
  });

  it('is what this suite runs at', () => {
    expect(defaultLogLevel()).toBe('warn');
  });
});

describe('ConsoleLoggingService', () => {
  const spies = () => ({
    debug: vi.spyOn(console, 'debug').mockImplementation(() => {}),
    info: vi.spyOn(console, 'info').mockImplementation(() => {}),
    warn: vi.spyOn(console, 'warn').mockImplementation(() => {}),
    error: vi.spyOn(console, 'error').mockImplementation(() => {}),
    log: vi.spyOn(console, 'log').mockImplementation(() => {}),
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function logEveryLevel(service: ConsoleLoggingService) {
    service.debug('d');
    service.info('i');
    service.warn('w');
    service.error(new Error('e'));
  }

  it('writes every level at debug', () => {
    const c = spies();
    logEveryLevel(new ConsoleLoggingService('debug'));
    expect([c.debug, c.info, c.warn, c.error].map((s) => s.mock.calls.length)).toEqual([
      1, 1, 1, 1,
    ]);
  });

  it('drops debug and info at warn', () => {
    const c = spies();
    logEveryLevel(new ConsoleLoggingService('warn'));
    expect([c.debug, c.info, c.warn, c.error].map((s) => s.mock.calls.length)).toEqual([
      0, 0, 1, 1,
    ]);
  });

  it('writes nothing at silent', () => {
    const c = spies();
    logEveryLevel(new ConsoleLoggingService('silent'));
    expect([c.debug, c.info, c.warn, c.error].map((s) => s.mock.calls.length)).toEqual([
      0, 0, 0, 0,
    ]);
  });

  it('follows setLevel', () => {
    const c = spies();
    const service = new ConsoleLoggingService('warn');
    service.setLevel('debug');
    service.debug('now visible');
    expect(service.getLevel()).toBe('debug');
    expect(c.debug).toHaveBeenCalledWith('now visible');
  });

  it('passes a context through and leaves it off when absent', () => {
    const c = spies();
    const service = new ConsoleLoggingService('debug');
    service.debug('with', { a: 1 });
    service.debug('without');
    expect(c.debug.mock.calls).toEqual([['with', { a: 1 }], ['without']]);
  });

  it('prints the banner at any level', () => {
    const c = spies();
    new ConsoleLoggingService('silent').banner();
    expect(c.log).toHaveBeenCalledTimes(1);
  });

  it('prints the warning under the banner when given one', () => {
    const c = spies();
    new ConsoleLoggingService('silent').banner({
      heading: 'Danger',
      lead: 'Stop.',
      body: 'Body text.',
      advice: 'Close this panel.',
    });
    expect(c.log).toHaveBeenCalledTimes(3);
    const [, heading, text] = c.log.mock.calls;
    expect(heading).toEqual(flameArgs('Danger', 36));
    expect(text.filter((arg) => !String(arg).includes(':'))).toEqual(
      expect.arrayContaining(['Stop.', 'Body text.', 'Close this panel.'])
    );
  });
});

describe('flameArgs', () => {
  // Every %c%s pair takes a style and then a character.
  function characters(args: string[]): string {
    return args.filter((_, i) => i % 2 === 1).join('');
  }

  it('pairs one style with each character', () => {
    const [format, ...rest] = flameArgs('Hot', 18);
    expect(format).toBe('%c%s%c%s%c%s');
    expect(rest).toHaveLength(6);
    expect(characters(rest)).toBe('Hot');
    expect(rest[0]).toMatch(/^color:hsl\(/);
  });

  it('keeps line breaks in the format string', () => {
    const [format] = flameArgs('ab\nc', 18);
    expect(format).toBe('%c%s%c%s\n%c%s');
  });

  it('keeps a percent sign out of the format string', () => {
    const [format, ...rest] = flameArgs('100%', 18);
    expect(format).toBe('%c%s'.repeat(4));
    expect(characters(rest)).toBe('100%');
  });

  it('keeps a character and its combining accent together', () => {
    const [format] = flameArgs('e\u0301', 18);
    expect(format).toBe('%c%s');
  });
});
