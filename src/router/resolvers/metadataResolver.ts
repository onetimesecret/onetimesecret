// src/router/resolvers/metadataResolver.ts
import { useMetadataStore } from '@/stores/metadataStore';
import type { AsyncDataResult, MetadataRecordApiResponse } from '@/types/api/responses';
import { NotFoundError } from '@/utils/errors';
import type { NavigationGuardNext, RouteLocationNormalized } from 'vue-router';

export async function resolveMetadata(
  to: RouteLocationNormalized,
  _from: RouteLocationNormalized,
  next: NavigationGuardNext
) {
  const metadataKey = to.params.metadataKey as string;
  const store = useMetadataStore();

  try {
    const result = await store.fetchOne(metadataKey, true);
    if (!result && !store.currentRecord) {
      throw new NotFoundError(`Metadata not found: ${metadataKey}`);
    }

    // Use either the result or fallback to store state
    const initialData: AsyncDataResult<MetadataRecordApiResponse> = {
      status: 200,
      data: {
        success: true,
        record: result?.record || store.currentRecord,
        details: result?.details || store.details
      },
      error: store.error
    };

    to.meta.initialData = initialData;
    next();
  } catch (error) {
    console.error('Failed to load metadata:', error);
    const status = error instanceof NotFoundError ? 404 : 500;

    to.meta.initialData = {
      status,
      data: null,
      error: error instanceof Error ? error.message : 'Failed to load metadata'
    };

    if (status === 404 && to.name === 'Burn secret') {
      next({ name: 'Not Found', replace: true });
    } else {
      next();
    }
  }
}
