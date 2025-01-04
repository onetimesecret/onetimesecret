import type { CustomDomain } from '@/schemas/models/domain';
import type { Mock } from 'vitest';
import type { Ref } from 'vue';

export interface MockDependencies {
  router: {
    back: Mock;
    push: Mock;
  };
  confirmDialog: Mock;
  errorHandler: {
    handleError: Mock;
    wrap: Mock;
    createError: Mock;
  };
  domainsStore: {
    domains: Ref<Record<string, CustomDomain>>;
    addDomain: Mock;
    deleteDomain: Mock;
    isLoading: Ref<boolean>;
    error: Ref<Error | null>;
  };
  notificationsStore: {
    show: Mock;
  };
}
