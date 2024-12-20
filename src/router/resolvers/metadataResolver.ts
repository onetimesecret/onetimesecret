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

    // Ensure we have a complete metadata record with all required fields
    if (!result?.record ||
        !('natural_expiration' in result.record) ||
        !('expiration' in result.record) ||
        !('share_path' in result.record) ||
        !('burn_path' in result.record) ||
        !('metadata_path' in result.record) ||
        !('share_url' in result.record) ||
        !('metadata_url' in result.record) ||
        !('burn_url' in result.record)) {
      throw new NotFoundError(`Complete metadata not found: ${metadataKey}`);
    }

    // Ensure details are of the correct type
    const details = result.details && result.details.type === 'record' ? result.details : undefined;

    // Use API response which has the complete record type
    const initialData: AsyncDataResult<MetadataRecordApiResponse> = {
      status: 200,
      data: {
        success: true,
        shrimp: '',
        record: result.record,
        details
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
