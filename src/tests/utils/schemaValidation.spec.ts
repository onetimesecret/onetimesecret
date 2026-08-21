// src/tests/utils/schemaValidation.spec.ts
//
// Tests for schema validation utilities with uniform control flow.
// gracefulParse always returns ParseResult — never throws.
// In dev/test it calls console.error as a side effect for visibility.

import { z, ZodError } from 'zod';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ParseResult } from '@/utils/schemaValidation';

// Mock loggingService before importing the module under test
vi.mock('@/services/logging.service', () => ({
  loggingService: {
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
    debug: vi.fn(),
    banner: vi.fn(),
  },
}));

// The Sentry-facing sink. Mocked so the production reporting branch can be
// asserted directly: everything between gracefulParse and this call is real.
vi.mock('@/services/diagnostics.service', () => ({
  captureException: vi.fn(),
  captureMessage: vi.fn(),
}));

// Import after mocking
import { gracefulParse, strictParse } from '@/utils/schemaValidation';
import { loggingService } from '@/services/logging.service';
import { captureException } from '@/services/diagnostics.service';
import {
  MAX_PROJECTED_ISSUES,
  projectSchemaIssues,
} from '@/utils/telemetry/schemaIssueProjection';
import {
  parameterizeApiPath,
  resetApiRouteContext,
  setApiRouteResolver,
  setCurrentApiRoute,
} from '@/utils/telemetry/apiRouteContext';

// Test schemas
const UserSchema = z.object({
  id: z.string(),
  name: z.string(),
  email: z.string().email(),
  age: z.number().optional(),
});

const SimpleSchema = z.object({
  value: z.string(),
});

type User = z.infer<typeof UserSchema>;

