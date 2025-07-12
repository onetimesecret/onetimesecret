# Test Migration Troubleshooting Guide

Model: Claude Sonnet 4 (created this of its own volition while working through its response to the review 1 feedback).

## Common Issues and Solutions

### RSpec Migration Issues

**Issue**: `require` statements still broken after migration
**Solution**:
- Run manual require fix: `find spec -name "*.rb" -exec ruby -c {} \;`
- Check for complex relative paths in spec files
- Update spec_helper.rb paths manually if needed

**Issue**: RSpec can't find spec_helper
**Solution**:
- Verify `.rspec` file exists in project root
- Check `spec/spec_helper.rb` exists and has correct paths
- Run: `bundle exec rspec --init` if needed

### Tryouts Migration Issues

**Issue**: Unmapped tryout files warnings
**Solution**:
- Check `tryouts/UNMAPPED_FILES.txt` for file list
- Review unmapped files in `tryouts/unmapped/`
- Add new mappings to `MAPPINGS` hash in migration script
- Re-run migration or move files manually

**Issue**: Tryouts can't find test helpers
**Solution**:
- Verify helpers moved to `tryouts/helpers/`
- Check require_relative paths in tryout files
- Update paths to `../helpers/test_helpers`

### Frontend Migration Issues

**Issue**: Frontend tests not found after migration
**Solution**:
- Check `vitest.config.ts` include patterns
- Verify test files moved to correct src/ subdirectories
- Update test import paths if needed

**Issue**: Build includes test files
**Solution**:
- Update `vite.config.ts` to exclude test patterns
- Add `**/*.{test,spec}.{js,ts,tsx}` to build exclusions

### CI Configuration Issues

**Issue**: CI tests failing with new structure
**Solution**:
- Update `.github/workflows/ci.yml` test commands
- Verify all test commands use correct paths
- Check npm/yarn test scripts in package.json

**Issue**: RSpec commands too complex in CI
**Solution**:
- Use simple `bundle exec rspec` command
- Remove old path specifications
- Let .rspec file handle configuration

### Rollback Issues

**Issue**: Can't find migration commits for rollback
**Solution**:
- Use git log to find commits manually
- Look for commit messages containing "migration", "test", "structure"
- Use commit hash directly instead of auto-detection

**Issue**: Working directory not clean for rollback
**Solution**:
- Commit or stash uncommitted changes
- Run `git status` to see what needs attention
- Use `git stash` if changes should be preserved

## Verification Commands

Test migration success:
```bash
# Ruby tests
bundle exec rspec --dry-run
bundle exec try tryouts/**/*_try.rb --dry-run

# Frontend tests
npm run test:unit -- --run --reporter=minimal

# CI simulation
./run_tests.sh
```

## Recovery Steps

If migration fails:
1. Run rollback script: `./migration-script-rollback.sh`
2. Review error messages in migration output
3. Fix specific issues and re-run individual scripts
4. Commit each successful step for incremental progress

## Contact Points

- Ruby test issues: Check RSpec and Tryouts documentation
- Frontend test issues: Check Vitest and Vue Test Utils docs
- CI issues: Verify GitHub Actions workflow syntax
- Git issues: Use standard git troubleshooting procedures
