// src/utils/formSubmission.ts

type FormSubmissionOptions = {
  url: string;
  successMessage: string;
  redirectUrl?: string;
  redirectDelay?: number;
};

export async function handleFormSubmission(
  event: Event,
  options: FormSubmissionOptions,
  // eslint-disable-next-line no-unused-vars
  setIsUpdating: (value: boolean) => void,
  // eslint-disable-next-line no-unused-vars
  setErrorMessage: (value: string) => void,
  // eslint-disable-next-line no-unused-vars
  setSuccessMessage: (value: string) => void
) {
  setIsUpdating(true);
  setErrorMessage('');
  setSuccessMessage('');

  try {
    const form = event.target as HTMLFormElement;
    const formData = new FormData(form);
    const urlSearchParams = new URLSearchParams(formData as never);

    const response = await fetch(options.url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: urlSearchParams.toString(),
    });

    if (!response.ok) {
      if (response.headers.get("content-type")?.includes("application/json")) {
        const errorResponse = await response.json();
        throw new Error(errorResponse.message || 'Submission failed');
      } else {
        throw new Error('Please refresh the page and try again.');
      }
    }

    setSuccessMessage(options.successMessage);

    if (options.redirectUrl) {
      setTimeout(() => {
        window.location.href = options.redirectUrl!;
      }, options.redirectDelay || 3000);
    }

  } catch (error: unknown) {
    if (error instanceof Error) {
      setErrorMessage(error.message);
    } else {
      console.error('An unexpected error occurred', error);
      setErrorMessage('An unexpected error occurred');
    }
  } finally {
    setIsUpdating(false);
  }
}
