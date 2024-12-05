# Plan for Transitioning AccountDomainBrand to Store-Based Architecture

## Design Goals
- Clear separation of concerns
- Type safety throughout the application
- Consistent error handling
- Testable code structure
- Maintainable codebase
- Reusable business logic

## 1. Original Implementation Analysis

### Core Functionality
1. Brand Settings Management
   - Fetches settings from `/api/v2/account/domains/{domainId}/brand`
   - Manages state via reactive refs (brandSettings, loading, error, etc.)
   - Handles unsaved changes tracking
   - Processes form submissions via PUT requests

2. Image Management
   - Handles image upload (POST) and removal (DELETE)
   - Updates UI to reflect image state
   - Manages upload/removal loading states

3. Real-time Preview
   - Updates SecretPreview component in real-time
   - Handles browser type switching (safari/edge)
   - Provides immediate feedback for customization changes

### Component Interactions
1. Parent-Child Communication
   - BrandSettingsBar: Receives and emits setting updates
   - SecretPreview: Displays live preview based on settings
   - BrowserPreviewFrame: Handles browser type switching

2. Service Integration
   - CSRF Store: Security token management
   - Notifications Store: User feedback
   - API Utility: HTTP request handling via request/response interceptors
     - Uses CSRF Store. Notifies on API errors.

## 2. Architecture Overview

### Data Flow
```
[Components] <-> [Composable] <-> [Store] <-> [API]
     ^               ^              ^           ^
     |               |              |           |
   [Types] <---- [Zod Schema] -> [Validation]   |
     |                                          |
     +------------------------------------------+
```

### Responsibilities

1. Components (UI Layer)
   - Render UI elements and handle user interactions
   - Emit events for user actions
   - Display loading/error states
   - Use composables for business logic
   - NO direct API calls or store mutations
   - Focus on presentation and user interaction only

2. Composable (Business Logic Layer)
   - Extend existing useDomainBranding composable
   - Handle form validation and state management
   - Transform data between store and components
   - Manage UI-specific state (e.g., preview settings)
   - Track unsaved changes
   - Coordinate between multiple stores if needed
   - NO direct API calls

3. Store (Data Layer)
   - Manage global state for brand settings and image
   - Handle all API communication
   - Validate API responses using Zod schemas
   - Manage loading/error states
   - Cache management
   - Expose actions and getters
   - NO UI logic

4. Zod Schema (Type Layer)
   - Define and validate data structures
   - Generate TypeScript types
   - Ensure type safety across layers
   - Provide runtime validation

## 3. Implementation Structure

### 1. Type Definitions & Schemas
```typescript
// @/schemas/models/domain/brand.ts
// Extend existing domain schemas
export const brandSettingsSchema = z.object({
  primary_color: z.string().regex(/^#[0-9A-F]{6}$/i),
  font_family: z.enum(['sans-serif', 'serif', 'monospace']),
  corner_style: z.enum(['rounded', 'sharp']),
  button_text_light: z.boolean(),
  instructions_pre_reveal: z.string(),
  instructions_post_reveal: z.string(),
  instructions_reveal: z.string(),
  allow_public_homepage: z.boolean(),
  allow_public_api: z.boolean(),
});

export type BrandSettings = z.infer<typeof brandSettingsSchema>;

// Reuse image schema if it exists in the codebase
export const imageSchema = z.object({
  url: z.string().url(),
  width: z.number(),
  height: z.number(),
  size: z.number(),
  type: z.string()
});

export type Image = z.infer<typeof imageSchema>;
```

### 2. Store Implementation
```typescript
// stores/brandSettingsStore.ts
export const useBrandSettingsStore = defineStore('brandSettings', {
  state: () => ({
    settings: null as BrandSettings | null,
    originalSettings: null as BrandSettings | null,
    loading: false,
    error: null as string | null,
    isSubmitting: false,
    hasUnsavedChanges: false,
    logoImage: null as ImageProps | null
  }),

  actions: {
    async fetchSettings(domainId: string) {
      // Implement fetching logic
    },

    async updateSettings(domainId: string, settings: Partial<BrandSettings>) {
      // Implement update logic
    },

    async uploadLogo(domainId: string, file: File) {
      // Implement logo upload
    },

    async removeLogo(domainId: string) {
      // Implement logo removal
    }
  },

  getters: {
    // Add computed properties
  }
})
```

