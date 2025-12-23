# Plan Testing Mode - Test Coverage

This document outlines the test coverage for Issue #2244 - Plan Testing Mode for Colonels.

## Test Files Created

### 1. PlanTestModal Component Tests
**Location**: `src/apps/colonel/components/__tests__/PlanTestModal.test.ts`

**Coverage**:
- **Rendering**: Modal visibility, plan list display
- **Current Test Plan Display**: Shows active test plan, actual plan, reset option
- **Plan Selection**: API calls with correct planid, reset functionality, error handling
- **Loading State**: Loading indicators, button states during API calls
- **Events**: Close events, page reload on success
- **Integration**: Plan descriptions, active plan highlighting, dual plan display
- **Edge Cases**: Missing data, invalid selections, network timeouts

**Total Test Cases**: 23 tests across 7 describe blocks

**Key Patterns Used**:
- Vue Test Utils mounting with proper Pinia setup
- AxiosMockAdapter for API mocking
- WindowService mocking for state injection
- Comprehensive error and edge case handling

---

### 2. useTestPlanMode Composable Tests
**Location**: `src/shared/composables/__tests__/useTestPlanMode.test.ts`

**Coverage**:
- **isTestModeActive**: Returns correct boolean based on window state
- **testPlanId**: Reads and returns test plan ID from window
- **testPlanName**: Reads and returns test plan name from window
- **actualPlanId**: Reads organization's actual plan
- **Integration Scenarios**: Complete state when active/inactive
- **Reactivity**: Computed value behavior
- **Edge Cases**: WindowService errors, partial state, whitespace handling

**Total Test Cases**: 19 tests across 7 describe blocks

**Expected Composable Interface**:
```typescript
{
  isTestModeActive: ComputedRef<boolean>
  testPlanId: ComputedRef<string | null>
  testPlanName: ComputedRef<string | null>
  actualPlanId: ComputedRef<string | undefined>
}
```

---

### 3. UserMenu Component Tests
**Location**: `src/shared/components/navigation/__tests__/UserMenu.test.ts`

**Coverage**:
- **Basic Rendering**: Menu trigger, avatar, menu visibility
- **Test Plan Mode Menu Item**: Shows for colonels, hides for non-colonels, beaker icon
- **Visual Variants**: Caution variant when active, default when inactive
- **Click Behavior**: Opens modal, hidden during MFA
- **Menu Item Ordering**: Proper section placement, dividers
- **Integration**: Works with other menu items, billing conditional display
- **MFA State**: Limited menu during MFA, amber styling, badge display
- **Click Outside**: Menu closes properly
- **Logout**: Calls logout handler, danger variant styling
- **Edge Cases**: Missing customer data, long emails, WindowService errors
- **Accessibility**: ARIA attributes, roles, labels

**Total Test Cases**: 31 tests across 11 describe blocks

**Key Features Tested**:
- Colonel-only visibility
- Test mode active indicator (caution variant)
- Modal triggering
- Integration with existing menu structure
- MFA flow compatibility

---

## Running the Tests

### Run All Plan Test Mode Tests
```bash
pnpm test PlanTestModal
pnpm test useTestPlanMode
pnpm test UserMenu
```

### Run with Coverage
```bash
pnpm run test:coverage -- PlanTestModal
pnpm run test:coverage -- useTestPlanMode
pnpm run test:coverage -- UserMenu
```

### Watch Mode
```bash
pnpm run test:watch -- PlanTestModal
```

---

## Test Patterns Used

### WindowService Mocking
```typescript
vi.mock('@/services/window.service', () => ({
  WindowService: {
    get: vi.fn(),
    getState: vi.fn(() => ({})),
  },
}));

// In tests:
vi.mocked(WindowService.get).mockImplementation((key: string) => {
  if (key === 'entitlement_test_planid') return 'identity_v1';
  return undefined;
});
```

### API Mocking
```typescript
const axiosMock = new AxiosMockAdapter(api);

axiosMock.onPost('/api/colonel/entitlement-test').reply(200, {
  status: 'active',
  test_planid: 'identity_v1',
  entitlements: ['custom_domains'],
});
```

### Component Mounting
```typescript
const wrapper = mount(Component, {
  props: { ... },
  global: {
    plugins: [createTestingPinia({ createSpy: vi.fn })],
    provide: { api },
    stubs: { OIcon: { template: '<span />' } },
  },
});
```

---

## Implementation Checklist

When implementing the actual components, ensure:

### PlanTestModal.vue
- [ ] Accepts `open` prop (v-model)
- [ ] Displays available plans from `Billing::Plan.available_plans`
- [ ] Shows current test plan when active
- [ ] Shows reset/clear option when override active
- [ ] Makes POST request to `/api/colonel/entitlement-test`
- [ ] Handles loading state with disabled buttons
- [ ] Reloads page on successful plan change
- [ ] Emits close/update:open event

### useTestPlanMode.ts (Composable)
- [ ] Returns `isTestModeActive` computed
- [ ] Returns `testPlanId` from WindowService
- [ ] Returns `testPlanName` from WindowService
- [ ] Returns `actualPlanId` from organization
- [ ] Handles missing WindowService data gracefully
- [ ] Trims whitespace from planid values

### UserMenu.vue Updates
- [ ] Add "Test Plan Mode" menu item
- [ ] Only show for colonels (`props.colonel`)
- [ ] Hide during MFA (`!props.awaitingMfa`)
- [ ] Use beaker icon
- [ ] Use caution variant when test mode active
- [ ] Opens PlanTestModal on click
- [ ] Proper placement with dividers

---

## Test Data

### Available Plans
```typescript
const availablePlans = [
  { id: 'free', name: 'Free', description: 'Basic features only' },
  { id: 'identity_v1', name: 'Identity Plus', description: 'Custom domains, priority support' },
  { id: 'multi_team_v1', name: 'Multi-Team', description: 'API access, audit logs, analytics' },
];
```

### Window State Structure
```typescript
interface WindowState {
  entitlement_test_planid?: string | null;
  entitlement_test_plan_name?: string | null;
  organization?: {
    planid?: string;
  };
}
```

---

## Expected API Endpoints

### POST /api/colonel/entitlement-test

**Request**:
```json
{
  "planid": "identity_v1"  // or null to clear
}
```

**Success Response (200)**:
```json
{
  "status": "active",
  "test_planid": "identity_v1",
  "test_plan_name": "Identity Plus",
  "actual_planid": "free",
  "entitlements": ["custom_domains", "priority_support"]
}
```

**Clear Response (200)**:
```json
{
  "status": "cleared",
  "actual_planid": "free"
}
```

**Error Response (400/500)**:
```json
{
  "error": "Error message"
}
```

---

## Notes

- Tests are written following project patterns from existing test files
- All tests use Vitest + Vue Test Utils
- Mocking patterns match existing composable/component tests
- WindowService mocking pattern consistent with languageStore tests
- API mocking uses AxiosMockAdapter like authStore tests
- Component mounting follows ThemeToggle.spec.ts pattern
- Accessibility tests included per project standards

## Next Steps

1. Implement `PlanTestModal.vue` component
2. Implement `useTestPlanMode.ts` composable
3. Update `UserMenu.vue` with Test Plan Mode menu item
4. Implement backend API endpoint
5. Run tests to verify implementation
6. Add i18n keys for UI text
7. Manual QA testing
