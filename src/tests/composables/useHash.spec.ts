// src/tests/composables/useHash.spec.ts
/**
 * Unit tests for useHash composable
 *
 * These tests verify that the useHash composable correctly:
 * - Generates cryptographic hashes with different algorithms
 * - Manages state during hash generation (isHashing, error)
 * - Handles edge cases like empty strings, errors, and large inputs
 */

import { useHash, type HashAlgorithm } from '@/composables/useHash';
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

describe('useHash', () => {
  const originalSubtleDigest = crypto.subtle.digest;

  beforeEach(() => {
    // No need to store full crypto object as it has only getters
  });

  afterEach(() => {
    // Restore original subtle.digest implementation
    Object.defineProperty(crypto.subtle, 'digest', {
      value: originalSubtleDigest,
      configurable: true,
    });
  });

  it('should generate SHA-256 hash correctly', async () => {
    const { generateHash, isHashing, error } = useHash();
    const input = 'test message';

    // Known SHA-256 hash of 'test message'
    const expectedHash = '3f0a377ba0a4a460ecb616f6507ce0d8cfa3e704025d4fda3ed0c5ca05468728';

    const result = await generateHash(input);

    expect(result).toBe(expectedHash);
    expect(isHashing.value).toBe(false);
    expect(error.value).toBeNull();
  });

  it('should set isHashing to true during hash generation', async () => {
    const { generateHash, isHashing } = useHash();

    // Mock subtle.digest to delay completion
    const mockDigest = vi.fn().mockImplementation(() => new Promise((resolve) => {
        setTimeout(() => {
          // Create a mock hash buffer
          const buffer = new ArrayBuffer(32);
          const view = new Uint8Array(buffer);
          for (let i = 0; i < 32; i++) {
            view[i] = i;
          }
          resolve(buffer);
        }, 10);
      }));

    // Replace crypto.subtle.digest with our mock implementation
    Object.defineProperty(crypto.subtle, 'digest', {
      value: mockDigest,
      configurable: true,
    });

    // Start hash generation but don't await it yet
    const hashPromise = generateHash('test');

    // isHashing should be true while the promise is pending
    expect(isHashing.value).toBe(true);

    // Wait for hash to complete
    await hashPromise;

    // isHashing should be false after completion
    expect(isHashing.value).toBe(false);
    expect(mockDigest).toHaveBeenCalledWith('SHA-256', expect.any(Object));
  });

  it('should support different hash algorithms', async () => {
    const { generateHash } = useHash();
    const input = 'test message';

    // Mock the digest function for different algorithms
    const mockDigest = vi.fn().mockImplementation((algorithm) => {
      const mockHashResults = {
        'SHA-1': new Uint8Array([1, 2, 3, 4, 5]),
        'SHA-256': new Uint8Array([6, 7, 8, 9, 10]),
        'SHA-384': new Uint8Array([11, 12, 13, 14, 15]),
        'SHA-512': new Uint8Array([16, 17, 18, 19, 20])
      };

      return Promise.resolve(mockHashResults[algorithm as keyof typeof mockHashResults].buffer);
    });

    // Replace crypto.subtle.digest with our mock implementation
    Object.defineProperty(crypto.subtle, 'digest', {
      value: mockDigest,
      configurable: true,
    });

    await generateHash(input, 'SHA-1');
    expect(mockDigest).toHaveBeenCalledWith('SHA-1', expect.any(Object));

    await generateHash(input, 'SHA-256');
    expect(mockDigest).toHaveBeenCalledWith('SHA-256', expect.any(Object));

    await generateHash(input, 'SHA-384');
    expect(mockDigest).toHaveBeenCalledWith('SHA-384', expect.any(Object));

    await generateHash(input, 'SHA-512');
    expect(mockDigest).toHaveBeenCalledWith('SHA-512', expect.any(Object));
  });

  it('should reject invalid hash algorithms', async () => {
    const { generateHash, error } = useHash();

    // @ts-expect-error - Testing invalid algorithm which TypeScript would normally prevent
    const result = await generateHash('test', 'INVALID-ALGORITHM' as HashAlgorithm);

    expect(result).toBeNull();
    expect(error.value).not.toBeNull();
    expect(error.value).toContain('algorithm');
  });

  it('should handle errors during hash generation', async () => {
    const { generateHash, error } = useHash();

    // Mock crypto.subtle.digest to throw an error
    const mockError = new Error('Crypto operation failed');
    Object.defineProperty(crypto.subtle, 'digest', {
      value: vi.fn().mockRejectedValue(mockError),
      configurable: true,
    });

    const result = await generateHash('test');

    expect(result).toBeNull();
    expect(error.value).toBe('Crypto operation failed');
  });

  it('should handle non-Error objects thrown during hash generation', async () => {
    const { generateHash, error } = useHash();

    // Mock crypto.subtle.digest to throw a non-Error object
    Object.defineProperty(crypto.subtle, 'digest', {
      value: vi.fn().mockRejectedValue('String error message'),
      configurable: true,
    });

    const result = await generateHash('test');

    expect(result).toBeNull();
    expect(error.value).toBe('String error message');
  });

  it('should generate consistent hash for the same input', async () => {
    const { generateHash } = useHash();
    const input = 'consistent input';

    const hash1 = await generateHash(input);
    const hash2 = await generateHash(input);

    expect(hash1).toBe(hash2);
  });

  it('should generate different hashes for different inputs', async () => {
    const { generateHash } = useHash();

    const hash1 = await generateHash('input1');
    const hash2 = await generateHash('input2');

    expect(hash1).not.toBe(hash2);
    expect(hash1?.length).toBe(64); // SHA-256 output should be 64 hex chars
    expect(hash2?.length).toBe(64);
  });

  it('should convert empty string input correctly', async () => {
    const { generateHash } = useHash();

    // SHA-256 hash of empty string
    const emptyStringHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    const result = await generateHash('');

    expect(result).toBe(emptyStringHash);
  });

  it('should handle null and undefined inputs', async () => {
    const { generateHash } = useHash();

    // Define known values for comparison
    const emptyStringHash = await generateHash('');
    const nullStringHash = await generateHash('null');

    // @ts-expect-error - Testing null input which TypeScript would normally prevent
    const nullResult = await generateHash(null);
    // Implementation treats null as "null" string
    expect(nullResult).not.toBeNull();
    expect(nullResult?.length).toBe(64); // Valid SHA-256 hash
    expect(nullResult).toBe(nullStringHash); // Should match hash of "null" string
    expect(nullResult).not.toBe(emptyStringHash); // Should not match empty string hash

    // @ts-expect-error - Testing undefined input which TypeScript would normally prevent
    const undefinedResult = await generateHash(undefined);
    // Implementation treats undefined as empty string
    expect(undefinedResult).toBe(emptyStringHash); // Should match empty string hash
    expect(undefinedResult).not.toBe(nullResult); // Should not match null result
  });

  it('should handle very large input strings', async () => {
    const { generateHash } = useHash();

    // Create a large string (1MB+)
    const largeString = 'x'.repeat(1024 * 1024 + 100); // Just over 1MB

    const result = await generateHash(largeString);

    // We just check that it returns a valid hash (64 hex chars for SHA-256)
    expect(result).not.toBeNull();
    expect(result?.length).toBe(64);
  });

  it('should properly handle Unicode characters', async () => {
    const { generateHash } = useHash();
    const unicodeInput = '👋 Hello, 世界!';

    // First hash with Unicode characters
    const hash1 = await generateHash(unicodeInput);

    // Verify the hash is not null and has the expected length for SHA-256 (64 hex chars)
    expect(hash1).not.toBeNull();
    expect(hash1?.length).toBe(64);

    // Generate the hash again with the same input
    const hash2 = await generateHash(unicodeInput);

    // Verify the hashes match
    expect(hash1).toBe(hash2);
  });

  it('should maintain proper error state between multiple calls', async () => {
    const { generateHash, error, isHashing } = useHash();

    // Mock crypto.subtle.digest to throw an error
    Object.defineProperty(crypto.subtle, 'digest', {
      value: vi.fn().mockRejectedValue(new Error('First error')),
      configurable: true,
    });

    const result1 = await generateHash('test');
    expect(result1).toBeNull();
    expect(error.value).toBe('First error');
    expect(isHashing.value).toBe(false);

    // Change the mock to succeed
    Object.defineProperty(crypto.subtle, 'digest', {
      value: vi.fn().mockImplementation(() => {
        const buffer = new ArrayBuffer(32);
        const view = new Uint8Array(buffer);
        for (let i = 0; i < 32; i++) {
          view[i] = i;
        }
        return Promise.resolve(buffer);
      }),
      configurable: true,
    });

    const result2 = await generateHash('test');
    expect(result2).not.toBeNull();
    expect(error.value).toBeNull(); // Error should be cleared after successful call
    expect(isHashing.value).toBe(false);
  });

  it('should handle concurrent hash operations correctly', async () => {
    const { generateHash, isHashing } = useHash();

    // Create multiple hash operations without awaiting them
    const hashPromise1 = generateHash('data1');
    const hashPromise2 = generateHash('data2');

    // isHashing should be true while operations are in progress
    expect(isHashing.value).toBe(true);

    // Complete all hash operations
    const [result1, result2] = await Promise.all([hashPromise1, hashPromise2]);

    // Verify results
    expect(result1).not.toBeNull();
    expect(result2).not.toBeNull();
    expect(result1).not.toBe(result2);

    // isHashing should be false when all complete
    expect(isHashing.value).toBe(false);
  });
});
