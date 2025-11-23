# PHASE 5: FINAL RECOMMENDATION
## OneTimeSecret Create-Secret Experience Redesign — Implementation Plan

**Date**: 2025-11-18
**Branch**: `claude/redesign-create-secret-01VCPSHrMm9voh36zpcZTmrD`
**Status**: Ready for Team Review → Implementation

---

## EXECUTIVE SUMMARY

After comprehensive analysis across 4 phases, we recommend a **Hybrid Express Model** that delivers:

- **50-85% faster** time-to-task-completion across all user scenarios
- **Mobile-first** experience with native patterns (bottom sheets, gestures, sticky actions)
- **Smart suggestions** via content detection without being intrusive
- **Progressive disclosure** that scales from beginners to power users
- **Future-ready** architecture for Linear Secrets, Inbound Secrets, QR codes, markdown rendering

**Core Philosophy**: Get out of the user's way. Paste → Smart suggestion → Create. Done in 5-10 seconds.

---

## PART 1: DESIGN PRINCIPLES

### 1. SPEED IS THE PRIMARY FEATURE

**Principle**: Every design decision must optimize for time-to-task-completion.

**Implementation**:
- Auto-focus textarea on page load
- Smart defaults based on content detection
- One-click "Apply Recommendation" (no multi-step configuration)
- Keyboard shortcuts for power users (`Cmd+Enter` to submit)
- Sticky footer on mobile (no scrolling to reach button)

**Success Metric**: 80% of secrets created in <10 seconds (vs current ~30-60s)

**Anti-Patterns to Avoid**:
- ❌ Multi-step wizards for common cases
- ❌ Required fields that could have smart defaults
- ❌ Modal dialogs that interrupt flow
- ❌ Submit button below fold on mobile

---

### 2. PROGRESSIVE DISCLOSURE OVER UPFRONT COMPLEXITY

**Principle**: Start minimal, reveal options contextually as users need them.

**Implementation**:
- **Default state**: Large textarea + create button (2 elements)
- **After paste**: Suggestion banner appears (optional, non-blocking)
- **If customize**: Options expand inline (not in modal)
- **Advanced features**: Collapsed by default (`<details>` element)

**Visual Hierarchy**:
```
1. Content input area (primary action)
2. Smart suggestion (helpful, not mandatory)
3. Create button (always visible)
4. Customization options (revealed on demand)
5. Advanced features (collapsed)
```

**Success Metric**: 70%+ of users accept defaults without customizing

---

### 3. CONTEXT-AWARE SUGGESTIONS WITH TRANSPARENCY

**Principle**: Use smart detection to help users, but always explain why and allow override.

**Implementation**:
```
🔍 Detected: Database credentials
⚡ Recommended: High security
   • Expires in 1 hour
   • Passphrase required
   [Apply Recommendation] or [Customize]
```

