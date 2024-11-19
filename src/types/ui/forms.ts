export type FormSubmissionOptions<T = unknown> = {
  url?: string;
  successMessage: string;
  redirectUrl?: string;
  redirectDelay?: number;
  getFormData?: () => FormData | URLSearchParams;
  onSuccess?: (data: T) => void | Promise<void>;
  onError?: (data: unknown) => void | Promise<void>;
};
