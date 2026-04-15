// src/tests/plugins/core/scrubSensitiveStrings.spec.ts
//
// Unit tests for scrubSensitiveStrings function.
// Tests scrubbing of emails, verifiable IDs, and sensitive paths from arbitrary text.

import { describe, expect, it } from 'vitest';
import { scrubSensitiveStrings } from '@/plugins/core/enableDiagnostics';

describe('scrubSensitiveStrings', () => {
  it('scrubs email addresses from text', () => {
    const text = 'Contact user@example.com for support';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Contact [EMAIL REDACTED] for support');
  });

  it('scrubs multiple email addresses', () => {
    const text = 'From: alice@example.com To: bob@example.com';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('From: [EMAIL REDACTED] To: [EMAIL REDACTED]');
  });

  it('scrubs 62-char verifiable IDs', () => {
    const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
    const text = `Processing secret ${id62}`;
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Processing secret [REDACTED]');
  });

  it('scrubs sensitive path patterns in text', () => {
    const text = 'Error loading /secret/abc123def';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Error loading /secret/[REDACTED]');
  });

  it('scrubs /private/ paths in text', () => {
    const text = 'Failed to fetch /private/xyz789';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Failed to fetch /private/[REDACTED]');
  });

  it('scrubs /receipt/ paths in text', () => {
    const text = 'Receipt at /receipt/receipt123';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Receipt at /receipt/[REDACTED]');
  });

  it('scrubs /incoming/ paths in text', () => {
    const text = 'Incoming at /incoming/incoming456';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Incoming at /incoming/[REDACTED]');
  });

  it('scrubs multiple sensitive patterns in one string', () => {
    const text = 'User user@example.com accessed /secret/abc123';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('User [EMAIL REDACTED] accessed /secret/[REDACTED]');
  });

  it('handles empty string input', () => {
    expect(scrubSensitiveStrings('')).toBe('');
  });

  it('handles null input gracefully', () => {
    expect(scrubSensitiveStrings(null as unknown as string)).toBe(null);
  });

  it('handles undefined input gracefully', () => {
    expect(scrubSensitiveStrings(undefined as unknown as string)).toBe(undefined);
  });

  it('leaves text without sensitive data unchanged', () => {
    const text = 'Application started successfully';
    const result = scrubSensitiveStrings(text);
    expect(result).toBe('Application started successfully');
  });
});
