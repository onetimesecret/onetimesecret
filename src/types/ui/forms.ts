import type { z } from 'zod/v4';

export type FormSubmissionOptions<ResponseSchema extends z.ZodTypeAny = z.ZodAny> = {
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
