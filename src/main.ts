import { createApp } from 'vue'
import Dashboard from '@/views/Dashboard.vue'
import GlobalBroadcast from '@/components/GlobalBroadcast.vue'
import ThemeToggle from '@/components/ThemeToggle.vue'
import { ref } from 'vue';
import './style.css'

const showBanner = ref(false);

createApp(Dashboard).mount('#app')

const app1 = createApp(GlobalBroadcast, {
  content: 'This is a global broadcast',
  show: showBanner.value,
})
app1.mount('#broadcast')


const app2 = createApp(ThemeToggle)
app2.mount('#theme-toggle')
