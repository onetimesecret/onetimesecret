

export type FormSubmissionOptions = {
  url?: string;
  successMessage: string;
  redirectUrl?: string;
  redirectDelay?: number;
  getFormData?: () => FormData | URLSearchParams;
  onSuccess?: (data: unknown) => void | Promise<void>;
  onError?: (data: unknown) => void | Promise<void>;
};
