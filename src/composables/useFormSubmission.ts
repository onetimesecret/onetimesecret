// src/composables/useFormSubmission.ts

import { useCsrfStore } from '@/stores/csrfStore';
import type { FormSubmissionOptions } from '@/types/ui';
import { ref } from 'vue';
import { z } from 'zod/v4';

/**
 *
 * @param options
 * @returns
 *
 * @deprecated
 */
/* eslint-disable max-lines-per-function */
/* eslint-disable complexity */
export function useFormSubmission<ResponseSchema extends z.ZodTypeAny>(
  options: FormSubmissionOptions<ResponseSchema>
) {
  const isSubmitting = ref(false);
  const error = ref('');
  const success = ref('');

  /* eslint-disable max-lines-per-function */
  async function submitForm(event?: Event) {
    isSubmitting.value = true;
    error.value = '';
    success.value = '';

    try {
      let formData: FormData | URLSearchParams;
      let submissionUrl: string;
      const url: string | undefined = options.url;

      if (options.getFormData) {
        formData = options.getFormData();
        if (!options.url) {
          throw new Error('URL is required when using getFormData');
        }
        submissionUrl = options.url;
      } else if (event) {
        const form = event.target as HTMLFormElement;
        formData = new FormData(form);

        // Use the form's action attribute if no url
        // was passed in the options.
        if (!url) {
          submissionUrl = form.action;
        } else {
          submissionUrl = url;
        }

        if (!submissionUrl) {
          throw new Error('No URL provided in options or form action');
        }
      } else {
        throw new Error('No form data provided');
      }

      const urlSearchParams =
        formData instanceof URLSearchParams ? formData : new URLSearchParams(formData as never);

      const csrfStore = useCsrfStore();
      urlSearchParams.append('shrimp', csrfStore.shrimp);

      const response = await fetch(submissionUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: urlSearchParams.toString(),
      });

      let jsonData: z.infer<ResponseSchema>;
      try {
        const rawData = await response.json();
        const responseSchema = (options.schema || z.any()) as ResponseSchema;
        jsonData = responseSchema.parse(rawData);
      } catch (error) {
        const message = `Server returned an invalid response (${submissionUrl})`;
        console.error(message, error);
        throw new Error(message);
      }

      // If the json response includes a new shrimp,
      // let's update our shrimp state to reflect it.
      if (
        typeof jsonData === 'object' &&
        jsonData !== null &&
        'shrimp' in jsonData &&
        typeof (jsonData as any).shrimp === 'string'
      ) {
        csrfStore.updateShrimp((jsonData as { shrimp: string }).shrimp);
      }

      if (!response.ok) {
        if (options.onError) {
          await options.onError(jsonData);
        }

        if (response.headers.get('content-type')?.includes('application/json')) {
          if (
            typeof jsonData === 'object' &&
            jsonData !== null &&
            'message' in jsonData &&
            typeof (jsonData as any).message === 'string'
          ) {
            throw new Error((jsonData as { message: string }).message);
          } else {
            throw new Error('Request was not successful. Please try again later.');
          }
        } else {
          throw new Error('Please refresh the page and try again.');
        }
      }

      success.value = options.successMessage;

      if (options.onSuccess) {
        await options.onSuccess(jsonData);
      }

      if (options.redirectUrl) {
        setTimeout(() => {
          window.location.href = options.redirectUrl!;
        }, options.redirectDelay || 3000);
      }
    } catch (err: unknown) {
      if (err instanceof Error) {
        error.value = err.message;
      } else {
        const msg = 'An unexpected error occurred';
        console.error(msg, err);
        error.value = msg;
      }
    } finally {
      isSubmitting.value = false;
    }
  }

  return {
    isSubmitting,
    error,
    success,
    submitForm,
  };
}
