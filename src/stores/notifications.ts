// src/stores/notifications.ts
import { defineStore } from 'pinia'

interface NotificationState {
  message: string
  type: 'success' | 'error' | 'info' | null
  isVisible: boolean
}

export const useNotificationsStore = defineStore('notifications', {
  state: (): NotificationState => ({
    message: '',
    type: null,
    isVisible: false
  }),

  actions: {
    show(message: string, type: 'success' | 'error' | 'info') {
      this.message = message
      this.type = type
      this.isVisible = true

      // Auto-hide after 5 seconds
      setTimeout(() => {
        this.hide()
      }, 5000)
    },

    hide() {
      this.isVisible = false
      this.message = ''
      this.type = null
    }
  }
})
