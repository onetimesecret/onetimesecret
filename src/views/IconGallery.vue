<!-- src/views/IconGallery.vue -->
<!--
  Developer tool: Icon gallery showing all available SVG sprite symbols.
  Not linked from main navigation - access directly at /icons

  Icons are discovered at runtime from the DOM, proving they loaded correctly.
-->

<script setup lang="ts">
import { computed, ref, onMounted, nextTick, defineAsyncComponent } from 'vue';
import { iconLibraries } from '@/shared/components/icons/sprites';

// Lazy-load all sprite components so we can render them and discover their symbols
const spriteComponents = {
  CarbonSprites: defineAsyncComponent(() => import('@/shared/components/icons/sprites/CarbonSprites.vue')),
  CriticalSprites: defineAsyncComponent(() => import('@/shared/components/icons/sprites/CriticalSprites.vue')),
  FontAwesome6Sprites: defineAsyncComponent(() => import('@/shared/components/icons/sprites/FontAwesome6Sprites.vue')),
  HeroiconsSprites: defineAsyncComponent(() => import('@/shared/components/icons/sprites/HeroiconsSprites.vue')),
  MaterialSymbolsSprites: defineAsyncComponent(() => import('@/shared/components/icons/sprites/MaterialSymbolsSprites.vue')),
  MdiSprites: defineAsyncComponent(() => import('@/shared/components/icons/sprites/MdiSprites.vue')),
  PhosphorSprites: defineAsyncComponent(() => import('@/shared/components/icons/sprites/PhosphorSprites.vue')),
  TablerSprites: defineAsyncComponent(() => import('@/shared/components/icons/sprites/TablerSprites.vue')),
  AlternateLogoSprites: defineAsyncComponent(() => import('@/shared/components/icons/sprites/AlternateLogoSprites.vue')),
};

// Known prefixes for grouping - order matters for matching
const prefixPatterns = [
  { prefix: 'heroicons', label: 'Heroicons' },
  { prefix: 'material-symbols', label: 'Material Symbols' },
  { prefix: 'mdi', label: 'Material Design Icons' },
  { prefix: 'ph', label: 'Phosphor' },
  { prefix: 'fa6-solid', label: 'Font Awesome 6' },
  { prefix: 'tabler', label: 'Tabler' },
  { prefix: 'carbon', label: 'Carbon' },
  { prefix: 'ix', label: 'IcoMoon' },
  { prefix: 'lucide', label: 'Lucide' },
  { prefix: 'solar', label: 'Solar' },
  { prefix: 'teenyicons', label: 'Teenyicons' },
  { prefix: 'pixelarticons', label: 'Pixel Art' },
  { prefix: 'arcticons', label: 'Arcticons' },
  { prefix: 'game-icons', label: 'Game Icons' },
  { prefix: 'file-icons', label: 'File Icons' },
];

const searchQuery = ref('');
const selectedLibrary = ref<string | null>(null);
const copiedId = ref<string | null>(null);
const iconsByLibrary = ref<Record<string, string[]>>({});
const isLoading = ref(true);

/**
 * Determine the library/prefix group for an icon ID
 */
function getLibraryKey(iconId: string): string {
  for (const { prefix, label } of prefixPatterns) {
    if (iconId.startsWith(prefix + '-')) {
      return label;
    }
  }
  // Fallback: use first segment before hyphen, or 'Other'
  const firstSegment = iconId.split('-')[0];
  return firstSegment || 'Other';
}

/**
 * Scan the DOM for all <symbol> elements and extract their IDs
 */
function discoverIconsFromDOM(): Record<string, string[]> {
  const symbols = document.querySelectorAll('symbol[id]');
  const grouped: Record<string, string[]> = {};

  symbols.forEach((symbol) => {
    const id = symbol.getAttribute('id');
    if (id) {
      const library = getLibraryKey(id);
      if (!grouped[library]) {
        grouped[library] = [];
      }
      // Avoid duplicates
      if (!grouped[library].includes(id)) {
        grouped[library].push(id);
      }
    }
  });

  // Sort icons within each library
  for (const library of Object.keys(grouped)) {
    grouped[library].sort();
  }

  return grouped;
}

/**
 * Poll until symbols appear in the DOM, then populate the gallery
 */
function waitForSpritesAndDiscover() {
  const checkForSymbols = () => {
    const symbols = document.querySelectorAll('symbol[id]');
    if (symbols.length > 0) {
      iconsByLibrary.value = discoverIconsFromDOM();
      isLoading.value = false;
    } else {
      // Sprites not yet rendered, check again
      setTimeout(checkForSymbols, 50);
    }
  };
  checkForSymbols();
}

