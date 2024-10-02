// @/api/secrets.ts

import axios, { AxiosError } from 'axios';
import { SecretDataApiResponse } from '@/types/onetime';

export interface AsyncDataResult<T> {
  data: T | null;
  error: string | null;
  status: number | null;
}

/**
 * Fetches the initial secret data from the API.
 *
 * @param secretKey - The key of the secret to fetch.
 * @returns An object containing the fetched data, error message (if any), and status code.
 *
 * Usage example:
 *
 * import { useAsyncData } from '@/composables/useAsyncData';
 * import { fetchInitialSecret } from '@/api/secrets';
 * import { useRoute } from 'vue-router';
 *
 * const route = useRoute();
 * const secretKey = route.params.secretKey as string;
 *
 * const { data, error, isLoading, load } = useAsyncData(() => fetchInitialSecret(secretKey));
 *
 * // Load the data
 * load();
 *
 * // Use data, error, and isLoading in your component
 */
export async function fetchInitialSecret(secretKey: string): Promise<AsyncDataResult<SecretDataApiResponse>> {
  try {
    const response = await axios.get<SecretDataApiResponse>(`/api/v2/secret/${secretKey}`);
    return {
      data: response.data,
      error: null,
      status: response.status
    };
  } catch (error) {
    if (axios.isAxiosError(error)) {
      const axiosError = error as AxiosError<{ message: string }>;
      if (axiosError.response) {
        const { status, data } = axiosError.response;
        if (status === 404) {
          return {
            data: null,
            error: 'Secret not found or already viewed',
            status: 404
          };
        }
        return {
          data: null,
          error: data.message || 'An error occurred while fetching the secret',
          status
        };
      } else if (axiosError.request) {
        return {
          data: null,
          error: 'No response received from server',
          status: null
        };
      }
    }

    return {
      data: null,
      error: 'An unexpected error occurred',
      status: null
    };
  }
}
