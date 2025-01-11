<!-- src/views/info/Icons.vue -->
<script setup lang="ts">
import { ref, onMounted } from 'vue';
import IconSources from '@/components/icons/IconSources.vue';

interface IconSet {
  prefix: string;
  name: string;
  id: string;
}

const icons = ref<IconSet[]>([]);

const ICON_PREFIXES = {
  'fa6-solid': 'Font Awesome 6',
  'carbon': 'Carbon',
  'heroicon': 'Heroicons',
  'mdi': 'Material Design Icons',
  'gm': 'Google Material'
} as const;


const categorizeIcon = (id: string): IconSet => {
  const prefix = Object.keys(ICON_PREFIXES).find(p => id.startsWith(p));
  return {
    prefix: prefix || 'other',
    name: prefix ? ICON_PREFIXES[prefix as keyof typeof ICON_PREFIXES] : 'Other',
    id
  };
};

onMounted(() => {
  const spritesContainer = document.getElementById('sprites');
  if (!spritesContainer) return;

  const symbols = spritesContainer.querySelectorAll('symbol');

  icons.value = Array.from(symbols)
    .map(symbol => categorizeIcon(symbol.id))
    .sort((a, b) =>
      a.name === b.name
        ? a.id.localeCompare(b.id)
        : a.name.localeCompare(b.name)
    );
});
</script>

<template>
  <div class="container mx-auto p-6">
    <h1 class="text-2xl font-semibold mb-6">Icon Library</h1>
    <IconSources :icons="icons" />
  </div>
</template>
