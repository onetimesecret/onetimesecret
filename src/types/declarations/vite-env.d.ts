import type { Plugin } from 'rollup';


/**
 * This file is here because:
 * 1. It helps our code editor (like VSCode) understand Vue files.
 * 2. It stops TypeScript from complaining about .vue imports.
 * 3. It makes sure Vite and TypeScript are speaking the same language.
 *
 * Without it, it would be like trying to read a book in a language you don't know!
 */

/**
 * This reference helps TypeScript understand Vite-specific things.
 * It's like giving TypeScript a special dictionary for Vite words.
 *
 * The `///` at the beginning is a special signal to TypeScript. It's
 * like saying "Hey TypeScript, pay attention to this!".
 *
 * `<reference types="...">` is a way to tell TypeScript to include
 * type information from somewhere else. It's like telling TypeScript,
 * "There's more information you need to know, and you can find it here."
 *
 * `vite/client` is the path to the type definitions for Vite's
 * client-side code. This includes types for things like import.meta.env,
 * which Vite uses for environment variables. It typically refers to a file
 * or directory within the node_modules folder of your project. When you
 * install Vite (usually by running npm install vite or as part of
 * creating a Vite project), it creates a vite folder in your
 * node_modules.
 *
 *    e.g. ./node_modules/vite/client.d.ts
 *
 */

/// <reference types="vite/client" />

/**
 * Extend Vite's ImportMetaEnv interface to include our custom environment variables
 */
interface ImportMetaEnv {
  readonly VITE_AUTH_URL?: string
  // Include other Vite default env vars
  readonly VITE_APP_TITLE?: string
  readonly MODE: string
  readonly BASE_URL: string
  readonly PROD: boolean
  readonly DEV: boolean
  readonly SSR: boolean
}

/**
 * This part tells TypeScript how to understand .vue files.
 * It's like teaching TypeScript a new language (Vue).
 */
declare module '*.vue' {
  /**
   * We import a special Vue type that describes components.
   * This is like telling TypeScript what a Vue component looks like.
   */
  import type { DefineComponent } from 'vue'

  /**
   * This line says: "Any .vue file is a Vue component."
   * It's like saying: "If you see a .vue file, it's a special Vue toy."
   */
  // const component: DefineComponent<{}, {}, any>
  const component: DefineComponent<
    // props
    Record<string, unknown>,
    // data/computed properties returned from setup()
    Record<string, unknown>,
    // methods
    Record<string, (..._: unknown[]) => unknown>
  >
  /**
   * This makes the component available to use in other files.
   * It's like sharing your toy with friends so they can play too.
   */
  export default component
}


// src/build/plugins/addTrailingNewline.d.ts
export declare function addTrailingNewline(): Plugin;
