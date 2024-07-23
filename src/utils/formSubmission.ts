// src/utils/formSubmission.ts
import { ref } from 'vue'

type FormSubmissionOptions = {
  url: string;
  successMessage: string;
  redirectUrl?: string;
  redirectDelay?: number;

  // eslint-disable-next-line no-unused-vars
  onSuccess?: (response: Response) => void | Promise<void>;
};

export function useFormSubmission(options: FormSubmissionOptions) {
  const isSubmitting = ref(false)
  const error = ref('')
  const success = ref('')

  const submitForm = async (event: Event) => {
    isSubmitting.value = true
    error.value = ''
    success.value = ''

    try {
      const form = event.target as HTMLFormElement
      const formData = new FormData(form)
      const urlSearchParams = new URLSearchParams(formData as never)

      const response = await fetch(options.url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: urlSearchParams.toString(),
      })

      if (!response.ok) {
        if (response.headers.get("content-type")?.includes("application/json")) {
          const errorResponse = await response.json()
          throw new Error(errorResponse.message || 'Submission failed')
        } else {
          throw new Error('Please refresh the page and try again.')
        }
      }

      success.value = options.successMessage

      // Call the onSuccess callback if it exists
      if (options.onSuccess) {
        await options.onSuccess(response)
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
