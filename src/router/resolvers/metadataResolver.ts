// src/router/resolvers/metadataResolver.ts
import { useMetadataStore } from '@/stores/metadataStore';
import type { AsyncDataResult, MetadataDataApiResponse } from '@/types';
import type { NavigationGuardNext, RouteLocationNormalized } from 'vue-router';

export async function resolveMetadata(
  to: RouteLocationNormalized,
  _from: RouteLocationNormalized,
  next: NavigationGuardNext
) {
  const metadataKey = to.params.metadataKey as string;
  const store = useMetadataStore();

  try {
    const result = await store.fetchOne(metadataKey);

    const initialData: AsyncDataResult<MetadataDataApiResponse> = {
      status: 200,
      data: {
        record: result.record,
        details: result.details
      },
      error: null
    };

    to.meta.initialData = initialData;
    next();
  } catch (error) {
    console.error('Failed to load metadata:', error);

    to.meta.initialData = {
      status: error instanceof Error ? 500 : 404,
      data: null,
      error: error instanceof Error ? error.message : 'Failed to load metadata'
    };
    next();
  }
}
