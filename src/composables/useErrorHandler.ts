import { ref } from 'vue'

export function useErrorHandler() {
  const error = ref<string | null>(null)

  const handleError = (e: unknown) => {
    console.error('API Error:', e) // Log the full error for debugging
    error.value = "We're sorry, but we couldn't load the page data at this time. Please try again later."
  }

  return { error, handleError }
}
