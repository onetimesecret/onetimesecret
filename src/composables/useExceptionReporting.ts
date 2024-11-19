// composables/useExceptionReporting.ts
import { ref } from 'vue'
import axios from 'axios'

export function useExceptionReporting() {
  const isReporting = ref(false)

  async function reportException(exceptionData: {
    message: string
    type: string
    stack: string
    url: string
    line: number
    column: number
    environment: string
    release: string
  }) {
    isReporting.value = true

    try {
      await axios.post('/api/v2/exception', exceptionData)
    } catch (error) {
      console.error('Failed to report exception:', error)
    } finally {
      isReporting.value = false
    }
  }

  return {
    isReporting,
    reportException
  }
}
