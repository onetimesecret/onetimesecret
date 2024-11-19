import { ref } from 'vue';

interface Toast {
  id: number;
  title: string;
  message: string;
  type: 'success' | 'error' | 'warning' | 'info';
  duration?: number;
}

export function useToast() {
  const toasts = ref<Toast[]>([]);
  let nextId = 0;

  const show = (
    title: string,
    message: string,
    type: Toast['type'] = 'info',
    duration = 5000
  ) => {
    const id = nextId++;
    const toast: Toast = {
      id,
      title,
      message,
      type,
      duration
    };

    toasts.value.push(toast);

    if (duration > 0) {
      setTimeout(() => {
        remove(id);
      }, duration);
    }

    return id;
  };

  const remove = (id: number) => {
    const index = toasts.value.findIndex(t => t.id === id);
    if (index > -1) {
      toasts.value.splice(index, 1);
    }
  };

  const success = (title: string, message: string, duration?: number) =>
    show(title, message, 'success', duration);

  const error = (title: string, message: string, duration?: number) =>
    show(title, message, 'error', duration);

  const warning = (title: string, message: string, duration?: number) =>
    show(title, message, 'warning', duration);

  const info = (title: string, message: string, duration?: number) =>
    show(title, message, 'info', duration);

  return {
    toasts,
    show,
    remove,
    success,
    error,
    warning,
    info
  };
}
