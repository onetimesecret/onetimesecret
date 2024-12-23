import type { MetadataRecords } from '@/schemas/api/endpoints';
import type { MetadataRecordsDetails } from '@/schemas/api/endpoints/recent';
import { responseSchemas } from '@/schemas/api/responses';
import { createApi } from '@/utils/api';
import { ref, type Ref } from 'vue';

const api = createApi();

export function useMetadataList() {
  const records: Ref<MetadataRecords[]> = ref([]);
  const details: Ref<MetadataRecordsDetails | null> = ref(null);
  const isLoading = ref(false);
  const abortController = ref<AbortController | null>(null);

  async function fetchList() {
    if (abortController.value) {
      abortController.value.abort();
    }
    abortController.value = new AbortController();
    isLoading.value = true;

    try {
      const response = await api.get('/api/v2/private/recent', {
        signal: abortController.value.signal,
      });

      const validated = responseSchemas.metadataList.parse(response.data);
      records.value = validated.records;
      details.value = validated.details;

      return validated;
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        console.debug('Metadata list fetch aborted');
        return;
      }
      throw createApiError(
        'SERVER',
        'SERVER_ERROR',
        error instanceof Error ? error.message : 'Failed to fetch metadata list'
      );
    } finally {
      isLoading.value = false;
      abortController.value = null;
    }
  }

  return {
    records,
    details,
    isLoading,
    fetchList,
  };
}
