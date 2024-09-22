import { ref, onMounted, onUnmounted } from 'vue';

export const useCust = () => {
  const cust = ref(window.cust);

  const updateCust = () => {
    cust.value = window.cust;
  };

  onMounted(() => {
    updateCust();
    window.addEventListener('cust-changed', updateCust);
  });

  onUnmounted(() => {
    window.removeEventListener('cust-changed', updateCust);
  });

  return { cust };
};
