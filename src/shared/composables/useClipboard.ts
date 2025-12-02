// src/composables/useClipboard.ts

import { ref } from 'vue'

export function useClipboard() {
  const isCopied = ref(false)

  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text)
      isCopied.value = true
      setTimeout(() => {
        isCopied.value = false
      }, 2000)
    } catch (err) {
      console.error('Failed to copy text: ', err)
    }
  }

  return {
    isCopied,
    copyToClipboard
  }
}