onMounted(() => {
  // Give async components time to start loading
  nextTick(() => {
    waitForSpritesAndDiscover();
  });
});

const libraryNames = computed(() => Object.keys(iconsByLibrary.value).sort());

const totalIconCount = computed(() =>
  Object.values(iconsByLibrary.value).reduce((sum, icons) => sum + icons.length, 0)
);

const filteredIcons = computed(() => {
  const query = searchQuery.value.toLowerCase();
  const result: Record<string, string[]> = {};

  for (const [library, icons] of Object.entries(iconsByLibrary.value)) {
    if (selectedLibrary.value && library !== selectedLibrary.value) continue;

    const filtered = icons.filter((id) => id.toLowerCase().includes(query));
    if (filtered.length > 0) {
      result[library] = filtered;
    }
  }

  return result;
});

const filteredCount = computed(() =>
  Object.values(filteredIcons.value).reduce((sum, icons) => sum + icons.length, 0)
);

const getLibraryMeta = (libraryLabel: string) => {
  // Map display labels back to iconLibraries keys
  const labelToKey: Record<string, string> = {
    'Heroicons': 'heroicons',
    'Material Symbols': 'materialSymbols',
    'Material Design Icons': 'mdi',
    'Phosphor': 'phosphor',
    'Font Awesome 6': 'fa6',
    'Tabler': 'tabler',
    'Carbon': 'carbon',
  };
  return iconLibraries[labelToKey[libraryLabel] || ''];
};

const copyToClipboard = async (iconId: string) => {
  try {
    await navigator.clipboard.writeText(iconId);
    copiedId.value = iconId;
    setTimeout(() => {
      copiedId.value = null;
    }, 2000);
  } catch (err) {
    console.error('Failed to copy:', err);
  }
};

const getIconName = (iconId: string) => {
  // Remove the prefix to get just the icon name
  for (const { prefix } of prefixPatterns) {
    if (iconId.startsWith(prefix + '-')) {
      return iconId.slice(prefix.length + 1);
    }
  }
  // Fallback: remove first segment
  const parts = iconId.split('-');
  return parts.slice(1).join('-') || iconId;
};
</script>

