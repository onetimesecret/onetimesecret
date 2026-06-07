// src/schemas/shapes/config/section/index.ts

/**
 * Configuration Section Shapes
 *
 * Each section shape extends its contract counterpart with the defaults and
 * value constraints required at runtime. The composed shapes here are what
 * `bin/ots config validate` and JSON Schema generation consume.
 */

export * from './capabilities';
export * from './development';
export * from './diagnostics';
export * from './features';
export * from './i18n';
export * from './jobs';
export * from './jurisdiction';
export * from './limits';
export * from './mail';
export * from './secret_options';
export * from './site';
export * from './storage';
export * from './ui';
