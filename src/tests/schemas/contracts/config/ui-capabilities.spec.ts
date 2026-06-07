// src/tests/schemas/contracts/config/ui-capabilities.spec.ts
//
// Tests for uiCapabilitiesSchema covering valid, partial, empty, and invalid
// inputs, plus integration with the parent uiSchema/uiInterfaceSchema.

import { describe, it, expect } from 'vitest';
import {
  uiCapabilitiesSchema as configUiCapabilitiesSchema,
  uiHelpSchema as configUiHelpSchema,
  uiSchema as configUiSchema,
} from '@/schemas/contracts/config/section/ui';
import {
  uiCapabilitiesSchema as bootstrapUiCapabilitiesSchema,
  uiHelpSchema as bootstrapUiHelpSchema,
  uiInterfaceSchema as bootstrapUiInterfaceSchema,
} from '@/schemas/contracts/bootstrap';

/**
 * Both config and bootstrap define their own uiCapabilitiesSchema.
 * These tests verify both behave identically and integrate with their
 * respective parent schemas.
 */
describe.each([
  { label: 'config/section/ui', schema: configUiCapabilitiesSchema },
  { label: 'contracts/bootstrap', schema: bootstrapUiCapabilitiesSchema },
])('uiCapabilitiesSchema ($label)', ({ schema }) => {
  it('accepts full input with all four boolean fields', () => {
    const input = {
      burn: true,
      show: true,
      receipt: false,
      recipient: true,
    };

    const result = schema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data).toEqual(input);
    }
  });

  it('accepts partial input with only burn provided', () => {
    const input = { burn: true };

    const result = schema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.burn).toBe(true);
      expect(result.data.show).toBeUndefined();
      expect(result.data.receipt).toBeUndefined();
      expect(result.data.recipient).toBeUndefined();
    }
  });

  it('accepts empty object (all fields optional)', () => {
    const result = schema.safeParse({});
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data).toEqual({});
    }
  });

  it('rejects non-boolean value for burn', () => {
    const input = { burn: 'yes' };

    const result = schema.safeParse(input);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('burn');
    }
  });

  it('rejects non-boolean value for show', () => {
    const result = schema.safeParse({ show: 1 });
    expect(result.success).toBe(false);
  });

  it('rejects non-boolean value for receipt', () => {
    const result = schema.safeParse({ receipt: null });
    expect(result.success).toBe(false);
  });

  it('rejects non-boolean value for recipient', () => {
    const result = schema.safeParse({ recipient: 'true' });
    expect(result.success).toBe(false);
  });
});

describe('uiCapabilitiesSchema nested in parent schema (config uiSchema)', () => {
  it('parses capabilities nested inside uiSchema', () => {
    const input = {
      enabled: true,
      capabilities: {
        burn: false,
        recipient: true,
      },
    };

    const result = configUiSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.capabilities?.burn).toBe(false);
      expect(result.data.capabilities?.recipient).toBe(true);
      expect(result.data.capabilities?.show).toBeUndefined();
      expect(result.data.capabilities?.receipt).toBeUndefined();
    }
  });

  it('parses uiSchema without capabilities field', () => {
    const input = { enabled: true };

    const result = configUiSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.capabilities).toBeUndefined();
    }
  });
});

describe('uiCapabilitiesSchema nested in parent schema (bootstrap uiInterfaceSchema)', () => {
  it('parses capabilities nested inside uiInterfaceSchema', () => {
    const input = {
      enabled: true,
      capabilities: {
        burn: false,
        recipient: true,
      },
    };

    const result = bootstrapUiInterfaceSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.capabilities?.burn).toBe(false);
      expect(result.data.capabilities?.recipient).toBe(true);
      expect(result.data.capabilities?.show).toBeUndefined();
      expect(result.data.capabilities?.receipt).toBeUndefined();
    }
  });

  it('parses uiInterfaceSchema without capabilities field', () => {
    const input = { enabled: true };

    const result = bootstrapUiInterfaceSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.capabilities).toBeUndefined();
    }
  });
});

/**
 * Both config and bootstrap define their own uiHelpSchema.
 * These tests verify both behave identically for explicit values
 * and integrate with their respective parent schemas.
 */
describe.each([
  { label: 'config/section/ui', schema: configUiHelpSchema },
  { label: 'contracts/bootstrap', schema: bootstrapUiHelpSchema },
])('uiHelpSchema ($label)', ({ schema }) => {
  it('accepts { enabled: true }', () => {
    const result = schema.safeParse({ enabled: true });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.enabled).toBe(true);
    }
  });

  it('accepts { enabled: false }', () => {
    const result = schema.safeParse({ enabled: false });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.enabled).toBe(false);
    }
  });

  it('accepts empty object', () => {
    const result = schema.safeParse({});
    expect(result.success).toBe(true);
  });

  it('rejects non-boolean value for enabled', () => {
    const result = schema.safeParse({ enabled: 'yes' });
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].path).toContain('enabled');
    }
  });
});

describe('uiHelpSchema default behavior differences', () => {
  it('config schema: enabled is undefined when omitted', () => {
    const result = configUiHelpSchema.safeParse({});
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.enabled).toBeUndefined();
    }
  });

  it('bootstrap schema: enabled defaults to true when omitted', () => {
    const result = bootstrapUiHelpSchema.safeParse({});
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.enabled).toBe(true);
    }
  });
});

describe('uiHelpSchema nested in parent schema (config uiSchema)', () => {
  it('parses help nested inside uiSchema', () => {
    const input = {
      enabled: true,
      help: {
        enabled: false,
      },
    };

    const result = configUiSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.help?.enabled).toBe(false);
    }
  });

  it('parses uiSchema without help field', () => {
    const input = { enabled: true };

    const result = configUiSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.help).toBeUndefined();
    }
  });
});

describe('uiHelpSchema nested in parent schema (bootstrap uiInterfaceSchema)', () => {
  it('parses help nested inside uiInterfaceSchema', () => {
    const input = {
      enabled: true,
      help: {
        enabled: true,
      },
    };

    const result = bootstrapUiInterfaceSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.help?.enabled).toBe(true);
    }
  });

  it('parses uiInterfaceSchema without help field', () => {
    const input = { enabled: true };

    const result = bootstrapUiInterfaceSchema.safeParse(input);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.help).toBeUndefined();
    }
  });
});
