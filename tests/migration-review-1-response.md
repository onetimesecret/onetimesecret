# Test Migration Action Plan

Model: Claude Sonnet 4

## Priority 1: Critical Issues (Must Fix)

### 1.1 Improve require statement handling in migration-script-2-rspec.sh
**Issue**: Simple `sed` commands may not handle complex `require_relative` paths correctly.

**Action**:
- Add more robust regex patterns to handle edge cases
- Create a verification step to check for broken requires after migration
- Add fallback handling for complex require patterns

### 1.2 Handle unmapped tryout files better in migration-script-3-tryouts.rb
**Issue**: Files without mappings only get warnings, potentially leaving orphaned files.

**Action**:
- Create an `unmapped/` directory under `tryouts/`
- Move unmapped files there instead of just warning
- Generate a report of unmapped files for manual review

### 1.3 Add frontend test structure consistency
**Issue**: Frontend tests remain under `tests/` while Ruby tests move to `spec/` and `tryouts/`.

**Action**:
- Create migration-script-6-frontend.sh to move frontend tests to co-located structure under `src/`
- Update vite.config.ts to ensure proper test file exclusion from builds
- Update CI configuration to run tests from new locations

## Priority 2: Enhancements (Should Do)

### 2.1 Improve verification script
**Action**:
- Add actual test execution to verify migrations work
- Check for broken require statements by running a syntax check
- Validate that moved files can be required without errors

### 2.2 Enhanced CI configuration updates
**Action**:
- Create a backup and restore mechanism for CI changes
- Add validation that CI commands work before finalizing changes
- Update package.json test scripts programmatically using Node.js instead of manual review

### 2.3 Add rollback capability
**Action**:
- Create migration-script-rollback.sh to undo changes if needed
- Store original file locations in a manifest
- Implement git-based rollback using recorded moves

## Priority 3: Nice to Have (Could Do)

### 3.1 Improve mapping system for tryouts
**Action**:
- Make the mapping system more flexible/configurable
- Add ability to specify mappings via external file
- Add mapping validation before migration starts

### 3.2 Add progress indicators
**Action**:
- Add progress bars or counters to long-running operations
- Provide ETA for migration completion
- Add verbose mode for debugging

## Implementation Plan

### Phase 1: Fix Critical Issues
1. Update migration-script-2-rspec.sh with robust require handling
2. Update migration-script-3-tryouts.rb to handle unmapped files
3. Create migration-script-6-frontend.sh for Vue test co-location
4. Test all scripts in a branch

### Phase 2: Enhancements
1. Improve verification script with actual test execution
2. Enhance CI configuration updates
3. Add rollback capability
4. Update migration-script-runner.sh to include new frontend script

### Phase 3: Testing and Documentation
1. Test complete migration flow on a clean branch
2. Update documentation
3. Create troubleshooting guide
4. Prepare final migration for main branch

## Files to Modify

### Existing Scripts
- `migration-script-2-rspec.sh`: Enhanced require statement handling
- `migration-script-3-tryouts.rb`: Better unmapped file handling
- `migration-script-4-ci.sh`: Enhanced CI updates
- `migration-script-5-verify.sh`: More thorough verification
- `migration-script-runner.sh`: Include new frontend script

### New Scripts
- `migration-script-6-frontend.sh`: Frontend test co-location
- `migration-script-rollback.sh`: Rollback capability

### Configuration Updates
- Update `vite.config.ts` for proper test file handling
- Update `.github/workflows/ci.yml` for new frontend test locations
- Modify `package.json` test scripts programmatically

## Success Criteria

- [ ] All Ruby tests (RSpec + tryouts) successfully migrated
- [ ] All frontend tests co-located under `src/`
- [ ] CI passes with new test structure
- [ ] No broken require statements or imports
- [ ] All unmapped files properly handled
- [ ] Rollback capability tested and working
- [ ] Documentation updated and clear

## Risk Mitigation

- All changes tracked in git with granular commits for each migration step
- Run all migrations in feature branches first
- Keep detailed logs of all file moves
- Test migration process independently (test suites currently not passing due to ongoing major refactor)
- Have rollback capability ready using git history
- Test migration on copy of repository first
- Use git to track original file locations for potential rollback
