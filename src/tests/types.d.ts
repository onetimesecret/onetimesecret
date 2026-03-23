// src/tests/types.d.ts

import type { CustomDomainDetails } from '@/schemas/api/v2/responses';
import type { CustomDomain } from '@/schemas/shapes/v2';
import type { Mock } from 'vitest';
import type { ComputedRef, Ref } from 'vue';

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
    init: Mock;
    records: Ref<CustomDomain[]>;
    details: Ref<CustomDomainDetails | null>;
    count: Ref<number>;
    domains: ComputedRef<CustomDomain[]>;
    initialized: boolean;
    recordCount: Mock;
    addDomain: Mock;
    deleteDomain: Mock;
    getDomain: Mock;
    verifyDomain: Mock;
    updateDomain: Mock;
    updateDomainBrand: Mock;
    getBrandSettings: Mock;
    updateBrandSettings: Mock;
    uploadLogo: Mock;
    fetchLogo: Mock;
    removeLogo: Mock;
    fetchList: Mock;
    refreshRecords: Mock;
    $reset: Mock;
    isLoading: Ref<boolean>;
    error: Ref<Error | null>;
  };
  notificationsStore: {
    show: Mock;
  };
}
