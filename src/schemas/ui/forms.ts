// src/schemas/ui/forms.ts

/**
 * Form-related types for schema-aware form handling
 *
 * Note: FormSubmissionOptions is a TypeScript utility type that accepts
 * Zod schemas as generic parameters. It doesn't define a Zod schema itself
 * because it's configuration passed in TypeScript code, not external data
 * that needs runtime validation.
 */

import type { z } from 'zod';

/**
 * Form submission configuration options
 *
 * Generic type that accepts a Zod schema for response validation.
 * The schema parameter enables type-safe handling of API responses.
 */
export type FormSubmissionOptions<ResponseSchema extends z.ZodType = z.ZodAny> = {
  /**
   * URL to submit the form to. If not provided, form's action attribute will be used
   */
  url?: string;

  /**
   * Message to display on successful form submission
   */
  successMessage: string;

  /**
   * URL to redirect to after successful form submission
   */
  redirectUrl?: string;

  /**
   * Delay in milliseconds before redirecting (default: 3000)
   */
  redirectDelay?: number;

  /**
   * Optional function to get form data instead of using standard form submission
   */
  getFormData?: () => FormData | URLSearchParams;

  /**
   * Optional schema to validate the response data
   */
  schema?: ResponseSchema;

  /**
   * Called after successful form submission with the transformed response data
   */
  onSuccess?: (data: z.infer<ResponseSchema>) => void | Promise<void>;

  /**
   * Called after failed form submission with the error response
   */
  onError?: (error: unknown) => void | Promise<void>;
};