**Detection Patterns** (Pattern matching, not ML):
- `password|db_pass|api_key|token` → High security (1hr, passphrase)
- `ssid|wifi|wpa` + length < 100 chars → QR code suggestion
- Markdown syntax (`#`, `**`, ` ``` `) → Enable rendering
- Default → Medium security (24hr, optional passphrase)

**Transparency Rules**:
- Always show "why" (Detected: X)
- User can override (Customize button)
- Suggestions are optional (can ignore, just click Create)

**Success Metric**: 60%+ acceptance rate for suggestions

---

### 4. MOBILE FIRST, DESKTOP ENHANCED

**Principle**: Design for smallest screen first, enhance for larger screens—never treat mobile as "responsive desktop."

**Mobile-Specific Patterns**:
- **Bottom sheet** for options (native iOS/Android pattern)
- **Sticky footer** with primary action (always visible)
- **Swipe gestures** (swipe up for options, swipe between modes)
- **Large tap targets** (minimum 44x44px)
- **Safe area insets** for notches/home indicators

**Desktop Enhancements**:
- **Keyboard shortcuts** (`Cmd+K` focus, `Cmd+Enter` submit, `Cmd+G` generate)
- **Split-pane markdown** editor (Edit | Preview)
- **Hover states** and tooltips
- **Preview panes** for QR codes and formatted content

**Success Metric**: Mobile completion rate matches or exceeds desktop (>95%)

---

### 5. CLARITY OVER CLEVERNESS

**Principle**: Users should always understand what's happening and why. No "magic" without explanation.

**Language Guidelines**:
- ✅ "Expires in 1 hour (at 2:45 PM)" → ❌ "TTL: 3600"
- ✅ "How sensitive is this content?" → ❌ "Select risk level"
- ✅ "Detected: Database credentials" → ❌ Silent auto-configuration
- ✅ "Passphrase protects against link interception" → ❌ Just a checkbox

**Error Messages**:
- Blame the system, not the user
- Provide actionable next steps
- ✅ "Rate limit reached. Try again in 5 minutes." → ❌ "Invalid request"

**Accessibility Language**:
- All icons paired with text labels
- Screen reader announcements for dynamic changes
- Plain language help text (no jargon)

**Success Metric**: 90%+ user comprehension in testing (understand security options)

---

## PART 2: COMPONENT STRUCTURE

### 2.1 RECOMMENDED ARCHITECTURE

#### High-Level Component Tree

```
src/
├── views/
│   ├── CreateSecretPage.vue          # Main orchestrator
│   ├── ReceiptPage.vue                # After secret created
│   └── ViewSecretPage.vue             # Existing (recipient view)
│
├── components/
│   ├── create/
│   │   ├── ModeSelector.vue           # Text | Generate | Document tabs
│   │   │
│   │   ├── modes/
│   │   │   ├── TextMode.vue           # Paste/type content
│   │   │   ├── GenerateMode.vue       # Password generator
│   │   │   └── DocumentMode.vue       # Markdown editor
│   │   │
│   │   ├── shared/
│   │   │   ├── SecretTextarea.vue     # Auto-focus, char counter
│   │   │   ├── SuggestionBanner.vue   # Detection + recommendation
│   │   │   ├── SecurityOptions.vue    # Presets + custom
│   │   │   ├── AdvancedOptions.vue    # Email, QR, markdown toggles
│   │   │   └── CreateButton.vue       # Submit with loading states
│   │   │
│   │   └── mobile/
│   │       ├── BottomSheet.vue        # Swipeable options panel
│   │       └── StickyFooter.vue       # Always-visible button
│   │
│   ├── receipt/
│   │   ├── SecretLink.vue             # Link display + copy
│   │   ├── PassphraseDisplay.vue      # Passphrase + copy
│   │   ├── ExpirationInfo.vue         # Countdown timer
│   │   ├── ShareOptions.vue           # Copy, QR, Email buttons
│   │   ├── QRCodeModal.vue            # Fullscreen QR display
│   │   └── BurnButton.vue             # Immediate destruction
│   │
│   └── ui/                             # Reusable primitives
│       ├── Button.vue
│       ├── Input.vue
│       ├── Select.vue
│       ├── Checkbox.vue
│       └── Modal.vue
│
├── composables/
│   ├── useSecretCreation.ts           # Form state + submission
│   ├── useContentDetection.ts         # Pattern matching logic
│   ├── useUserPreferences.ts          # localStorage behavioral memory
│   ├── useKeyboardShortcuts.ts        # Global shortcuts
│   ├── useFocusManagement.ts          # Accessibility focus
│   └── usePasswordGenerator.ts        # Secure password generation
│
├── stores/
│   ├── secretCreationStore.ts         # New: Creation flow state
│   ├── secretStore.ts                 # Existing: API integration
│   └── concealedMetadataStore.ts      # Existing: Local storage
│
└── utils/
    ├── contentDetection.ts            # Pattern matching algorithms
    ├── passphraseGenerator.ts         # Memorable passphrase creation
    ├── expirationFormatter.ts         # Human-readable TTL
    └── qrCodeGenerator.ts             # QR code canvas rendering
```

---

### 2.2 KEY COMPONENT SPECIFICATIONS

#### CreateSecretPage.vue (Main Orchestrator)

**Responsibilities**:
- Render current mode (Text/Generate/Document)
- Handle mode switching
- Manage global state (form data, detection results)
- Coordinate submission workflow

**Template Structure**:
```vue
<template>
  <div class="create-page container mx-auto px-4 py-8">
    <!-- Mode Selector (Tabs) -->
    <ModeSelector
      :current-mode="currentMode"
      @change="handleModeChange"
    />

    <!-- Current Mode Component (dynamic) -->
    <component
      :is="currentModeComponent"
      v-model="formData"
      :detection="detectionResult"
      @submit="handleSubmit"
    />

    <!-- Mobile-only Sticky Footer -->
    <StickyFooter v-if="isMobile">
      <CreateButton
        :disabled="!canSubmit"
        :loading="isSubmitting"
        @click="handleSubmit"
      />
    </StickyFooter>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import { useSecretCreation } from '@/composables/useSecretCreation';
import { useBreakpoints } from '@/composables/useBreakpoints';

import ModeSelector from '@/components/create/ModeSelector.vue';
import TextMode from '@/components/create/modes/TextMode.vue';
import GenerateMode from '@/components/create/modes/GenerateMode.vue';
import DocumentMode from '@/components/create/modes/DocumentMode.vue';
import StickyFooter from '@/components/create/mobile/StickyFooter.vue';
import CreateButton from '@/components/create/shared/CreateButton.vue';

const {
  currentMode,
  formData,
  detectionResult,
  isSubmitting,
  canSubmit,
  handleModeChange,
  handleSubmit,
} = useSecretCreation();

const { isMobile } = useBreakpoints();

const currentModeComponent = computed(() => {
  switch (currentMode.value) {
    case 'generate': return GenerateMode;
    case 'document': return DocumentMode;
    default: return TextMode;
  }
});
</script>
```

**State Management**:
- Uses `useSecretCreation()` composable for all form logic
- No local state (all in composable for testability)
- Reactive updates via v-model binding

---

#### TextMode.vue (Primary Use Case)

**Responsibilities**:
- Render large textarea with auto-focus
- Display suggestion banner when content detected
- Show security options (progressive disclosure)
- Handle desktop/mobile layout differences

**Template Structure**:
```vue
<template>
  <div class="text-mode">
    <!-- Textarea -->
    <SecretTextarea
      v-model="modelValue.content"
      @paste="handlePaste"
      @input="handleInput"
    />

    <!-- Suggestion Banner (appears after detection) -->
    <SuggestionBanner
      v-if="detection"
      :detection="detection"
      @apply="handleApply"
      @customize="showOptions = true"
    />

    <!-- Security Options (progressive) -->
    <Transition name="expand">
      <SecurityOptions
        v-if="showOptions"
        v-model:preset="modelValue.securityPreset"
        v-model:ttl="modelValue.ttl"
        v-model:passphrase="modelValue.passphrase"
      />
    </Transition>

    <!-- Advanced Options (collapsed by default) -->
    <AdvancedOptions v-model="modelValue.advancedOptions" />

    <!-- Create Button (desktop only, mobile uses sticky footer) -->
    <CreateButton
      v-if="!isMobile"
      :disabled="!canSubmit"
      :loading="isSubmitting"
      @click="$emit('submit')"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue';
import { debounce } from '@/utils/debounce';
import { detectContentType } from '@/utils/contentDetection';

const props = defineProps<{
  modelValue: SecretFormData;
  detection: DetectionResult | null;
}>();

const emit = defineEmits<{
  'update:modelValue': [value: SecretFormData];
  'submit': [];
}>();

const showOptions = ref(false);

const handleInput = debounce((content: string) => {
  if (content.length > 10) {
    const result = detectContentType(content);
    emit('update:detection', result);
  }
}, 200);

const handleApply = () => {
  // Apply recommendation logic
  showOptions.value = false;
};
</script>
```

---

#### SuggestionBanner.vue (Smart Recommendations)

**Responsibilities**:
- Display detection result with icon
- Explain recommended settings
- Provide Apply and Customize actions
- Accessible announcements

**Template**:
```vue
<template>
  <div
    role="status"
    aria-live="polite"
    class="suggestion-banner rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-950"
  >
    <div class="flex items-start gap-3">
      <!-- Icon -->
      <span class="text-2xl" aria-hidden="true">🔍</span>

      <!-- Content -->
      <div class="flex-1">
        <p class="font-semibold text-blue-900 dark:text-blue-100">
          Detected: {{ detection.label }}
        </p>
        <p class="mt-1 text-sm text-blue-700 dark:text-blue-300">
          ⚡ Recommended: {{ recommendedPresetLabel }}
        </p>
        <ul class="mt-2 space-y-1 text-sm text-blue-600 dark:text-blue-400">
          <li>• Expires in {{ formatTTL(recommendedSettings.ttl) }}</li>
          <li v-if="recommendedSettings.passphrase">
            • Passphrase required
          </li>
        </ul>
      </div>

      <!-- Actions -->
      <div class="flex gap-2">
        <button
          type="button"
          class="btn-primary"
          @click="$emit('apply')"
        >
          Apply
        </button>
        <button
          type="button"
          class="btn-secondary"
          @click="$emit('customize')"
        >
          Customize
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import type { DetectionResult } from '@/types';
import { securityPresets } from '@/config/presets';
import { formatTTL } from '@/utils/expirationFormatter';

const props = defineProps<{
  detection: DetectionResult;
}>();

const emit = defineEmits<{
  apply: [];
  customize: [];
}>();

const recommendedPresetLabel = computed(() => {
  const preset = securityPresets[props.detection.suggestedPreset];
  return preset.label;
});

const recommendedSettings = computed(() => {
  return securityPresets[props.detection.suggestedPreset];
});
</script>
```

---

#### BottomSheet.vue (Mobile-Specific)

**Responsibilities**:
- Swipeable options panel for mobile
- Collapsed/expanded states
- Gesture handling (drag to expand/collapse)
- Safe area insets

**Template**:
```vue
<template>
  <Teleport to="body">
    <div
      ref="sheetRef"
      class="bottom-sheet"
      :class="{ expanded: isExpanded }"
      :style="{ transform: `translateY(${dragOffset}px)` }"
      @touchstart="handleDragStart"
      @touchmove="handleDragMove"
      @touchend="handleDragEnd"
    >
      <!-- Drag Handle -->
      <div class="handle">
        <div class="handle-bar"></div>
      </div>

      <!-- Content -->
      <div class="sheet-content">
        <slot></slot>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { ref } from 'vue';

const isExpanded = ref(false);
const dragOffset = ref(0);
const startY = ref(0);
const sheetRef = ref<HTMLElement | null>(null);

const handleDragStart = (e: TouchEvent) => {
  startY.value = e.touches[0].clientY;
};

const handleDragMove = (e: TouchEvent) => {
  const deltaY = e.touches[0].clientY - startY.value;

  // Only allow valid drag directions
  if ((isExpanded.value && deltaY > 0) || (!isExpanded.value && deltaY < 0)) {
    dragOffset.value = deltaY;
  }
};

const handleDragEnd = () => {
  // Snap to expanded or collapsed
  if (Math.abs(dragOffset.value) > 100) {
    isExpanded.value = !isExpanded.value;
  }

  // Reset with animation
  dragOffset.value = 0;
};
</script>

<style scoped>
.bottom-sheet {
  @apply fixed left-0 right-0 z-50;
  @apply bg-white dark:bg-slate-900;
  @apply rounded-t-3xl shadow-2xl;
  @apply transition-transform duration-300 ease-out;
  bottom: calc(env(safe-area-inset-bottom) + 4rem);
}

.bottom-sheet.expanded {
  @apply h-[70vh];
}

.bottom-sheet:not(.expanded) {
  @apply h-32;
}

.handle {
  @apply flex h-8 cursor-grab items-center justify-center;
  @apply active:cursor-grabbing;
}

.handle-bar {
  @apply h-1.5 w-12 rounded-full bg-gray-300;
}

.sheet-content {
  @apply overflow-y-auto p-6;
  max-height: calc(70vh - 2rem);
}
</style>
```

---

### 2.3 COMPOSABLE DESIGN PATTERNS

#### useSecretCreation.ts (Core Logic)

```typescript
import { ref, reactive, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useSecretStore } from '@/stores/secretStore';
import { useUserPreferences } from './useUserPreferences';
import { detectContentType } from '@/utils/contentDetection';
import { generatePassphrase } from '@/utils/passphraseGenerator';

export function useSecretCreation() {
  const router = useRouter();
  const secretStore = useSecretStore();
  const preferences = useUserPreferences();

  // State
  const currentMode = ref<'text' | 'generate' | 'document'>('text');
  const formData = reactive({
    content: '',
    ttl: preferences.getDefaultTTL(),
    passphrase: '',
    securityPreset: preferences.getMostUsedPreset(),
    advancedOptions: {
      sendEmail: false,
      displayQR: false,
      enableMarkdown: false,
    },
  });
  const detectionResult = ref<DetectionResult | null>(null);
  const isSubmitting = ref(false);
  const errors = ref<string[]>([]);

  // Computed
  const canSubmit = computed(() => {
    if (currentMode.value === 'text' && !formData.content) return false;
    if (isSubmitting.value) return false;
    return true;
  });

  // Actions
  const handleModeChange = (mode: typeof currentMode.value) => {
    currentMode.value = mode;
    errors.value = [];
  };

  const detectContent = (content: string) => {
    if (content.length < 10) {
      detectionResult.value = null;
      return;
    }

    detectionResult.value = detectContentType(content);
  };

  const applyRecommendation = () => {
    if (!detectionResult.value) return;

    const preset = securityPresets[detectionResult.value.suggestedPreset];
    formData.ttl = preset.ttl;

    if (preset.passphrase === 'auto-generate') {
      formData.passphrase = generatePassphrase();
    }

    formData.securityPreset = detectionResult.value.suggestedPreset;
  };

  const handleSubmit = async () => {
    isSubmitting.value = true;
    errors.value = [];

    try {
      const payload = buildPayload();
      const response = await submitToAPI(payload);

      // Track usage
      preferences.recordPresetUsage(formData.securityPreset);

      // Navigate to receipt
      await router.push(`/receipt/${response.record.metadata.key}`);

      // Reset form
      resetForm();

    } catch (error: any) {
      handleError(error);
    } finally {
      isSubmitting.value = false;
    }
  };

  const buildPayload = () => {
    // Build API payload based on mode
    const base = {
      kind: currentMode.value === 'generate' ? 'generate' : 'conceal',
      ttl: formData.ttl,
      passphrase: formData.passphrase || undefined,
    };

    if (currentMode.value === 'text' || currentMode.value === 'document') {
      return {
        secret: {
          ...base,
          secret: formData.content,
        },
      };
    } else {
      return {
        secret: {
          ...base,
          length: 12,
          character_sets: {
            uppercase: true,
            lowercase: true,
            numbers: true,
            symbols: true,
          },
        },
      };
    }
  };

  const submitToAPI = async (payload: any) => {
    if (currentMode.value === 'generate') {
      return await secretStore.generate(payload);
    } else {
      return await secretStore.conceal(payload);
    }
  };

  const handleError = (error: any) => {
    if (error.response?.status === 429) {
      errors.value.push('Rate limit exceeded. Please try again in a few minutes.');
    } else if (error.response?.data?.form_fields) {
      errors.value = Object.values(error.response.data.form_fields);
    } else {
      errors.value.push('Something went wrong. Please try again.');
    }
  };

  const resetForm = () => {
    formData.content = '';
    formData.passphrase = '';
    formData.advancedOptions = {
      sendEmail: false,
      displayQR: false,
      enableMarkdown: false,
    };
    detectionResult.value = null;
    errors.value = [];
  };

  return {
    currentMode,
    formData,
    detectionResult,
    isSubmitting,
    errors,
    canSubmit,
    handleModeChange,
    detectContent,
    applyRecommendation,
    handleSubmit,
  };
}
```

---

## PART 3: IMPLEMENTATION CONSIDERATIONS

### 3.1 BACKWARDS COMPATIBILITY

**Challenge**: Existing users have muscle memory with current interface.

**Solution: Feature Flag Rollout**

```typescript
// config/features.ts
export const features = {
  newCreateExperience: {
    enabled: import.meta.env.VITE_FEATURE_NEW_CREATE === 'true',
    rolloutPercentage: 0, // 0-100, gradual rollout
    allowOptOut: true, // Users can switch back
  },
};

// In CreateSecretPage.vue
const showNewExperience = computed(() => {
  // Check feature flag
  if (!features.newCreateExperience.enabled) return false;

  // Check user opt-out preference
  const userPrefs = useUserPreferences();
  if (userPrefs.optedOutOfNewUI) return false;

  // Gradual rollout (0-100%)
  const userId = getUserId(); // Hash or session ID
  const bucket = hashUserToBucket(userId, 100);
  return bucket < features.newCreateExperience.rolloutPercentage;
});
```

**User Control**:
```vue
<!-- Toggle in settings or banner -->
<div v-if="showNewExperience" class="new-ui-banner">
  <p>You're using the new create experience!</p>
  <button @click="optOutOfNewUI">Switch back to classic</button>
</div>

<div v-else class="classic-ui-banner">
  <p>Try the new create experience (faster, mobile-friendly)</p>
  <button @click="optInToNewUI">Try it now</button>
</div>
```

---

### 3.2 EXISTING CODE INTEGRATION

**Current Implementation Files** (from Phase 1):
- `src/components/secrets/form/SecretForm.vue` (444 lines)
- `src/composables/useSecretForm.ts` (152 lines)
- `src/composables/useSecretConcealer.ts` (112 lines)

**Migration Strategy**:

#### Option A: Parallel Components (Recommended)

**Pros**:
- Zero risk to existing functionality
- Easy A/B testing
- Can iterate on new version without breaking old
- Gradual migration

**Cons**:
- Temporary code duplication
- Must maintain two versions during transition

**Implementation**:
```
src/components/
├── secrets/
│   ├── form/
│   │   ├── SecretForm.vue              # OLD (keep for now)
│   │   └── SecretFormClassic.vue       # Rename old
│   └── create/                          # NEW
│       ├── CreateSecretPage.vue
│       └── ...
```

```vue
<!-- In Homepage.vue or routing -->
<SecretFormClassic v-if="!useNewExperience" />
<CreateSecretPage v-else />
```

#### Option B: In-Place Refactor

**Pros**:
- No duplication
- Forces complete migration

**Cons**:
- Higher risk
- All-or-nothing deployment
- Harder to roll back

**Not recommended** given privacy-first ethos (can't A/B test without user data)

---

### 3.3 DATA LAYER COMPATIBILITY

**Current API Endpoints** (from Phase 1):
- `POST /api/v2/secret/conceal`
- `POST /api/v2/secret/generate`

**Payload Structure** (no changes needed):
```typescript
// Current payload format (keep as-is)
{
  secret: {
    kind: 'conceal',
    secret: string,
    ttl: number,
    passphrase?: string,
    recipient?: string,
    share_domain?: string,
  }
}
```

**Backend Changes Required**: **NONE** ✅

The new UI sends identical payloads to existing API. All changes are frontend-only.

**Store Integration**:
```typescript
// Reuse existing store (no changes)
import { useSecretStore } from '@/stores/secretStore';

const secretStore = useSecretStore();

// Existing methods work as-is
await secretStore.conceal(payload);
await secretStore.generate(payload);
```

---

### 3.4 MOBILE TESTING REQUIREMENTS

**Critical Devices**:
- iPhone SE (smallest modern iOS, 375x667)
- iPhone 14 Pro Max (largest iOS, 430x932, notch)
- Samsung Galaxy S21 (Android, 360x800)
- iPad Air (tablet, 820x1180)

**Testing Checklist**:
- [ ] Textarea auto-focuses on page load
- [ ] Sticky footer always visible (even with keyboard open)
- [ ] Bottom sheet swipe gestures work smoothly
- [ ] Tap targets minimum 44x44px
- [ ] No horizontal scrolling at any width
- [ ] Safe area insets respected (notches, home indicators)
- [ ] Copy button works (clipboard API)
- [ ] QR code displays fullscreen without cropping

**Safari-Specific Issues**:
- `position: fixed` + keyboard: iOS Safari moves viewport, not layout
  - **Solution**: Use `visualViewport` API to adjust sticky footer
- `100vh` includes address bar on mobile
  - **Solution**: Use `100dvh` (dynamic viewport height)
- Zoom on input focus (if font-size < 16px)
  - **Solution**: Ensure all inputs use `text-base` (16px minimum)

```typescript
// Handle iOS keyboard resize
if (isSafariMobile) {
  window.visualViewport?.addEventListener('resize', () => {
    const footer = document.querySelector('.sticky-footer');
    if (footer) {
      footer.style.bottom = `${window.visualViewport.offsetBottom}px`;
    }
  });
}
```

---

### 3.5 PERFORMANCE BUDGETS

**Targets**:
- **First Contentful Paint**: <1.5s (mobile 3G)
- **Time to Interactive**: <3.0s (mobile 3G)
- **Largest Contentful Paint**: <2.5s
- **Cumulative Layout Shift**: <0.1
- **Total Bundle Size**: <150KB gzipped (new components only)

**Optimization Strategies**:

1. **Code Splitting**:
   ```typescript
   // Lazy load receipt page (not needed initially)
   const ReceiptPage = () => import('@/views/ReceiptPage.vue');

   // Lazy load QR code generator
   const QRCodeModal = () => import('@/components/receipt/QRCodeModal.vue');
   ```

2. **Tree Shaking**:
   ```typescript
   // Import only what's needed
   import { debounce } from 'lodash-es'; // NOT from 'lodash'
   ```

3. **Image Optimization**:
   - No images in critical path (text-only interface)
   - QR codes generated as SVG (scalable, small)

4. **CSS Purging**:
   ```javascript
   // tailwind.config.ts
   export default {
     content: ['./src/**/*.{vue,ts}'], // Purge unused
     // ...
   };
   ```

5. **Debouncing**:
   ```typescript
   // Don't run detection on every keystroke
   const debouncedDetect = debounce(detectContent, 200);
   ```

---

### 3.6 ACCESSIBILITY VERIFICATION

**Automated Testing** (CI/CD):
```bash
# Run on every PR
npm run test:a11y

# Uses jest-axe
import { axe } from 'jest-axe';
const results = await axe(wrapper.html());
expect(results).toHaveNoViolations();
```

**Manual Testing Checklist**:
- [ ] VoiceOver (macOS): Full flow navigable
- [ ] NVDA (Windows): All content announced correctly
- [ ] Keyboard only: Can complete flow without mouse
- [ ] 200% zoom: No horizontal scroll, all content readable
- [ ] High contrast mode: Borders visible, focus clear
- [ ] Reduced motion: Animations disabled

**WCAG 2.1 AA Compliance**:
- [ ] 4.5:1 contrast ratio (normal text)
- [ ] 3:1 contrast ratio (large text, UI components)
- [ ] All form inputs have labels
- [ ] All interactive elements have focus indicators
- [ ] All images have alt text (or `aria-label`)
- [ ] All time-based content has pause/stop controls
- [ ] All errors have clear, actionable messages

---

## PART 4: MIGRATION STRATEGY

### 4.1 PHASED ROLLOUT PLAN

#### Phase 0: Preparation (Week 1)
**Objective**: Set up infrastructure for parallel development

**Tasks**:
- [ ] Create feature flag system
- [ ] Set up new component directory structure
- [ ] Configure build to include both old + new components
- [ ] Add user preference storage (opt-in/opt-out)
- [ ] Create rollback plan documentation

**Success Criteria**:
- Feature flag toggles new/old UI in development
- No impact to production users

---

#### Phase 1: Internal Testing (Week 2-3)
**Objective**: Build and test with team, no external users

**Tasks**:
- [ ] Implement TextMode component (primary use case)
- [ ] Implement ModeSelector (tabs)
- [ ] Implement SuggestionBanner (detection + recommendation)
- [ ] Implement mobile BottomSheet
- [ ] Implement sticky footer
- [ ] Wire up to existing API (no backend changes)

**Testing**:
- [ ] Unit tests for detection logic
- [ ] Component tests for TextMode
- [ ] E2E test: Paste → Apply → Create → Receipt
- [ ] Manual testing on 4+ mobile devices
- [ ] Accessibility audit (axe)

**Success Criteria**:
- Core flow works end-to-end
- 0 critical bugs
- 0 accessibility violations
- Performance within budget

**Rollout**: Internal team only (`VITE_FEATURE_NEW_CREATE=true` in dev)

---

#### Phase 2: Alpha Testing (Week 4-5)
**Objective**: Test with 5-10 friendly external users

**Tasks**:
- [ ] Implement GenerateMode (password generator)
- [ ] Implement DocumentMode (markdown editor)
- [ ] Implement QRCodeModal
- [ ] Polish mobile gestures (swipe, long-press)
- [ ] Add keyboard shortcuts
- [ ] Implement user opt-out mechanism

**Testing**:
- [ ] 5-10 external users (selected, not random)
- [ ] Collect qualitative feedback (interviews)
- [ ] Monitor for errors (Sentry or similar)
- [ ] Track time-to-task (manual observation)

**Rollout**:
```typescript
features.newCreateExperience.rolloutPercentage = 0; // Manual opt-in only
// Users visit special URL: /create?beta=true
```

**Success Criteria**:
- Users complete tasks faster than old UI
- 60%+ accept suggestions (validation of detection)
- No showstopper bugs
- Positive qualitative feedback

---

#### Phase 3: Beta Testing (Week 6-8)
**Objective**: Gradual rollout to broader audience

**Tasks**:
- [ ] Implement all remaining features
- [ ] Add analytics (privacy-respecting, opt-in)
- [ ] Create "Try new UI" banner for old interface
- [ ] Implement A/B test infrastructure (if privacy allows)
- [ ] Document all features for users

**Testing**:
- [ ] 10% rollout (random selection or opt-in)
- [ ] Monitor completion rates
- [ ] Monitor error rates
- [ ] Collect feedback via optional survey

**Rollout Schedule**:
| Week | Rollout % | Users Affected | Monitoring |
|------|-----------|----------------|------------|
| 6 | 5% | ~50-100 | Intensive (hourly checks) |
| 7 | 10% | ~100-200 | Daily checks |
| 8 | 25% | ~250-500 | Twice daily |

**Success Criteria**:
- Completion rate ≥ old UI
- Error rate ≤ old UI
- <5% opt-out rate
- Performance within budget

**Rollback Trigger**:
- >10% error rate spike
- >20% opt-out rate
- Critical accessibility issue
- Performance degradation >50%

---

#### Phase 4: General Availability (Week 9-10)
**Objective**: Full rollout to all users

**Tasks**:
- [ ] 50% → 75% → 100% rollout
- [ ] Monitor for 2 weeks at 100%
- [ ] Keep old UI available via settings
- [ ] Update documentation
- [ ] Announce on homepage/changelog

**Rollout Schedule**:
| Week | Rollout % | Notes |
|------|-----------|-------|
| 9 | 50% | Monitor for 3 days |
| 9.5 | 75% | Monitor for 3 days |
| 10 | 100% | Default for all new users |

**Success Criteria**:
- Stable at 100% for 2 weeks
- All metrics better than or equal to old UI
- <3% opt-out rate

---

#### Phase 5: Deprecation (Week 12+)
**Objective**: Remove old UI (after confidence established)

**Tasks**:
- [ ] Send notification to remaining classic UI users
- [ ] Give 2-4 week notice before removal
- [ ] Remove old components from codebase
- [ ] Clean up feature flags
- [ ] Archive old code for reference

**Timeline**:
- Week 12: Announce deprecation (banner in classic UI)
- Week 14: Remove opt-in toggle (new UI only)
- Week 16: Delete old component files

---

### 4.2 ROLLBACK STRATEGY

**Scenario 1: Minor Bug in New UI**

**Trigger**: Non-critical bug affecting <5% of users

**Action**:
1. Fix bug in new UI
2. Deploy fix within 24 hours
3. Keep feature flag at current percentage
4. No rollback needed

**Example**: Copy button doesn't work on old Android versions
- **Fix**: Add fallback for clipboard API
- **Deploy**: Patch release
- **Impact**: Minimal

---

**Scenario 2: Major Bug in New UI**

**Trigger**: Critical bug affecting >5% of users OR security issue

**Action**:
1. **Immediate**: Set `rolloutPercentage = 0` (all users to old UI)
2. Investigate root cause
3. Fix bug in new UI
4. Restart rollout at previous phase (e.g., back to 10%)

**Example**: Mobile bottom sheet breaks on iOS 15
- **Rollback**: All users to old UI within minutes (feature flag update)
- **Fix**: Add iOS version detection, disable bottom sheet for iOS 15
- **Re-deploy**: Start at 5% again

---

**Scenario 3: Poor User Reception**

**Trigger**: >20% opt-out rate OR overwhelmingly negative feedback

**Action**:
1. Pause rollout (keep at current %)
2. Conduct user research (interviews, surveys)
3. Identify specific pain points
4. Re-design problematic areas
5. Restart rollout from Phase 2 (alpha)

**Example**: Users confused by auto-detection
- **Pause**: Keep at 25%
- **Research**: Interview 10 users who opted out
- **Finding**: Detection explanations too technical
- **Fix**: Simplify language, add examples
- **Re-test**: Alpha with same users

---

### 4.3 DATA MIGRATION

**Good News**: No data migration needed! ✅

**Reason**:
- Frontend-only changes
- Same API endpoints
- Same payload structure
- Same database schema

**What IS migrated**:
- **User preferences** (localStorage):
  ```typescript
  // Old preferences (keep)
  localStorage.getItem('oneTimeSecret_concealedMessages');

  // New preferences (add)
  localStorage.setItem('ots_preferences', JSON.stringify({
    useNewUI: true,
    lastUsedPreset: 'secure',
    totalSecretsCreated: 42,
  }));
  ```

**Backwards Compatibility**:
- New UI reads old localStorage (if exists)
- Old UI ignores new localStorage (no conflicts)
- Secrets created in new UI viewable in old UI (same data model)

---

### 4.4 MONITORING & METRICS

**What to Track** (Privacy-Respecting):

#### Performance Metrics (Browser APIs, no server)
```typescript
// Use PerformanceObserver API (client-side only)
const observer = new PerformanceObserver((list) => {
  for (const entry of list.getEntries()) {
    if (entry.entryType === 'navigation') {
      // Log to console or local storage only
      console.log('Time to Interactive:', entry.domInteractive);
    }
  }
});

observer.observe({ entryTypes: ['navigation'] });
```

#### Error Tracking (Opt-In, Anonymized)
```typescript
// Only if user opts in to error reporting
if (userPreferences.errorReporting) {
  window.addEventListener('error', (event) => {
    // Send anonymized error to server
    reportError({
      message: event.message,
      stack: event.error?.stack,
      component: 'CreateSecretPage',
      // NO user ID, NO IP address
    });
  });
}
```

#### Usage Patterns (Local Only)
```typescript
// Track in localStorage, never sent to server
const usage = {
  secretsCreated: 0,
  suggestionsAccepted: 0,
  suggestionsRejected: 0,
  modesUsed: {
    text: 0,
    generate: 0,
    document: 0,
  },
};

localStorage.setItem('ots_usage', JSON.stringify(usage));
```

#### Key Metrics to Watch
| Metric | Target | How to Measure |
|--------|--------|----------------|
| Time-to-task | <10s (80%) | PerformanceObserver |
| Completion rate | >95% | localStorage count |
| Error rate | <5% | Error boundary |
| Suggestion acceptance | >60% | localStorage count |
| Opt-out rate | <5% | Preference toggle count |

---

### 4.5 DOCUMENTATION UPDATES

**User-Facing Documentation**:
- [ ] Update homepage screenshots (show new UI)
- [ ] Create "What's New" announcement
- [ ] Update FAQ (common questions about new UI)
- [ ] Create video walkthrough (30-60 seconds)

**Developer Documentation**:
- [ ] Component API documentation (props, events, slots)
- [ ] Composable usage examples
- [ ] Feature flag configuration guide
- [ ] Testing guide (unit, component, e2e)
- [ ] Accessibility checklist

**Migration Guide** (for forks/deployments):
```markdown
# Migrating to New Create Experience

## For Administrators

1. Enable feature flag in `.env`:
   ```
   VITE_FEATURE_NEW_CREATE=true
   ```

2. Configure rollout percentage:
   ```typescript
   // config/features.ts
   rolloutPercentage: 10, // Start at 10%
   ```

3. Monitor for 48 hours, then increase to 25%, 50%, 100%

## For Developers

1. New components are in `src/components/create/`
2. Old components remain in `src/components/secrets/form/`
3. Both share the same API (`/api/v2/secret/conceal`)
4. No database changes required

## For End Users

- New UI is opt-in initially (banner appears)
- Can switch back via Settings → Interface → Use Classic UI
- All features work the same, just faster
```

---

## PART 5: DECISION MATRIX

### When to Use Each Approach

| Scenario | Recommended Approach | Rationale |
|----------|---------------------|-----------|
| **Privacy-first service** (no analytics) | **Parallel Components** | Can't A/B test without data, need opt-in/opt-out |
| **High-traffic service** (can A/B test) | **Gradual Rollout** | Data-driven decisions, automatic rollback |
| **Small user base** (<1000 users) | **All-at-Once** | Not enough users to phase, just migrate |
| **Enterprise deployment** (internal) | **Feature Flag** | IT can control rollout, instant rollback |
| **Open source** (many forks) | **Parallel Components** | Forks can choose timing, less disruptive |

**For OneTimeSecret** (privacy-first, no analytics):
→ **Recommended: Parallel Components + Gradual Opt-In**

---

## SUMMARY: RECOMMENDED PATH FORWARD

### IMMEDIATE NEXT STEPS (This Week)

1. **Team Review** (2-4 hours)
   - Present this recommendation to team
   - Discuss concerns, get buy-in
   - Align on timeline and priorities

2. **Spike/Prototype** (1-2 days)
   - Build minimal TextMode component
   - Test with real backend API
   - Validate technical assumptions
   - Get feel for development velocity

3. **Decision Point** (End of Week)
   - ✅ Proceed with implementation (10-week plan)
   - ⏸️ Pause for more research (specific concerns)
   - ❌ Defer (not priority now)

---

### IMPLEMENTATION TIMELINE (IF APPROVED)

| Phase | Duration | Deliverables | Risk |
|-------|----------|--------------|------|
| **0. Prep** | Week 1 | Feature flags, directory structure | Low |
| **1. Internal** | Week 2-3 | TextMode, mobile UI, basic flow | Medium |
| **2. Alpha** | Week 4-5 | GenerateMode, DocumentMode, QR | Medium |
| **3. Beta** | Week 6-8 | 5% → 10% → 25% rollout | High |
| **4. GA** | Week 9-10 | 50% → 100% rollout | Medium |
| **5. Deprecate** | Week 12+ | Remove old UI | Low |

**Total**: 12-16 weeks from approval to full deployment

---

### SUCCESS DEFINITION

This redesign is successful if, after 12 weeks:

✅ **80% of users** complete secret creation in <10 seconds
✅ **95% mobile completion rate** (parity with desktop)
✅ **60% suggestion acceptance** (validation of smart detection)
✅ **<5% opt-out rate** (users prefer new UI)
✅ **0 critical accessibility violations** (WCAG 2.1 AA compliant)
✅ **0 performance regressions** (within budget)
✅ **Positive team feedback** (maintainable, extensible)

**If any of these fail**: Pause, investigate, iterate, or rollback.

---

## FINAL RECOMMENDATION

**Proceed with Hybrid Express Model implementation** using the 10-week phased rollout strategy.

**Why this approach wins**:
1. **Measurable impact**: 50-85% faster across all user scenarios
2. **Low risk**: Parallel components allow instant rollback
3. **Privacy-aligned**: No tracking required, opt-in/opt-out user control
4. **Future-ready**: Enables Linear Secrets, Inbound Secrets, QR codes, markdown
5. **Accessibility-first**: WCAG 2.1 AA compliance from day one
6. **Mobile-optimized**: Native patterns, not responsive compromise

**Trade-offs accepted**:
- 12-week timeline (vs instant big-bang migration)
- Temporary code duplication (vs refactoring in place)
- Gradual rollout (vs immediate improvement for all users)

**The alternative** (doing nothing):
- Current UX friction remains (30-60s time-to-task)
- Mobile abandonment continues (button below fold)
- Feature discovery poor (Generate mode hidden)
- Technical debt increases (harder to add new features)

---

## OPEN QUESTIONS FOR TEAM

Before proceeding, we need alignment on:

1. **Timeline**: Is 12-week realistic given team capacity?
2. **Priorities**: Any features we should cut to ship faster?
3. **Testing**: What level of user testing is acceptable (privacy)?
4. **Rollout**: Comfortable with gradual opt-in approach?
5. **Metrics**: How will we measure success without analytics?

**Recommended: 60-minute working session to address these questions.**

---

## APPENDIX: IMPLEMENTATION CHECKLIST

### Phase 0: Preparation
- [ ] Create feature flag system
- [ ] Set up `src/components/create/` directory
- [ ] Configure build for parallel components
- [ ] Document rollback procedure
- [ ] Set up error monitoring (opt-in)

### Phase 1: Core Components
- [ ] ModeSelector.vue (tabs)
- [ ] TextMode.vue (main use case)
- [ ] SecretTextarea.vue (auto-focus, counter)
- [ ] SuggestionBanner.vue (detection + recommendation)
- [ ] SecurityOptions.vue (presets)
- [ ] CreateButton.vue (loading states)
- [ ] BottomSheet.vue (mobile)
- [ ] StickyFooter.vue (mobile)

### Phase 2: Extended Features
- [ ] GenerateMode.vue (password generator)
- [ ] PasswordOptions.vue
- [ ] StrengthMeter.vue
- [ ] DocumentMode.vue (markdown)
- [ ] MarkdownEditor.vue
- [ ] MarkdownPreview.vue
- [ ] AdvancedOptions.vue (email, QR, markdown toggles)

### Phase 3: Receipt & Sharing
- [ ] ReceiptPage.vue (enhanced)
- [ ] SecretLink.vue (copy button)
- [ ] PassphraseDisplay.vue (copy, show/hide)
- [ ] QRCodeModal.vue (fullscreen)
- [ ] ShareOptions.vue (copy, QR, email)
- [ ] ExpirationInfo.vue (countdown)
- [ ] BurnButton.vue (confirmation)

### Phase 4: Composables
- [ ] useSecretCreation.ts
- [ ] useContentDetection.ts
- [ ] useUserPreferences.ts
- [ ] useKeyboardShortcuts.ts
- [ ] usePasswordGenerator.ts
- [ ] useFocusManagement.ts

### Phase 5: Utilities
- [ ] contentDetection.ts (pattern matching)
- [ ] passphraseGenerator.ts (memorable phrases)
- [ ] expirationFormatter.ts (human-readable TTL)
- [ ] qrCodeGenerator.ts (canvas/SVG)

### Phase 6: Testing
- [ ] Unit tests (detection logic)
- [ ] Unit tests (passphrase generation)
- [ ] Component tests (TextMode)
- [ ] Component tests (GenerateMode)
- [ ] E2E tests (happy path)
- [ ] E2E tests (error handling)
- [ ] Accessibility tests (axe)
- [ ] Performance tests (Lighthouse)

### Phase 7: Documentation
- [ ] Component API docs
- [ ] Composable usage examples
- [ ] Testing guide
- [ ] Migration guide
- [ ] User announcement
- [ ] Video walkthrough

---

**Document Version**: 1.0
**Last Updated**: 2025-11-18
**Status**: Awaiting Team Review
**Next Step**: Schedule 60-minute working session to discuss and align
