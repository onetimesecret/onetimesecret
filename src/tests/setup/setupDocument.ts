import { vi } from 'vitest';
import { ref } from 'vue';

// Setup visibility mock
export const mockVisibility = ref('hidden');

vi.mock('@vueuse/core', () => ({
  useDocumentVisibility: () => mockVisibility,
}));
