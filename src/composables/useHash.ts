// composables/useHash.ts

import { ref, Ref } from 'vue';

/**
 * Supported hash algorithms that can be used with Web Crypto API
 */
export type HashAlgorithm = 'SHA-1' | 'SHA-256' | 'SHA-384' | 'SHA-512';

/**
 * Composable for generating cryptographic hashes using the Web Crypto API
 * @returns Object containing hash generation method and status values
 */
export function useHash() {
  const isHashing: Ref<boolean> = ref(false);
  const error: Ref<string | null> = ref(null);

  /**
   * Generates a cryptographic hash of the provided message
   * @param message - The input string to be hashed
   * @param algorithm - The hashing algorithm to use (default: 'SHA-256')
   * @returns A promise resolving to the hexadecimal hash string, or null if an error occurs
   */
  const generateHash = async (
    message: string,
    algorithm: HashAlgorithm = 'SHA-256'
  ): Promise<string | null> => {
    isHashing.value = true;
    error.value = null;

    try {
      const msgUint8 = new TextEncoder().encode(message);
      const hashBuffer = await crypto.subtle.digest(algorithm, msgUint8);
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      const hashHex = hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');

      return hashHex;
    } catch (err: unknown) {
      error.value = err instanceof Error ? err.message : String(err);
      return null;
    } finally {
      isHashing.value = false;
    }
  };

  return {
    generateHash,
    isHashing,
    error,
  };
}
