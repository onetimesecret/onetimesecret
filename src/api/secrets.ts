import { AsyncDataResult, SecretResponse } from '@/schemas/api';
import axios from 'axios';

/**
 * Fetches the initial secret data from the API.
 *
 * @param secretKey - The key of the secret to fetch.
 * @returns An object containing the fetched data, error message (if any), and status code.
 */
export async function fetchInitialSecret(
  secretKey: string
): Promise<AsyncDataResult<SecretResponse>> {
  try {
    const response = await axios.get<SecretResponse>(`/api/v2/secret/${secretKey}`);
    return {
      data: response.data,
      error: null,
      status: response.status,
    };
  } catch (error) {
    let errorMessage = 'An unexpected error occurred';
    let statusCode = null;

    if (axios.isAxiosError(error)) {
      if (error.response) {
        statusCode = error.response.status;
        errorMessage =
          statusCode === 404
            ? 'Secret not found or already viewed'
            : error.response.data?.message || 'An error occurred while fetching the secret';
      } else if (error.request) {
        errorMessage = 'No response received from server';
      }
    }

    return {
      data: null,
      error: errorMessage,
      status: statusCode,
    };
  }
}
