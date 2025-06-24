// src/schemas/config/index.ts

/**
 * Configuration Schema Architecture
 *
 * This module defines two complementary schema types for application configuration:
 *
 * Static Config Schema (staticConfigSchema):
 * - Sets up the basic structure and what the application can do
 * - Decides what features are available and how things connect
 * - Gets loaded when the app starts up and doesn't change until restarted
 *
 * Mutable Config Schema (mutableSettingsSchema):
 * - Controls how the application behaves and what rules it follows
 * - Works within the limits set by the static config
 * - Can be changed while the app is running (without restarting)
 *
 * How configuration flows through the system:
 *
 *    Static + Mutable → (merge) → Runtime Config → (filter) → Client Config
 *
 * Design Principle:
 * The configuration system keeps static and mutable settings separate,
 * then combines them when the app runs. Static settings always win if
 * there's a conflict - mutable settings can't override them. The final
 * combined configuration becomes the single source of truth that contains
 * both what the system can do and how it should behave.
 *
 */

export * from './runtime';
