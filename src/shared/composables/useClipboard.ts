// src/shared/composables/useClipboard.ts

import { ref, computed } from 'vue'

export function useClipboard() {
  const isCopied = ref(false)

  // Check if clipboard API is available (requires secure context: HTTPS or localhost)
  const isClipboardAvailable = computed(() => typeof navigator !== 'undefined' && 'clipboard' in navigator)

  /**
   * Copy text to clipboard
   * @param text - The text to copy
   * @returns true if successful, false otherwise
   */
  const copyToClipboard = async (text: string): Promise<boolean> => {
    if (!isClipboardAvailable.value) {
      console.error('Clipboard API not available. Requires secure context (HTTPS or localhost).')
      return false
    }

    try {
      await navigator.clipboard.writeText(text)
      isCopied.value = true
      setTimeout(() => {
        isCopied.value = false
      }, 2000)
      return true
    } catch (err) {
      console.error('Failed to copy text: ', err)
      return false
    }
  }

  return {
    isCopied,
    isClipboardAvailable,
    copyToClipboard
  }
}
