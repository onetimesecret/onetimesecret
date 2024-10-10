// src/composables/useFetchData.ts
import { ref, Ref, computed } from 'vue';
import type { ApiRecordResponse, ApiRecordsResponse, BaseApiRecord, DetailsType } from '@/types/onetime.d.ts';

interface FetchDataOptions<T extends BaseApiRecord> {
  url: string;

  /**
   * Type definition for the onSuccess callback function.
   * @param data - The array of data items of type T.
   * @param details - Additional details of type DetailsType, which is optional.
   */
  onSuccess?: (data: T[], details?: DetailsType) => void;

  /**
   * Type definition for the onError callback function.
   * @param error - The error object.
   * @param status - The HTTP status code, which is optional.
   */
  onError?: (error: Error, status?: number | null) => void;
}

export function useFetchData<T extends BaseApiRecord>({ url, onSuccess, onError }: FetchDataOptions<T>) {
  const records = ref<T[]>([]) as Ref<T[]>;
  const details = ref<DetailsType>(null);
  const isLoading = ref(false);
  const error = ref('');
  const count = ref<number>(0);
  const custid = ref<string | null>(null);
  const status = ref<number | null>(null);

  const fetchData = async () => {
    isLoading.value = true;
    error.value = '';
    status.value = null;

    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });

      status.value = response.status;

      if (!response.ok) {
        throw new Error(`Failed to fetch data from ${url}`);
      }

      const jsonData: ApiRecordResponse<T> | ApiRecordsResponse<T> = await response.json();

      if ('record' in jsonData) {
        records.value = [jsonData.record];
        count.value = 1;
        details.value = jsonData.details || null;

      } else if ('records' in jsonData) {
        records.value = jsonData.records;
        count.value = jsonData.count;
        custid.value = jsonData.custid;
        details.value = jsonData.details || null;

      } else {
        throw new Error('Unexpected response format');
      }

      if (onSuccess) {
        onSuccess(records.value, details.value);
      }

    } catch (err: unknown) {
      if (err instanceof Error) {
        error.value = err.message;
      } else {
        console.error('An unexpected error occurred', err);
        error.value = 'An unexpected error occurred';
      }

      if (onError) {
        onError(err as Error, status.value);
      }

    } finally {
      isLoading.value = false;
    }
  };

  return {
    records,
    details,
    isLoading,
    error,
    count,
    custid,
    status,
    fetchData,
  };
}

export function useFetchDataRecord<T extends BaseApiRecord>(options: FetchDataOptions<T>) {
  const { records, details, isLoading, error, count, custid, status, fetchData } = useFetchData<T>(options);

  const record = computed(() => records.value[0] || null);

  return {
    record,
    details,
    isLoading,
    error,
    count,
    custid,
    status,
    fetchData,
  };
}
