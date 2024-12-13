// src/composables/useAsyncData.ts

import type { AsyncDataResult } from '@/types';
import { ref, Ref, UnwrapRef } from 'vue';



export function useAsyncData<T>(fetchFunction: () => Promise<AsyncDataResult<T>>) {
  const data = ref<T | null>(null) as Ref<UnwrapRef<T> | null>;
  const error = ref<string | null>(null);
  const status = ref<number | null>(null);
  const isLoading = ref(true);

  const load = async () => {
    isLoading.value = true;
    try {
      const result = await fetchFunction();
      data.value = result.data as UnwrapRef<T> | null;
      error.value = result.error;
      status.value = result.status;
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'An unexpected error occurred';
    } finally {
      isLoading.value = false;
    }
  };

  return { data, error, status, isLoading, load };
}
