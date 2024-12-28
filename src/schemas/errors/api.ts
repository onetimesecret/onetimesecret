export const enum HttpStatus {
  UNAUTHORIZED = 401,
  FORBIDDEN = 403,
  NOT_FOUND = 404,
  VALIDATION_ERROR = 422,
  RATE_LIMIT = 429,
  SERVER_ERROR = 500,
}

export interface TechnicalError {
  kind: 'technical';
  code: number;
  message: string;
  userMessage: string;
  retryable: boolean;
  details?: unknown;
}

export function createApiError(
  status: number,
  message: string,
  userMessage?: string
): TechnicalError {
  return {
    kind: 'technical',
    code: status,
    message,
    userMessage: userMessage ?? getDefaultUserMessage(status),
    retryable: status >= 500 || status === HttpStatus.RATE_LIMIT,
  };
}

function getDefaultUserMessage(status: number): string {
  switch (status) {
    case HttpStatus.UNAUTHORIZED:
      return 'Please sign in again to continue';
    case HttpStatus.NOT_FOUND:
      return 'The requested item could not be found';
    case HttpStatus.RATE_LIMIT:
      return 'Please wait a moment before trying again';
    default:
      return 'Something went wrong. Please try again later.';
  }
}

export const isTechnicalError = (error: unknown): error is TechnicalError =>
  typeof error === 'object' &&
  error != null &&
  'kind' in error &&
  error.kind === 'technical';

export function handleError(error: unknown): TechnicalError | DomainError {
  if (isDomainError(error) || isTechnicalError(error)) {
    return error;
  }

  if (error instanceof z.ZodError) {
    return createApiError(
      HttpStatus.VALIDATION_ERROR,
      'Validation failed',
      'Please check your input and try again'
    );
  }

  if (error instanceof AxiosError) {
    return error.response
      ? createApiError(error.response.status, error.message)
      : createApiError(0, error.message, 'Unable to connect to the server');
  }

  return createApiError(
    HttpStatus.SERVER_ERROR,
    error instanceof Error ? error.message : 'An unexpected error occurred'
  );
}