<template>
  <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
    <!-- Hidden sprite container - renders all sprites to make symbols available -->
    <div
      class="hidden"
      aria-hidden="true"
    >
      <Suspense>
        <component :is="spriteComponents.CarbonSprites" />
      </Suspense>
      <Suspense>
        <component :is="spriteComponents.CriticalSprites" />
      </Suspense>
      <Suspense>
        <component :is="spriteComponents.FontAwesome6Sprites" />
      </Suspense>
      <Suspense>
        <component :is="spriteComponents.HeroiconsSprites" />
      </Suspense>
      <Suspense>
        <component :is="spriteComponents.MaterialSymbolsSprites" />
      </Suspense>
      <Suspense>
        <component :is="spriteComponents.MdiSprites" />
      </Suspense>
      <Suspense>
        <component :is="spriteComponents.PhosphorSprites" />
      </Suspense>
      <Suspense>
        <component :is="spriteComponents.TablerSprites" />
      </Suspense>
      <Suspense>
        <component :is="spriteComponents.AlternateLogoSprites" />
      </Suspense>
    </div>

    <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <!-- Header -->
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          Icon Gallery
        </h1>
        <p class="mt-2 text-gray-600 dark:text-gray-400">
          <template v-if="isLoading">
            Loading icons from sprite files...
          </template>
          <template v-else>
            {{ totalIconCount }} icons discovered across {{ libraryNames.length }} libraries.
            Click any icon to copy its ID.
          </template>
        </p>
      </div>

      <!-- Loading state -->
      <div
        v-if="isLoading"
        class="flex items-center justify-center py-24"
      >
        <svg
          class="size-8 animate-spin text-brand-600"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
        >
          <circle
            class="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            stroke-width="4"
          />
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
          />
        </svg>
        <span class="ml-3 text-gray-600 dark:text-gray-400">
          Loading sprite files...
        </span>
      </div>

      <template v-else>
        <!-- Filters -->
        <div class="mb-8 flex flex-col gap-4 sm:flex-row">
          <div class="flex-1">
            <input
              v-model="searchQuery"
              type="text"
              placeholder="Search icons..."
              class="w-full rounded-lg border border-gray-300 bg-white px-4 py-2 text-gray-900 placeholder-gray-500 focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white dark:placeholder-gray-400"
            />
          </div>
          <div class="flex gap-2">
            <button
              :class="[
                'rounded-lg px-4 py-2 text-sm font-medium transition-colors',
                !selectedLibrary
                  ? 'bg-brand-600 text-white'
                  : 'bg-gray-200 text-gray-700 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600',
              ]"
              @click="selectedLibrary = null"
            >
              All
            </button>
            <select
              v-model="selectedLibrary"
              class="rounded-lg border border-gray-300 bg-white px-4 py-2 text-gray-900 focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
            >
              <option :value="null">All Libraries</option>
              <option
                v-for="lib in libraryNames"
                :key="lib"
                :value="lib"
              >
                {{ lib }} ({{ iconsByLibrary[lib]?.length || 0 }})
              </option>
            </select>
          </div>
        </div>

        <!-- Results count -->
        <p
          v-if="searchQuery || selectedLibrary"
          class="mb-4 text-sm text-gray-600 dark:text-gray-400"
        >
          Showing {{ filteredCount }} icons
        </p>

        <!-- Icon sections -->
        <div class="space-y-12">
          <section
            v-for="(icons, library) in filteredIcons"
            :key="library"
          >
            <div class="mb-4 flex items-baseline justify-between border-b border-gray-200 pb-2 dark:border-gray-700">
              <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
                {{ library }}
                <span class="ml-2 text-sm font-normal text-gray-500 dark:text-gray-400">
                  ({{ icons.length }})
                </span>
              </h2>
              <a
                v-if="getLibraryMeta(library)"
                :href="getLibraryMeta(library)?.sourceUrl"
                target="_blank"
                rel="noopener noreferrer"
                class="text-sm text-brand-600 hover:text-brand-700 dark:text-brand-400 dark:hover:text-brand-300"
              >
                {{ getLibraryMeta(library)?.license }}
              </a>
            </div>

            <div class="grid grid-cols-4 gap-3 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-10 xl:grid-cols-12">
              <button
                v-for="iconId in icons"
                :key="iconId"
                :title="iconId"
                class="group relative flex flex-col items-center rounded-lg border border-gray-200 bg-white p-3 transition-all hover:border-brand-500 hover:shadow-md dark:border-gray-700 dark:bg-gray-800 dark:hover:border-brand-400"
                @click="copyToClipboard(iconId)"
              >
                <svg class="size-8 text-gray-700 dark:text-gray-300">
                  <use :href="`#${iconId}`" />
                </svg>
                <span class="mt-2 line-clamp-2 text-center text-xs text-gray-500 dark:text-gray-400">
                  {{ getIconName(iconId) }}
                </span>

                <!-- Copied indicator -->
                <div
                  v-if="copiedId === iconId"
                  class="absolute inset-0 flex items-center justify-center rounded-lg bg-green-500/90"
                >
                  <span class="text-sm font-medium text-white">Copied</span>
                </div>
              </button>
            </div>
          </section>
        </div>

        <!-- Empty state -->
        <div
          v-if="Object.keys(filteredIcons).length === 0"
          class="py-12 text-center"
        >
          <svg
            class="mx-auto size-12 text-gray-400"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <h3 class="mt-4 text-lg font-medium text-gray-900 dark:text-white">
            No icons found
          </h3>
          <p class="mt-2 text-gray-500 dark:text-gray-400">
            Try adjusting your search or filter.
          </p>
        </div>

        <!-- Usage instructions -->
        <div class="mt-16 rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
          <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
            Usage
          </h2>
          <pre class="overflow-x-auto rounded bg-gray-100 p-4 text-sm dark:bg-gray-900"><code class="text-gray-800 dark:text-gray-200">&lt;OIcon
  collection="heroicons-solid"
  name="check-circle"
  class="size-5"
  aria-label="Success"
/&gt;</code></pre>
          <p class="mt-4 text-sm text-gray-600 dark:text-gray-400">
            The icon ID format is <code class="rounded bg-gray-100 px-1 dark:bg-gray-900">{collection}-{name}</code>.
            For example, <code class="rounded bg-gray-100 px-1 dark:bg-gray-900">heroicons-check-circle-solid</code>
            uses collection <code class="rounded bg-gray-100 px-1 dark:bg-gray-900">heroicons</code>
            and name <code class="rounded bg-gray-100 px-1 dark:bg-gray-900">check-circle-solid</code>.
          </p>
          <p class="mt-4 text-sm text-gray-500 dark:text-gray-500">
            Icons are discovered dynamically from rendered sprite files.
            New icons added to sprite files will appear here automatically.
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