describe('schemaValidation', () => {
  let consoleSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.clearAllMocks();
    consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    consoleSpy.mockRestore();
  });

  describe('gracefulParse', () => {
    describe('success cases', () => {
      it('returns { ok: true, data } when schema matches', () => {
        const validData = {
          id: '123',
          name: 'John Doe',
          email: 'john@example.com',
        };

        const result = gracefulParse(UserSchema, validData);

        expect(result.ok).toBe(true);
        if (result.ok) {
          expect(result.data).toEqual(validData);
        }
      });

      it('returns validated data with optional fields present', () => {
        const validData: User = {
          id: '123',
          name: 'Jane Doe',
          email: 'jane@example.com',
          age: 30,
        };

        const result = gracefulParse(UserSchema, validData);

        expect(result.ok).toBe(true);
        if (result.ok) {
          expect(result.data).toEqual(validData);
          expect(result.data.age).toBe(30);
        }
      });

      it('strips unknown fields from validated data (non-strict schema)', () => {
        const looseSchema = z.object({
          id: z.string(),
        });

        const dataWithExtra = {
          id: '123',
          extraField: 'should be stripped',
        };

        const result = gracefulParse(looseSchema, dataWithExtra);

        expect(result.ok).toBe(true);
        if (result.ok) {
          expect(result.data).toEqual({ id: '123' });
          expect(result.data).not.toHaveProperty('extraField');
        }
      });

      it('does not log errors on success', () => {
        const validData = { value: 'test' };

        gracefulParse(SimpleSchema, validData);

        expect(loggingService.error).not.toHaveBeenCalled();
      });
    });

    describe('failure cases (uniform control flow)', () => {
      // Note: gracefulParse always returns ParseResult — never throws.
      // In dev/test (Vitest sets NODE_ENV=test), it calls console.error.

      it('returns { ok: false } when required field is missing', () => {
        const invalidData = {
          id: '123',
          // missing name and email
        };

        const result = gracefulParse(UserSchema, invalidData);
        expect(result.ok).toBe(false);
        if (!result.ok) {
          expect(result.error).toBeInstanceOf(ZodError);
        }
      });

      it('returns { ok: false } when field type is wrong', () => {
        const invalidData = {
          id: 123, // should be string
          name: 'John',
          email: 'john@example.com',
        };

        const result = gracefulParse(UserSchema, invalidData);
        expect(result.ok).toBe(false);
        if (!result.ok) {
          expect(result.error).toBeInstanceOf(ZodError);
        }
      });

      it('returns { ok: false } when email format is invalid', () => {
        const invalidData = {
          id: '123',
          name: 'John',
          email: 'not-an-email',
        };

        const result = gracefulParse(UserSchema, invalidData);
        expect(result.ok).toBe(false);
        if (!result.ok) {
          expect(result.error).toBeInstanceOf(ZodError);
        }
      });

      it('returns { ok: false } when data is null', () => {
        const result = gracefulParse(UserSchema, null);
        expect(result.ok).toBe(false);
        if (!result.ok) {
          expect(result.error).toBeInstanceOf(ZodError);
        }
      });

      it('returns { ok: false } when data is undefined', () => {
        const result = gracefulParse(UserSchema, undefined);
        expect(result.ok).toBe(false);
        if (!result.ok) {
          expect(result.error).toBeInstanceOf(ZodError);
        }
      });

      it('includes validation issues in error result', () => {
        const invalidData = {
          id: '123',
          name: 'John',
          email: 'invalid',
        };

        const result = gracefulParse(UserSchema, invalidData);
        expect(result.ok).toBe(false);
        if (!result.ok) {
          expect(result.error).toBeInstanceOf(ZodError);
          expect(result.error!.issues.length).toBeGreaterThan(0);
          expect(result.error!.issues[0].path).toContain('email');
        }
      });

      it('calls console.error in dev/test mode on failure', () => {
        const invalidData = { id: 123 };

        gracefulParse(UserSchema, invalidData);

        // In dev/test mode, console.error is called (not loggingService)
        expect(consoleSpy).toHaveBeenCalledWith(
          expect.stringContaining('Schema validation failed'),
          expect.any(Array)
        );
        expect(loggingService.error).not.toHaveBeenCalled();
      });
    });

    describe('context parameter', () => {
      it('accepts context parameter for success case', () => {
        const validData = { value: 'test' };

        const result = gracefulParse(SimpleSchema, validData, 'TestContext');

        expect(result.ok).toBe(true);
        if (result.ok) {
          expect(result.data).toEqual(validData);
        }
      });

      it('context is available in error for debugging', () => {
        // In test mode, context would be included in production error message
        // We can verify the function accepts the parameter
        const validData = { value: 'test' };

        // Should not throw even with context
        expect(() => {
          gracefulParse(SimpleSchema, validData, 'SomeContext');
        }).not.toThrow();
      });
    });
  });

  describe('gracefulParse error reporting', () => {
    // With the uniform approach, { ok: false } is returned in all environments.
    // The only difference is the side-effect channel: console.error in dev/test,
    // loggingService.error in production.

    it('returns { ok: false, error } on invalid data', () => {
      const result = gracefulParse(SimpleSchema, { value: 123 });
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.error).toBeInstanceOf(ZodError);
      }
    });

    it('includes context in console.error message when provided', () => {
      gracefulParse(SimpleSchema, { value: 123 }, 'TestContext');

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('Schema validation failed for TestContext'),
        expect.any(Array)
      );
    });
  });

  describe('strictParse', () => {
    describe('success cases', () => {
      it('returns validated data when schema matches', () => {
        const validData = {
          id: '123',
          name: 'John Doe',
          email: 'john@example.com',
        };

        const result = strictParse(UserSchema, validData);

        expect(result).toEqual(validData);
      });

      it('returns validated data with optional fields', () => {
        const validData: User = {
          id: '456',
          name: 'Jane',
          email: 'jane@example.com',
          age: 25,
        };

        const result = strictParse(UserSchema, validData);

        expect(result).toEqual(validData);
      });

      it('handles complex nested schemas', () => {
        const NestedSchema = z.object({
          user: UserSchema,
          metadata: z.object({
            createdAt: z.string(),
            tags: z.array(z.string()),
          }),
        });

        const validData = {
          user: {
            id: '1',
            name: 'Test',
            email: 'test@example.com',
          },
          metadata: {
            createdAt: '2024-01-01',
            tags: ['tag1', 'tag2'],
          },
        };

        const result = strictParse(NestedSchema, validData);

        expect(result).toEqual(validData);
      });
    });

    describe('failure cases', () => {
      it('throws ZodError when required field is missing', () => {
        const invalidData = {
          id: '123',
        };

        expect(() => strictParse(UserSchema, invalidData)).toThrow(ZodError);
      });

      it('throws ZodError when field type is wrong', () => {
        const invalidData = {
          id: '123',
          name: 456, // should be string
          email: 'test@example.com',
        };

        expect(() => strictParse(UserSchema, invalidData)).toThrow(ZodError);
      });

      it('throws ZodError when data is null', () => {
        expect(() => strictParse(UserSchema, null)).toThrow(ZodError);
      });

      it('throws ZodError when data is undefined', () => {
        expect(() => strictParse(UserSchema, undefined)).toThrow(ZodError);
      });

      it('throws ZodError when data is empty object', () => {
        expect(() => strictParse(UserSchema, {})).toThrow(ZodError);
      });

      it('throws ZodError when array item is invalid', () => {
        const ArraySchema = z.array(z.number());

        expect(() => strictParse(ArraySchema, [1, 'two', 3])).toThrow(ZodError);
      });
    });

    describe('error details', () => {
      it('includes path to invalid field in error', () => {
        const invalidData = {
          id: '123',
          name: 'John',
          email: 'invalid',
        };

        try {
          strictParse(UserSchema, invalidData);
          expect.fail('Should have thrown');
        } catch (error) {
          expect(error).toBeInstanceOf(ZodError);
          const zodError = error as ZodError;
          expect(zodError.issues[0].path).toContain('email');
        }
      });

      it('includes multiple issues for multiple failures', () => {
        const invalidData = {
          id: 123, // wrong type
          // missing name
          email: 'invalid',
        };

        try {
          strictParse(UserSchema, invalidData);
          expect.fail('Should have thrown');
        } catch (error) {
          expect(error).toBeInstanceOf(ZodError);
          const zodError = error as ZodError;
          expect(zodError.issues.length).toBeGreaterThan(1);
        }
      });
    });
  });

  describe('ParseResult type discrimination', () => {
    it('success result can be discriminated via ok property', () => {
      const validData = {
        id: '123',
        name: 'John',
        email: 'john@example.com',
      };

      const result: ParseResult<User> = gracefulParse(UserSchema, validData);

      // TypeScript narrowing via ok check
      if (result.ok) {
        // Access data safely - these should be type-safe
        const _id: string = result.data.id;
        const _name: string = result.data.name;
        const _email: string = result.data.email;
        const _age: number | undefined = result.data.age;

        expect(_id).toBe('123');
        expect(_name).toBe('John');
        expect(_email).toBe('john@example.com');
        expect(_age).toBeUndefined();
      } else {
        expect.fail('Result should be ok');
      }
    });

    it('result type union correctly reflects success or failure', () => {
      const validData = { value: 'test' };
      const result = gracefulParse(SimpleSchema, validData);

      // Demonstrate type narrowing
      if (result.ok === true) {
        // Type is { ok: true, data: { value: string } }
        expect(result.data.value).toBe('test');
      } else {
        // Type is { ok: false, error: ZodError | null }
        // This branch won't execute for valid data
        expect.fail('Should be ok');
      }
    });
  });

  describe('edge cases', () => {
    it('handles empty object schema', () => {
      const EmptySchema = z.object({});

      const gracefulResult = gracefulParse(EmptySchema, {});
      expect(gracefulResult.ok).toBe(true);
      if (gracefulResult.ok) {
        expect(gracefulResult.data).toEqual({});
      }

      expect(strictParse(EmptySchema, {})).toEqual({});
    });

    it('handles schema with default values', () => {
      const DefaultSchema = z.object({
        value: z.string().default('default'),
      });

      const result = gracefulParse(DefaultSchema, {});

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toEqual({ value: 'default' });
      }
    });

    it('handles schema with transforms', () => {
      const TransformSchema = z.object({
        value: z.string().transform((v) => v.toUpperCase()),
      });

      const result = gracefulParse(TransformSchema, { value: 'hello' });

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toEqual({ value: 'HELLO' });
      }
    });

    it('handles union schemas', () => {
      const UnionSchema = z.union([
        z.object({ type: z.literal('a'), valueA: z.string() }),
        z.object({ type: z.literal('b'), valueB: z.number() }),
      ]);

      const resultA = gracefulParse(UnionSchema, { type: 'a', valueA: 'test' });
      const resultB = gracefulParse(UnionSchema, { type: 'b', valueB: 42 });

      expect(resultA.ok).toBe(true);
      expect(resultB.ok).toBe(true);

      if (resultA.ok) {
        expect(resultA.data).toEqual({ type: 'a', valueA: 'test' });
      }
      if (resultB.ok) {
        expect(resultB.data).toEqual({ type: 'b', valueB: 42 });
      }
    });

    it('handles discriminated union schemas', () => {
      const DiscriminatedSchema = z.discriminatedUnion('type', [
        z.object({ type: z.literal('success'), data: z.string() }),
        z.object({ type: z.literal('error'), message: z.string() }),
      ]);

      const success = gracefulParse(DiscriminatedSchema, {
        type: 'success',
        data: 'result',
      });
      const error = gracefulParse(DiscriminatedSchema, {
        type: 'error',
        message: 'failed',
      });

      expect(success.ok).toBe(true);
      expect(error.ok).toBe(true);

      if (success.ok) {
        expect(success.data).toEqual({ type: 'success', data: 'result' });
      }
      if (error.ok) {
        expect(error.data).toEqual({ type: 'error', message: 'failed' });
      }
    });

    it('handles array schemas', () => {
      const ArraySchema = z.array(z.number());

      const result = gracefulParse(ArraySchema, [1, 2, 3]);

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toEqual([1, 2, 3]);
      }
    });

    it('handles tuple schemas', () => {
      const TupleSchema = z.tuple([z.string(), z.number(), z.boolean()]);

      const result = gracefulParse(TupleSchema, ['hello', 42, true]);

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toEqual(['hello', 42, true]);
      }
    });

    it('handles record schemas', () => {
      const RecordSchema = z.record(z.string(), z.number());

      const result = gracefulParse(RecordSchema, { a: 1, b: 2, c: 3 });

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toEqual({ a: 1, b: 2, c: 3 });
      }
    });

    it('handles nullable schemas', () => {
      const NullableSchema = z.object({
        value: z.string().nullable(),
      });

      const resultWithValue = gracefulParse(NullableSchema, { value: 'test' });
      const resultWithNull = gracefulParse(NullableSchema, { value: null });

      expect(resultWithValue.ok).toBe(true);
      expect(resultWithNull.ok).toBe(true);

      if (resultWithValue.ok) {
        expect(resultWithValue.data).toEqual({ value: 'test' });
      }
      if (resultWithNull.ok) {
        expect(resultWithNull.data).toEqual({ value: null });
      }
    });

    it('handles refine validations', () => {
      const RefinedSchema = z.object({
        password: z.string().min(8),
        confirmPassword: z.string(),
      }).refine((data) => data.password === data.confirmPassword, {
        message: 'Passwords must match',
        path: ['confirmPassword'],
      });

      const validData = {
        password: 'password123',
        confirmPassword: 'password123',
      };

      const result = gracefulParse(RefinedSchema, validData);

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toEqual(validData);
      }

      // Invalid case — returns { ok: false }
      const invalidData = {
        password: 'password123',
        confirmPassword: 'different',
      };

      const failResult = gracefulParse(RefinedSchema, invalidData);
      expect(failResult.ok).toBe(false);
      if (!failResult.ok) {
        expect(failResult.error).toBeInstanceOf(ZodError);
      }
    });

    it('handles optional fields with explicit undefined', () => {
      const result = gracefulParse(UserSchema, {
        id: '123',
        name: 'Test',
        email: 'test@example.com',
        age: undefined, // explicitly undefined optional field
      });

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data.age).toBeUndefined();
      }
    });
  });

  describe('primitive schemas', () => {
    it('handles boolean schema', () => {
      const BoolSchema = z.boolean();

      const resultTrue = gracefulParse(BoolSchema, true);
      const resultFalse = gracefulParse(BoolSchema, false);

      expect(resultTrue.ok).toBe(true);
      expect(resultFalse.ok).toBe(true);

      if (resultTrue.ok) {
        expect(resultTrue.data).toBe(true);
      }
      if (resultFalse.ok) {
        expect(resultFalse.data).toBe(false);
      }

      const failResult = gracefulParse(BoolSchema, 'true');
      expect(failResult.ok).toBe(false);
      if (!failResult.ok) {
        expect(failResult.error).toBeInstanceOf(ZodError);
      }
    });

    it('handles coerced boolean schema', () => {
      const CoercedBoolSchema = z.coerce.boolean();

      const cases = [
        { input: true, expected: true },
        { input: false, expected: false },
        { input: 'true', expected: true },
        { input: 1, expected: true },
        { input: 0, expected: false },
      ];

      for (const { input, expected } of cases) {
        const result = gracefulParse(CoercedBoolSchema, input);
        expect(result.ok).toBe(true);
        if (result.ok) {
          expect(result.data).toBe(expected);
        }
      }
    });

    it('handles string schema', () => {
      const StringSchema = z.string();

      const result = gracefulParse(StringSchema, 'hello');

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toBe('hello');
      }

      const failResult = gracefulParse(StringSchema, 123);
      expect(failResult.ok).toBe(false);
      if (!failResult.ok) {
        expect(failResult.error).toBeInstanceOf(ZodError);
      }
    });

    it('handles number schema', () => {
      const NumberSchema = z.number();

      const result = gracefulParse(NumberSchema, 42);

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toBe(42);
      }

      const failResult = gracefulParse(NumberSchema, '42');
      expect(failResult.ok).toBe(false);
      if (!failResult.ok) {
        expect(failResult.error).toBeInstanceOf(ZodError);
      }
    });

    it('handles enum schema', () => {
      const EnumSchema = z.enum(['red', 'green', 'blue']);

      const result = gracefulParse(EnumSchema, 'red');

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toBe('red');
      }

      const failResult = gracefulParse(EnumSchema, 'yellow');
      expect(failResult.ok).toBe(false);
      if (!failResult.ok) {
        expect(failResult.error).toBeInstanceOf(ZodError);
      }
    });

    it('handles literal schema', () => {
      const LiteralSchema = z.literal('exact');

      const result = gracefulParse(LiteralSchema, 'exact');

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data).toBe('exact');
      }

      const failResult = gracefulParse(LiteralSchema, 'different');
      expect(failResult.ok).toBe(false);
      if (!failResult.ok) {
        expect(failResult.error).toBeInstanceOf(ZodError);
      }
    });
  });

  describe('comparison: gracefulParse vs strictParse', () => {
    it('both return same data on success', () => {
      const validData = {
        id: '123',
        name: 'John',
        email: 'john@example.com',
      };

      const gracefulResult = gracefulParse(UserSchema, validData);
      const strictResult = strictParse(UserSchema, validData);

      expect(gracefulResult.ok).toBe(true);
      if (gracefulResult.ok) {
        expect(gracefulResult.data).toEqual(strictResult);
      }
    });

    it('gracefulParse returns { ok: false } while strictParse throws on failure', () => {
      const invalidData = { id: 123 }; // invalid

      const result = gracefulParse(UserSchema, invalidData);
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.error).toBeInstanceOf(ZodError);
      }

      expect(() => strictParse(UserSchema, invalidData)).toThrow(ZodError);
    });

    it('gracefulParse uses safeParse internally (never throws)', () => {
      const validData = { value: 'test' };

      // Should not throw for valid data
      expect(() => gracefulParse(SimpleSchema, validData)).not.toThrow();

      // Should also not throw for invalid data
      expect(() => gracefulParse(SimpleSchema, { value: 123 })).not.toThrow();
    });

    it('strictParse uses parse internally (always throws on failure)', () => {
      // strictParse wraps Zod's parse which always throws
      const invalidData = { value: 123 };

      expect(() => strictParse(SimpleSchema, invalidData)).toThrow(ZodError);
    });
  });

  describe('real-world usage patterns', () => {
    it('validates API response structure', () => {
      const ApiResponseSchema = z.object({
        success: z.boolean(),
        data: z.object({
          items: z.array(z.object({
            id: z.string(),
            name: z.string(),
          })),
          total: z.number(),
        }),
        meta: z.object({
          timestamp: z.string(),
        }).optional(),
      });

      const validResponse = {
        success: true,
        data: {
          items: [
            { id: '1', name: 'Item 1' },
            { id: '2', name: 'Item 2' },
          ],
          total: 2,
        },
        meta: {
          timestamp: '2024-01-01T00:00:00Z',
        },
      };

      const result = gracefulParse(ApiResponseSchema, validResponse);

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data.data.items).toHaveLength(2);
        expect(result.data.data.total).toBe(2);
      }
    });

    it('validates user input with custom refinements', () => {
      const RegistrationSchema = z.object({
        username: z.string().min(3).max(20),
        email: z.string().email(),
        password: z.string().min(8),
        confirmPassword: z.string(),
      }).refine((data) => data.password === data.confirmPassword, {
        message: 'Passwords do not match',
        path: ['confirmPassword'],
      });

      const validInput = {
        username: 'johndoe',
        email: 'john@example.com',
        password: 'securepass123',
        confirmPassword: 'securepass123',
      };

      const result = gracefulParse(RegistrationSchema, validInput);

      expect(result.ok).toBe(true);
    });

    it('validates configuration objects', () => {
      const ConfigSchema = z.object({
        apiUrl: z.string().url(),
        timeout: z.number().positive().default(5000),
        retries: z.number().int().min(0).max(10).default(3),
        features: z.object({
          darkMode: z.boolean(),
          betaFeatures: z.boolean(),
        }).default({ darkMode: false, betaFeatures: false }),
      });

      // Minimal config - defaults should be applied
      const minimalConfig = {
        apiUrl: 'https://api.example.com',
      };

      const result = gracefulParse(ConfigSchema, minimalConfig);

      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(result.data.timeout).toBe(5000);
        expect(result.data.retries).toBe(3);
        expect(result.data.features.darkMode).toBe(false);
        expect(result.data.features.betaFeatures).toBe(false);
      }
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// TELEMETRY CONTRACT — what gracefulParse is allowed to report, and what it
// must still be able to report.
// ═══════════════════════════════════════════════════════════════════════════
//
// The end-to-end leak suite lives in
// src/tests/plugins/core/diagnostics/telemetryBoundary.spec.ts (event assembly
// through the real beforeSend). This section pins the unit-level contract of
// the projection itself: the approved fields, the omissions, the bound, the
// union recursion and the parameterized-route hook.

describe('gracefulParse telemetry contract', () => {
  /** Reads the context object handed to the mocked captureException. */
  function lastContext(): Record<string, unknown> {
    const mock = vi.mocked(captureException);
    expect(mock).toHaveBeenCalled();
    return (mock.mock.calls.at(-1)?.[1] ?? {}) as Record<string, unknown>;
  }

  function lastRows(): Array<Record<string, unknown>> {
    return (lastContext().issues ?? []) as Array<Record<string, unknown>>;
  }

  function lastMessage(): string {
    const mock = vi.mocked(captureException);
    return (mock.mock.calls.at(-1)?.[0] as Error).message;
  }

  beforeEach(() => {
    vi.clearAllMocks();
    resetApiRouteContext();
    vi.stubEnv('NODE_ENV', 'production');
    vi.stubEnv('DEV', false as never);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    resetApiRouteContext();
  });

  describe('approved fields', () => {
    it('reports path, code, expected type and received type for a type mismatch', () => {
      gracefulParse(z.object({ record: z.object({ n: z.string() }) }), { record: { n: 7 } }, 'Ctx');

      expect(lastRows()).toEqual([
        { path: 'record.n', code: 'invalid_type', expected: 'string', received: 'number' },
      ]);
    });

    it('preserves array indices in the field path', () => {
      const schema = z.object({ items: z.array(z.object({ v: z.string() })) });

      gracefulParse(schema, { items: [{ v: 'ok' }, { v: 1 }] }, 'Ctx');

      expect(lastRows()[0].path).toBe('items.1.v');
      expect(lastContext().schemaField).toBe('items.1.v');
    });

    it('uses (root) for an issue with an empty path', () => {
      gracefulParse(z.object({ a: z.string() }), 'not-an-object', 'Ctx');

      expect(lastRows()[0].path).toBe('(root)');
    });

    it('reports the TRUE issue count alongside the field paths', () => {
      gracefulParse(z.object({ a: z.string(), b: z.string() }), { a: 1, b: 2 }, 'Ctx');

      expect(lastContext().issueCount).toBe(2);
      expect(lastContext().schemaField).toBe('a,b');
    });
  });

  describe('omissions', () => {
    it('never emits the Zod message', () => {
      gracefulParse(SimpleSchema, { value: 1 }, 'Ctx');

      expect(Object.keys(lastRows()[0])).not.toContain('message');
      expect(JSON.stringify(lastContext())).not.toContain('Invalid input');
    });

    it('never emits the raw failing value', () => {
      gracefulParse(SimpleSchema, { value: 987654321 }, 'Ctx');

      const wire = JSON.stringify({ message: lastMessage(), context: lastContext() });
      expect(wire).not.toContain('987654321');
      expect(lastRows()[0].received).toBe('number');
    });

    it('drops unrecognized payload KEY NAMES and reports only their count', () => {
      const strict = z.strictObject({ id: z.string() });

      gracefulParse(strict, { id: 'x', authorization_token: 'sk_live_XKCD', tracking: 1 }, 'Ctx');

      const wire = JSON.stringify({ message: lastMessage(), context: lastContext() });
      expect(wire).not.toContain('authorization_token');
      expect(wire).not.toContain('sk_live_XKCD');
      expect(wire).not.toContain('tracking');

      // The count lives on its OWN key. It used to reuse `issueCount`, which
      // also means "true issue total" at the top level and on the truncation
      // sentinel — three incompatible meanings on one name, so an operator
      // reading `{code:"unrecognized_keys", issueCount:2}` beside a top-level
      // `issueCount:1` got a wrong answer rather than a confusing one.
      expect(lastRows()[0]).toMatchObject({ code: 'unrecognized_keys', key_count: 2 });
      expect(lastRows()[0]).not.toHaveProperty('issueCount');
      expect(lastContext().issueCount).toBe(1);
    });

    // CONTRACT CHANGE, pass three. The accepted literal set used to be dropped
    // with the payload values, on the theory that everything attached to an
    // issue is suspect. It is not: every `z.enum` / `z.literal` under
    // src/schemas is built from a module-level `as const` tuple or a string
    // literal, so `values` is .ts SOURCE, not wire data. Dropping it left enum
    // drift — the same bug class as the epoch bug this branch exists for —
    // strictly less diagnosable than before the branch, because the event could
    // not answer "what does the schema accept?".
    //
    // The payload value is still refused, which is the half that was ever the
    // leak. And the emission fails CLOSED (see `safeConstant`) if a set ever
    // starts carrying something a scrub pass recognizes.
    it('emits the accepted literal set but never the rejected payload value', () => {
      const schema = z.object({ mode: z.enum(['alpha', 'omega']) });

      gracefulParse(schema, { mode: 'sigma' }, 'Ctx');

      const wire = JSON.stringify({ message: lastMessage(), context: lastContext() });
      expect(wire).not.toContain('sigma');
      expect(lastRows()[0]).toMatchObject({
        path: 'mode',
        code: 'invalid_value',
        expected: '"alpha"|"omega"',
        received: 'string',
      });
    });

    it('scrubs a payload-derived record KEY out of the extras rows, not just the tag', () => {
      // `event.extra` is UNSCRUBBED BY CONSTRUCTION — `createBeforeSendHandler`
      // never touches it. The tag was being scrubbed here while `issues` rode
      // out untouched, so a `z.record()` path segment (which IS the payload
      // key) reached Sentry through the unprotected half.
      gracefulParse(z.record(z.string(), z.number()), { 'alice@example.com': 'nope' }, 'Ctx');

      const wire = JSON.stringify({ message: lastMessage(), context: lastContext() });
      expect(wire).not.toContain('alice@example.com');
      expect(lastRows()[0].path).toBe('[REDACTED]');
      expect(lastContext().schemaField).toBe('[REDACTED]');
    });

    it('emits only primitive leaves, so nothing can normalize to [Object]/[Array]', () => {
      gracefulParse(z.object({ a: z.string(), b: z.number() }), { a: 1, b: 'x' }, 'Ctx');

      for (const row of lastRows()) {
        for (const value of Object.values(row)) {
          expect(['string', 'number', 'boolean']).toContain(typeof value);
        }
      }
    });
  });

  describe('custom messages that interpolate payload data', () => {
    const leaky = z.object({
      token: z.any().superRefine((val, ctx) => {
        ctx.addIssue({ code: 'custom', message: `rejected ${String(val)}` });
      }),
    });

    it('reports the redaction SENTINEL, not the message text, when a shape is recognized', () => {
      gracefulParse(leaky, { token: 'tester@example.com' }, 'Ctx');

      expect(lastMessage()).toContain('[EMAIL_REDACTED]');
      expect(lastMessage()).not.toContain('tester@example.com');
      expect(JSON.stringify(lastContext())).not.toContain('tester@example.com');
    });

    it('emits nothing at all when the interpolated value is an unrecognized shape', () => {
      gracefulParse(leaky, { token: 'sk_live_51H8xQe0000LEAKME' }, 'Ctx');

      const wire = JSON.stringify({ message: lastMessage(), context: lastContext() });
      expect(wire).not.toContain('sk_live_');
      expect(wire).not.toContain('rejected');
    });
  });

  describe('invalid_union recursion', () => {
    const union = z.object({
      payload: z.union([z.object({ a: z.string() }), z.object({ b: z.number() })]),
    });

    it('projects the union member issues, not just the opaque parent', () => {
      gracefulParse(union, { payload: { a: 1 } }, 'Ctx');

      const rows = lastRows();
      expect(rows[0]).toMatchObject({ path: 'payload', code: 'invalid_union' });

      // Member paths are re-based onto the union's own path.
      expect(rows.map((r) => r.path)).toContain('payload.a');
      expect(rows.map((r) => r.path)).toContain('payload.b');
      expect(rows.find((r) => r.path === 'payload.a')).toMatchObject({
        code: 'invalid_type',
        expected: 'string',
        received: 'number',
      });
    });

    it('carries no member message into the event', () => {
      gracefulParse(union, { payload: { a: 1 } }, 'Ctx');

      expect(JSON.stringify(lastContext())).not.toContain('Invalid input');
    });
  });

  describe('bounding', () => {
    it('caps the projected rows, keeps the true total, and flags the truncation', () => {
      const shape: Record<string, z.ZodTypeAny> = {};
      const payload: Record<string, unknown> = {};
      for (let i = 0; i < MAX_PROJECTED_ISSUES + 5; i += 1) {
        shape[`f${i}`] = z.string();
        payload[`f${i}`] = i;
      }

      gracefulParse(z.object(shape), payload, 'Ctx');

      const rows = lastRows();
      const real = rows.filter((r) => r.code !== 'projection_truncated');
      const marker = rows.find((r) => r.code === 'projection_truncated');

      expect(real).toHaveLength(MAX_PROJECTED_ISSUES);
      expect(marker).toMatchObject({ issueCount: MAX_PROJECTED_ISSUES + 5 });
      expect(lastContext().issueCount).toBe(MAX_PROJECTED_ISSUES + 5);
      expect(lastMessage()).toContain('truncated');
    });

    it('honours an explicit maxIssues override', () => {
      const projection = projectSchemaIssues(
        z.object({ a: z.string(), b: z.string(), c: z.string() }).safeParse({}).error!,
        {},
        'Ctx',
        2
      );

      expect(projection.issueCount).toBe(3);
      expect(projection.truncated).toBe(true);
      expect(projection.rows.filter((r) => r.code !== 'projection_truncated')).toHaveLength(2);
    });

    it('caps the schemaField tag length', () => {
      const shape: Record<string, z.ZodTypeAny> = {};
      const payload: Record<string, unknown> = {};
      for (let i = 0; i < 40; i += 1) {
        shape[`averyverylongfieldname_${i}`] = z.string();
        payload[`averyverylongfieldname_${i}`] = i;
      }

      gracefulParse(z.object(shape), payload, 'Ctx');

      expect(String(lastContext().schemaField).length).toBeLessThanOrEqual(200);
    });
  });

  describe('parameterized api route', () => {
    it('is omitted when no route context has been installed', () => {
      gracefulParse(SimpleSchema, { value: 1 }, 'Ctx');

      expect(lastContext()).not.toHaveProperty('apiRoute');
    });

    it('parameterizes the axios slot, keeping the organization id out', () => {
      setCurrentApiRoute('/api/colonel/organizations/org_9f3a2b1c8d7e6f50?expand=1');

      gracefulParse(SimpleSchema, { value: 1 }, 'Ctx');

      expect(lastContext().apiRoute).toBe('/api/colonel/organizations/:org_id');
      expect(JSON.stringify(lastContext())).not.toContain('org_9f3a2b1c8d7e6f50');
    });

    it('accepts an explicit override from the caller', () => {
      gracefulParse(SimpleSchema, { value: 1 }, 'Ctx', {
        apiRoute: '/api/v3/receipts/:key',
      });

      expect(lastContext().apiRoute).toBe('/api/v3/receipts/:key');
    });

    it('RE-PARAMETERIZES an explicit override, as its contract always claimed', () => {
      // The option's TSDoc said "NEVER pass a resolved URL — it is
      // re-parameterized and scrubbed defensively". Only the resolver path did
      // that; this branch scrubbed and capped without parameterizing, so a
      // caller who made the exact mistake the contract warns about put a tenant
      // id into an extras field that nothing downstream scrubs. The spec here
      // only ever exercised an already-parameterized value, which is why the
      // gap survived two passes.
      gracefulParse(SimpleSchema, { value: 1 }, 'Ctx', {
        apiRoute: '/api/colonel/organizations/org_9f3a2b1c8d7e6f50',
      });

      expect(lastContext().apiRoute).toBe('/api/colonel/organizations/:org_id');
      expect(JSON.stringify(lastContext())).not.toContain('org_9f3a2b1c8d7e6f50');
    });

    it('keeps an end-user IP out of an override built from a resolved URL', () => {
      // AdminBannedIps.vue:123 builds exactly this URL and gracefulParses the
      // response. An end-user IP in extras is what actorIdentity pins
      // `ip_address: null` to prevent.
      gracefulParse(SimpleSchema, { value: 1 }, 'Ctx', {
        apiRoute: '/api/colonel/banned-ips/203.0.113.5',
      });

      expect(JSON.stringify(lastContext())).not.toContain('203.0.113.5');
    });

    it('re-parameterizes and scrubs whatever a custom resolver returns', () => {
      setApiRouteResolver(() => '/api/colonel/organizations/org_9f3a2b1c8d7e6f50/domains/12');

      gracefulParse(SimpleSchema, { value: 1 }, 'Ctx');

      expect(lastContext().apiRoute).toBe(
        '/api/colonel/organizations/:org_id/domains/:domain_id'
      );
    });

    it('treats a throwing resolver as "unknown" rather than breaking reporting', () => {
      setApiRouteResolver(() => {
        throw new Error('boom');
      });

      expect(() => gracefulParse(SimpleSchema, { value: 1 }, 'Ctx')).not.toThrow();
      expect(lastContext()).not.toHaveProperty('apiRoute');
    });

    it('parameterizeApiPath leaves literal route words alone', () => {
      expect(parameterizeApiPath('/api/v3/status')).toBe('/api/v3/status');
      expect(parameterizeApiPath('/api/colonel/organizations')).toBe(
        '/api/colonel/organizations'
      );
    });

    describe('a child of a known collection is an identifier BY POSITION', () => {
      // REGRESSION: `looksLikeIdentifier` is a SHAPE test, and the collection
      // map used to be consulted only AFTER it passed. A short, all-lowercase,
      // digit-free segment therefore failed every shape branch and shipped
      // verbatim into `apiRoute` — which is an INDEXED, searchable dimension —
      // even though its parent was `users`, `members` or `domains`. Executed
      // against the pre-fix tree, all three of these returned the input
      // unchanged.
      it.each([
        ['/api/colonel/users/alice/diagnostics', '/api/colonel/users/:user_id/diagnostics'],
        [
          '/api/organizations/onabc/members/bobsmith',
          '/api/organizations/:org_id/members/:member_id',
        ],
        ['/api/domains/acmecorp/brand', '/api/domains/:domain_id/brand'],
        ['/api/colonel/users/ur/role', '/api/colonel/users/:user_id/role'],
        ['/api/invite/tok/signup', '/api/invite/:token/signup'],
      ])('%s -> %s', (input, expected) => {
        expect(parameterizeApiPath(input)).toBe(expected);
      });

      it('keeps the short id out of the emitted extras field entirely', () => {
        setCurrentApiRoute('/api/colonel/users/alice/diagnostics');

        gracefulParse(SimpleSchema, { value: 1 }, 'Ctx');

        expect(JSON.stringify(lastContext())).not.toContain('alice');
      });

      it('is fail-CLOSED: an unreviewed action word is parameterized, not passed', () => {
        // The cost of the positional rule, asserted so it is a decision rather
        // than a surprise: a real action route that nobody added to
        // COLLECTION_CHILD_LITERALS loses aggregation granularity. That is the
        // correct direction to fail.
        expect(parameterizeApiPath('/api/v3/secret/unlisted-action')).toBe(
          '/api/v3/secret/:key'
        );
      });

      it('still keeps the reviewed literal action words legible', () => {
        expect(parameterizeApiPath('/api/v3/secret/conceal')).toBe('/api/v3/secret/conceal');
        expect(parameterizeApiPath('/api/v3/secret/generate')).toBe('/api/v3/secret/generate');
        expect(parameterizeApiPath('/api/v2/secret/conceal')).toBe('/api/v2/secret/conceal');
        expect(parameterizeApiPath('/api/v3/receipt/recent')).toBe('/api/v3/receipt/recent');
        expect(parameterizeApiPath('/api/domains/add')).toBe('/api/domains/add');
        expect(parameterizeApiPath('/api/colonel/domains/orphaned')).toBe(
          '/api/colonel/domains/orphaned'
        );
        expect(parameterizeApiPath('/api/domains/dns-widget/token')).toBe(
          '/api/domains/dns-widget/token'
        );
        expect(parameterizeApiPath('/api/incoming/config')).toBe('/api/incoming/config');
        expect(parameterizeApiPath('/api/incoming/secret')).toBe('/api/incoming/secret');
        // `status` and `validate` were MISSING from COLLECTION_CHILD_LITERALS,
        // so three live endpoints collapsed into a param. Re-derived from
        // apps/api/*/routes.txt; see collectionChildLiterals.spec.ts, which
        // regenerates the whole set rather than spot-checking it.
        expect(parameterizeApiPath('/api/v2/secret/status')).toBe('/api/v2/secret/status');
        expect(parameterizeApiPath('/api/v3/secret/status')).toBe('/api/v3/secret/status');
        expect(parameterizeApiPath('/api/incoming/validate')).toBe('/api/incoming/validate');
      });

      it('does not carry a literal for a route that does not exist', () => {
        // This assertion used to read
        // `parameterizeApiPath('/api/incoming/sso/mailer') === '/api/incoming/sso/mailer'`,
        // pinning a route that is not in the table: apps/api/incoming/routes.txt
        // declares /config, /secret and /validate only, and every real `sso`
        // route hangs off a resolved id (`/api/domains/:extid/sso`), whose
        // parent is the extid rather than a mapped collection. `sso` was
        // therefore an inert entry justified by invented evidence, and it is
        // gone. A non-route under a mapped collection now parameterizes, which
        // is the fail-closed default.
        expect(parameterizeApiPath('/api/incoming/sso/mailer')).toBe('/api/incoming/:key/mailer');
        // The real sso route is unaffected — its parent was never `domains`.
        expect(parameterizeApiPath('/api/domains/dom4bcdefghijk/sso')).toBe(
          '/api/domains/:domain_id/sso'
        );
      });

      it('never rewrites a segment that is already a route parameter', () => {
        expect(parameterizeApiPath('/api/organizations/:extid/members/:member_extid')).toBe(
          '/api/organizations/:extid/members/:member_extid'
        );
        expect(parameterizeApiPath('/api/v1/private/$key/burn')).toBe(
          '/api/v1/private/$key/burn'
        );
        // The `{param}` spelling survives as a parameter but is emitted
        // percent-encoded: `new URL().pathname` escapes braces, and the decoded
        // form is used for MATCHING ONLY, never emitted. The contract that
        // matters is that it is not rewritten into `:key`.
        expect(parameterizeApiPath('/api/v1/private/{key}/burn')).toBe(
          '/api/v1/private/%7Bkey%7D/burn'
        );
      });

      it('does not parameterize a collection segment that has no known parent', () => {
        expect(parameterizeApiPath('/api/colonel/users')).toBe('/api/colonel/users');
        expect(parameterizeApiPath('/api/organizations')).toBe('/api/organizations');
      });
    });
  });

  describe('dev/test console path', () => {
    it('logs the projected rows, never the raw issues', () => {
      vi.unstubAllEnvs();
      vi.stubEnv('NODE_ENV', 'test');
      const spy = vi.spyOn(console, 'error').mockImplementation(() => {});

      gracefulParse(z.strictObject({ id: z.string() }), { id: 1, secret_key: 'shh' }, 'Ctx');

      const [message, rows] = spy.mock.calls.at(-1) as [string, unknown[]];
      expect(message).toContain('Schema validation failed for Ctx');
      expect(JSON.stringify(rows)).not.toContain('secret_key');
      expect(JSON.stringify(rows)).not.toContain('Invalid input');
      expect(captureException).not.toHaveBeenCalled();

      spy.mockRestore();
    });

    it('still hands the caller the full ZodError for local inspection', () => {
      vi.unstubAllEnvs();
      vi.stubEnv('NODE_ENV', 'test');
      const spy = vi.spyOn(console, 'error').mockImplementation(() => {});

      const result = gracefulParse(SimpleSchema, { value: 1 }, 'Ctx');

      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.error).toBeInstanceOf(ZodError);
        expect(result.error!.issues[0].message).toBeTruthy();
      }

      spy.mockRestore();
    });
  });

  describe('backward compatibility', () => {
    it('still accepts the three-argument form', () => {
      expect(() => gracefulParse(SimpleSchema, { value: 1 }, 'Ctx')).not.toThrow();
      expect(lastContext().schema).toBe('Ctx');
    });

    it('still accepts the two-argument form and omits the schema tag', () => {
      gracefulParse(SimpleSchema, { value: 1 });

      expect(lastContext().schema).toBeUndefined();
      expect(lastMessage()).toContain('Schema validation failed —');
    });
  });
});
