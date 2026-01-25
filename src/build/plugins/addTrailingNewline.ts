// src/build/plugins/addTrailingNewline.ts

import fs from 'fs/promises';
import path from 'path';
import type { OutputBundle, OutputOptions, Plugin } from 'rollup';

/**
 * Vite plugin to ensure all text output files have a trailing newline.
 *
 * This plugin hooks into the `writeBundle` phase of the build process
 * and checks each generated text file. If a file doesn't end with a newline,
 * it appends one. Binary files are ignored.
 *
 * @returns A Vite plugin object
 */
export const addTrailingNewline = (): Plugin => ({
  name: 'add-trailing-newline',
  async writeBundle(options: OutputOptions, bundle: OutputBundle): Promise<void> {
    const outputDir = options.dir!;

    await Promise.all(
      Object.keys(bundle).map(async (fileName) => {
        const filePath = path.join(outputDir, fileName);

        try {
          const fileBuffer = await fs.readFile(filePath);

          // Simple binary file check
          const isBinary = fileBuffer.includes(0);

          if (!isBinary) {
            const content = fileBuffer.toString('utf-8');
            if (!content.endsWith('\n')) {
              // Append a newline if the file doesn't end with one
              await fs.writeFile(filePath, content + '\n');
            }
          }
        } catch (error) {
          console.error(`Error processing file ${fileName}:`, error);
        }
      })
    );
  },
});