2. Enhance DomainsManager
```typescript
// composables/useDomainsManager.ts
export function useDomainsManager() {
  const brandStore = useBrandSettingsStore()

  // Add brand management methods
  const manageBrandSettings = (domainId: string) => {
    return {
      fetchSettings: () => brandStore.fetchSettings(domainId),
      updateSettings: (settings: Partial<BrandSettings>) =>
        brandStore.updateSettings(domainId, settings),
      uploadLogo: (file: File) => brandStore.uploadLogo(domainId, file),
      removeLogo: () => brandStore.removeLogo(domainId)
    }
  }

  return {
    // Existing methods
    manageBrandSettings
  }
}
```

### Phase 2: Component Refactoring

1. Update AccountDomainBrand.vue
```typescript
// Transition from local state to store
const brandStore = useBrandSettingsStore()
const { manageBrandSettings } = useDomainsManager()

// Replace local refs with store state
const brandSettings = computed(() => brandStore.settings)
const loading = computed(() => brandStore.loading)
const error = computed(() => brandStore.error)
const hasUnsavedChanges = computed(() => brandStore.hasUnsavedChanges)

// Update methods to use store actions
const submitForm = () => manageBrandSettings(domainId).updateSettings(brandSettings.value)
```

2. Update Child Components
   - Pass store state via props
   - Update event handlers to commit to store
   - Maintain real-time preview functionality

### Phase 3: Navigation & Error Handling

1. Implement Navigation Guards
```typescript
// Router guard using store state
onBeforeRouteLeave((to, from, next) => {
  if (brandStore.hasUnsavedChanges) {
    // Confirm navigation
  } else {
    next()
  }
})
```

2. Error Boundaries
   - Add error handling in store actions
   - Implement error displays in components
   - Maintain notification integration

### Phase 4: Type Safety

1. Zod Schema Integration
```typescript
// Validate store mutations
const updateSettings = (settings: Partial<BrandSettings>) => {
  const validated = brandSettingsSchema.parse(settings)
  // Update store
}
```

2. Runtime Validation
   - Add validation at API boundaries
   - Validate component props
   - Add type guards for store state

## Testing Strategy

1. Store Tests
```typescript
describe('BrandSettingsStore', () => {
  test('fetchSettings loads brand settings', async () => {
    // Test store actions
  })

  test('updateSettings handles validation', () => {
    // Test validation
  })
})
```

2. Component Tests
   - Test store integration
   - Verify real-time updates
   - Check error handling

3. E2E Tests
   - Test full user flows
   - Verify navigation guards
   - Check preview functionality

## Migration Steps

1. Implement Store (Day 1-2)
   - Create store with full functionality
   - Add tests
   - Verify API integration

2. Update Components (Day 3-4)
   - Refactor AccountDomainBrand
   - Update child components
   - Add component tests

3. Add Safety Features (Day 5)
   - Implement validation
   - Add error boundaries
   - Update navigation guards

4. Testing & Validation (Day 6-7)
   - Run full test suite
   - Verify all features
   - Document changes

## Success Criteria

1. Functionality
   - All existing features work as before
   - Real-time preview maintains responsiveness
   - Form submission handling works correctly

2. Code Quality
   - Full type safety with zod schemas
   - Comprehensive test coverage
   - Clear error handling

3. Performance
   - No degradation in UI responsiveness
   - Efficient state updates
   - Optimized store mutations

## Risk Mitigation

1. Feature Regression
   - Comprehensive test suite
   - Feature parity verification
   - Gradual rollout

2. Performance Impact
   - Monitor state update frequency
   - Profile store operations
   - Optimize as needed

3. Developer Experience
   - Clear documentation
   - Type safety throughout
   - Consistent patterns

## Next Steps

1. Begin store implementation
2. Create test suite
3. Start component refactoring
4. Add validation layer
5. Implement navigation guards
6. Run full testing cycle
