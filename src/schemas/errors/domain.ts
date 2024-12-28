// schemas/errors/domain.ts

// import { ErrorCode } from './api';

export class DomainError extends Error {
  constructor(
    public code: string,
    message: string,
    public userMessage: string,
    public retryable: boolean = false,
    public details?: unknown
  ) {
    super(message);
    this.name = this.constructor.name;
  }
}

// Define specific error types for common business rules
export class SecretError extends DomainError {
  static readonly ALREADY_VIEWED = 'ALREADY_VIEWED';
  static readonly EXPIRED = 'EXPIRED';
  static readonly INVALID_PASSPHRASE = 'INVALID_PASSPHRASE';
  static readonly BURN_FAILED = 'BURN_FAILED';

  constructor(code: string, message: string, userMessage: string, details?: unknown) {
    super(code, message, userMessage, false, details);
  }

  static alreadyViewed() {
    return new SecretError(
      this.ALREADY_VIEWED,
      'Secret has already been viewed',
      'This secret is no longer available'
    );
  }

  static expired() {
    return new SecretError(
      this.EXPIRED,
      'Secret has expired',
      'This secret has expired and is no longer available'
    );
  }

  static invalidPassphrase() {
    return new SecretError(
      this.INVALID_PASSPHRASE,
      'Invalid passphrase provided',
      'The provided passphrase is incorrect'
    );
  }

  static burnFailed(details?: unknown) {
    return new SecretError(
      this.BURN_FAILED,
      'Failed to burn secret',
      'Unable to delete the secret at this time',
      details
    );
  }
}

export class QuotaError extends DomainError {
  static readonly RATE_LIMIT = 'RATE_LIMIT';
  static readonly STORAGE_LIMIT = 'STORAGE_LIMIT';

  constructor(
    code: string,
    message: string,
    userMessage: string,
    retryable: boolean = true,
    details?: unknown
  ) {
    super(code, message, userMessage, retryable, details);
  }

  static rateLimit(resetTime: Date) {
    return new QuotaError(
      this.RATE_LIMIT,
      'Rate limit exceeded',
      'Please wait a moment before trying again',
      true,
      { resetTime }
    );
  }

  static storageLimit() {
    return new QuotaError(
      this.STORAGE_LIMIT,
      'Storage limit reached',
      'You have reached your storage limit. Please delete some secrets to create new ones.',
      false
    );
  }
}

// Helper to check if an error is a domain error
export function isDomainError(error: unknown): error is DomainError {
  return error instanceof DomainError;
}

// Helper to determine if error is user-actionable
export function isUserActionable(error: DomainError): boolean {
  return (
    error instanceof QuotaError ||
    (error instanceof SecretError && error.code === SecretError.INVALID_PASSPHRASE)
  );
}
