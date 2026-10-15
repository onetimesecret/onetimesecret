// src/services/logging.service.ts

const STARTUP_BANNER = `
┏┓┳┓┏┓┏┳┓┳┳┳┓┏┓
┃┃┃┃┣  ┃ ┃┃┃┃┣
┗┛┛┗┗┛ ┻ ┻┛ ┗┗┛
`;

/**
 * The self-XSS warning printed under the banner, already translated. Anyone
 * told to paste code into the console is being scammed; this is what they
 * read before they do.
 */
export interface ConsoleWarning {
  heading: string;
  lead: string;
  body: string;
  advice: string;
}

const WARNING_LEAD_STYLE = 'font-size:18px;font-weight:700;line-height:1.5';
const WARNING_BODY_STYLE = 'font-size:14px;line-height:1.5';

/**
 * Console arguments that draw `text` in flame colours: one `%c%s` pair per
 * character, red at the top left through amber at the bottom right. The
 * characters travel as `%s` arguments, never in the format string, so a `%`
 * in translated text cannot be read as a format specifier.
 */
export function flameArgs(text: string, fontSize: number): string[] {
  const rows = text.split('\n').map(graphemes);
  const width = Math.max(1, ...rows.map((row) => row.length));
  let format = '';
  const args: string[] = [];
  rows.forEach((row, r) => {
    row.forEach((ch, i) => {
      const heat = (r + i / width) / rows.length;
      const hue = (8 + heat * 34 + Math.sin(i * 1.3) * 4).toFixed(1);
      const light = (48 + heat * 14).toFixed(1);
      format += '%c%s';
      args.push(
        `color:hsl(${hue},95%,${light}%);font-size:${fontSize}px;line-height:1;` +
          `text-shadow:0 0 6px hsla(${hue},100%,50%,.6)`,
        ch
      );
    });
    if (r < rows.length - 1) format += '\n';
  });
  return [format, ...args];
}

// One entry per visible character, so accents and emoji keep together.
function graphemes(text: string): string[] {
  if (typeof Intl.Segmenter !== 'function') return Array.from(text);
  const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
  return Array.from(segmenter.segment(text), (s) => s.segment);
}

export type LogLevel = 'debug' | 'info' | 'warn' | 'error' | 'silent';

const LEVEL_RANK: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
  silent: 4,
};

/**
 * The lowest level that reaches the console. Debug and info are for a
 * developer's own browser: in the test suite they surround every passing
 * spec with output nobody reads, and in production they run in every
 * visitor's browser. Tests that assert on a debug line spy on
 * `loggingService.debug`, which records the call whatever the level.
 *
 * Outside Vite (the schema check CLI bundles this module and runs it under
 * plain node) there is no import.meta.env, and the level is warn.
 */
export function defaultLogLevel(
  env: { MODE: string; DEV: boolean } | undefined = import.meta.env
): LogLevel {
  if (!env || env.MODE === 'test') return 'warn';
  return env.DEV ? 'debug' : 'warn';
}

export interface LoggingService {
  error(error: Error): void;
  warn(message: string, context?: Record<string, unknown>): void;
  info(message: string, context?: Record<string, unknown>): void;
  debug(message: string, context?: Record<string, unknown>): void;
  banner(warning?: ConsoleWarning): void;
  getLevel(): LogLevel;
  setLevel(level: LogLevel): void;
}

// services/logging/console.ts
// import type { LoggingService } from './types';
// import type { ApplicationError } from '@/schemas/errors';

export class ConsoleLoggingService implements LoggingService {
  private level: LogLevel;

  constructor(level: LogLevel = defaultLogLevel()) {
    this.level = level;
  }

  getLevel(): LogLevel {
    return this.level;
  }

  setLevel(level: LogLevel): void {
    this.level = level;
  }

  private enabled(level: Exclude<LogLevel, 'silent'>): boolean {
    return LEVEL_RANK[level] >= LEVEL_RANK[this.level];
  }

  error(error: Error): void {
    if (this.enabled('error')) console.error(error.message, error);
  }

  warn(message: string, context?: Record<string, unknown>): void {
    if (this.enabled('warn')) console.warn(...withContext(message, context));
  }

  info(message: string, context?: Record<string, unknown>): void {
    if (this.enabled('info')) console.info(...withContext(message, context));
  }

  debug(message: string, context?: Record<string, unknown>): void {
    if (this.enabled('debug')) console.debug(...withContext(message, context));
  }

  // The banner is not a log message: it prints whatever the level, and in
  // production too. The build's dropConsole strips every `console.*` call,
  // so these go through `globalThis.console`, which it leaves alone
  // (console-survives-minify.spec.ts holds it to that).
  banner(warning?: ConsoleWarning): void {
    globalThis.console.log(...flameArgs(STARTUP_BANNER.trim(), 18));
    if (!warning) return;
    globalThis.console.log(...flameArgs(warning.heading, 36));
    globalThis.console.log(
      '%c%s\n\n%c%s\n\n%s',
      WARNING_LEAD_STYLE,
      warning.lead,
      WARNING_BODY_STYLE,
      warning.body,
      warning.advice
    );
  }
}

// Without a context the console would print a trailing `undefined`.
function withContext(message: string, context?: Record<string, unknown>): unknown[] {
  return context === undefined ? [message] : [message, context];
}

export const loggingService: LoggingService = new ConsoleLoggingService();
