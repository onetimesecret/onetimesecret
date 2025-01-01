// src/stores/notificationsStore.ts
import { defineStore } from 'pinia';

interface NotificationState {
  message: string;
  type: 'success' | 'error' | 'info' | null;
  isVisible: boolean;
  position?: 'top' | 'bottom';
  _initialized: boolean;
}

export const useNotificationsStore = defineStore('notifications', {
  state: (): NotificationState => ({
    message: '',
    type: null,
    isVisible: false,
    position: 'bottom',
    _initialized: false,
  }),

  actions: {
    show(
      message: string,
      type: 'success' | 'error' | 'info',
      position?: 'top' | 'bottom'
    ) {
      this.message = message;
      this.type = type;
      this.position = position || 'bottom';
      this.isVisible = true;

      setTimeout(() => {
        this.hide();
      }, 5000);
    },

    hide() {
      this.isVisible = false;
      this.message = '';
      this.type = null;
    },
  },
});
