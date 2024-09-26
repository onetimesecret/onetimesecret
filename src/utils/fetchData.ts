// src/utils/fetchData.ts
import { ref, Ref, computed } from 'vue';
import type { ApiRecordResponse, ApiRecordsResponse, BaseApiRecord } from '@/types/onetime.d.ts';

// Use the more specific types like ColonelDataApiResponse?

interface FetchDataOptions<T extends BaseApiRecord> {
  url: string;
  onSuccess?: (data: T[]) => void;
  onError?: (error: Error) => void;
}

export function useFetchData<T extends BaseApiRecord>({ url, onSuccess, onError }: FetchDataOptions<T>) {
  const records = ref<T[]>([]) as Ref<T[]>;
  const isLoading = ref(false);
  const error = ref('');
  const count = ref<number>(0);
  const custid = ref<string | null>(null);

  const fetchData = async () => {
    isLoading.value = true;
    error.value = '';

    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`Failed to fetch data from ${url}`);
      }

      const jsonData: ApiRecordResponse<T> | ApiRecordsResponse<T> = await response.json();

      if ('record' in jsonData) {
        records.value = [jsonData.record];
        count.value = 1;
      } else if ('records' in jsonData) {
        records.value = jsonData.records;
        count.value = jsonData.count;
        custid.value = jsonData.custid;
      } else {
        throw new Error('Unexpected response format');
      }

      if (onSuccess) {
        onSuccess(records.value);
      }
    } catch (err: unknown) {
      if (err instanceof Error) {
        error.value = err.message;
      } else {
        console.error('An unexpected error occurred', err);
        error.value = 'An unexpected error occurred';
      }

      if (onError) {
        onError(err as Error);
      }
    } finally {
      isLoading.value = false;
    }
  };

  return {
    records,
    isLoading,
    error,
    count,
    custid,
    fetchData,
  };
}

export function useFetchDataRecord<T extends BaseApiRecord>(options: FetchDataOptions<T>) {
  const { records, isLoading, error, count, custid, fetchData } = useFetchData<T>(options);

  const record = computed(() => records.value[0] || null);

  return {
    record,
    isLoading,
    error,
    count,
    custid,
    fetchData,
  };
}
