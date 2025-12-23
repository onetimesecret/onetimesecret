// src/tests/composables/useEntitlementError.spec.ts

import { describe, it, expect } from 'vitest';
import { useEntitlementError } from '@/shared/composables/useEntitlementError';
import type { ApplicationError } from '@/schemas/errors';

describe('useEntitlementError', () => {
  it('should detect upgrade_required error type', () => {
    const error: ApplicationError = {
      name: 'ApplicationError',
      message: 'Member limit reached. Upgrade your plan to invite more members.',
      type: 'human',
      severity: 'error',
      code: 400,
      details: {
        error_type: 'upgrade_required',
        field: 'email',
        details: {},
      },
    };

    const { isUpgradeRequired, errorMessage, field } = useEntitlementError(error);

    expect(isUpgradeRequired.value).toBe(true);
    expect(errorMessage.value).toBe('Member limit reached. Upgrade your plan to invite more members.');
    expect(field.value).toBe('email');
  });

  it('should not detect upgrade_required for regular errors', () => {
    const error: ApplicationError = {
      name: 'ApplicationError',
      message: 'Invalid email format',
      type: 'human',
      severity: 'error',
      code: 400,
      details: {
        field: 'email',
      },
    };

    const { isUpgradeRequired } = useEntitlementError(error);

    expect(isUpgradeRequired.value).toBe(false);
  });

  it('should handle null error gracefully', () => {
    const { isUpgradeRequired, errorMessage, field } = useEntitlementError(null);

    expect(isUpgradeRequired.value).toBe(false);
    expect(errorMessage.value).toBe('');
    expect(field.value).toBe('');
  });

  it('should handle non-object error gracefully', () => {
    const { isUpgradeRequired, errorMessage, field } = useEntitlementError('string error');

    expect(isUpgradeRequired.value).toBe(false);
    expect(errorMessage.value).toBe('');
    expect(field.value).toBe('');
  });

  it('should extract error details', () => {
    const error: ApplicationError = {
      name: 'ApplicationError',
      message: 'Upgrade required',
      type: 'human',
      severity: 'error',
      code: 400,
      details: {
        error_type: 'upgrade_required',
        field: 'members',
        details: {
          current_limit: 5,
          requested_action: 'invite',
        },
      },
    };

    const { errorDetails } = useEntitlementError(error);

    expect(errorDetails.value).toEqual({
      current_limit: 5,
      requested_action: 'invite',
    });
  });
});
