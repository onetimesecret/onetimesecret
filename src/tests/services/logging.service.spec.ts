// src/tests/services/logging.service.spec.ts

import { ConsoleLoggingService, defaultLogLevel } from '@/services/logging.service';
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
});
