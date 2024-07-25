// src/utils/formSubmission.ts
import { ref } from 'vue'
import { FormSubmissionOptions } from '@/types/onetime'

export function useFormSubmission(options: FormSubmissionOptions) {
  const isSubmitting = ref(false)
  const error = ref('')
  const success = ref('')

  const submitForm = async (event?: Event) => {
    isSubmitting.value = true
    error.value = ''
    success.value = ''

    try {
      let formData: FormData | URLSearchParams;

      if (options.getFormData) {
        formData = options.getFormData();
      } else if (event) {
        const form = event.target as HTMLFormElement
        formData = new FormData(form)
      } else {
        throw new Error('No form data provided');
      }

      const urlSearchParams = formData instanceof URLSearchParams
        ? formData
        : new URLSearchParams(formData as never);

      const response = await fetch(options.url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: urlSearchParams.toString(),
      })

      let jsonData;
      try {
          jsonData = await response.json();

      } catch (error) {
        // The API endoint didnt return JSON. This could be a network error
        // but more likely
        const message = `Server returned an incomplete response (${options.url})`;
        console.error(message, error);
        // Handle the error appropriately, e.g., set json to a default value or rethrow the error
        throw new Error(message)
      }

      // If the json response includes a new shrimp,
      // let's update our shrimp state to reflect it.
      if (jsonData?.shrimp && options.handleShrimp) {
        options.handleShrimp(jsonData.shrimp);
        console.debug('Updating shrimp');
      }

      if (!response.ok) {

        if (options.onError) {
          await options.onError(jsonData)
        }

        if (response.headers.get("content-type")?.includes("application/json")) {
          throw new Error(jsonData.message || 'Submission failed')
        } else {
          throw new Error('Please refresh the page and try again.')
        }


      }

      success.value = options.successMessage


      if (options.onSuccess) {
        await options.onSuccess(jsonData)
      }

      if (options.redirectUrl) {
        setTimeout(() => {
          window.location.href = options.redirectUrl!
        }, options.redirectDelay || 3000)
      }

    } catch (err: unknown) {
      if (err instanceof Error) {
        error.value = err.message
      } else {
        console.error('An unexpected error occurred', err)
        error.value = 'An unexpected error occurred'
      }
    } finally {
      isSubmitting.value = false
    }
  }

  return {
    isSubmitting,
    error,
    success,
    submitForm
  }
}
