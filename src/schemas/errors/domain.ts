// schemas/errors/domain.ts
export const enum DomainErrorCode {
  ALREADY_VIEWED = 'ALREADY_VIEWED',
  EXPIRED = 'EXPIRED',
  INVALID_PASSPHRASE = 'INVALID_PASSPHRASE',
  BURN_FAILED = 'BURN_FAILED',
  RATE_LIMIT = 'RATE_LIMIT',
  STORAGE_LIMIT = 'STORAGE_LIMIT',
}

export interface DomainError {
  kind: 'domain';
  code: string;
  message: string;
  userMessage: string;
  retryable: boolean;
  details?: unknown;
}

export function createDomainError(
  code: DomainErrorCode,
  message: string,
  userMessage: string,
  details?: unknown
): DomainError {
  return {
    kind: 'domain',
    code,
    message,
    userMessage,
    retryable: false,
    details,
  };
}

export const isDomainError = (error: unknown): error is DomainError =>
  typeof error === 'object' &&
  error != null &&
  'kind' in error &&
  error.kind === 'domain';
