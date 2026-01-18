// src/build/plugins/syncLocales.ts

import { execFileSync } from 'child_process';
import type { Plugin } from 'vite';

/**
 * Vite plugin that syncs locale files on dev server start.
 *
 * Runs the Python sync script to generate merged locale files
 * from the source locale directories. This ensures the frontend
 * always has up-to-date locale data when starting development.
 *
 * The script generates files to generated/locales/{locale}.json
 * which are then imported by src/i18n.ts.
 *
 * @returns A Vite plugin object
 */
export function syncLocales(): Plugin {
  return {
    name: 'sync-locales',
    buildStart() {
      try {
        execFileSync('python', ['locales/scripts/sync_to_src.py', '--all', '--merged'], {
          stdio: 'inherit',
          cwd: process.cwd(),
        });
      } catch (error) {
        console.warn('[sync-locales] Failed to sync locales:', error);
        // Don't fail the build if sync fails - files may already exist
      }
    },
  };
}
