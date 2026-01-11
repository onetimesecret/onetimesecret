# Billing Validation Commands Specification

## Overview

This specification addresses UX and clarity issues in the billing validation CLI commands (`prices validate`, `plans validate`, `products validate`). The goal is to provide consistent, informative output that matches Stripe dashboard patterns and clearly communicates validation status.

## Current Issues

### 1. Price ID Truncation Confusion
**Issue:** Price IDs appear truncated in the table (e.g., `price_1SWaFKH5`) but show full ID in error messages (e.g., `price_1SWaFKH54PcLeqtYrxz3QnGS`), making them appear as different prices.

**Impact:** Users cannot correlate errors with table rows, especially when multiple prices exist.

**Root Cause:** Line 227 in `prices_validate_command.rb`:
```ruby
price.id[0..13]  # Truncates to 15 chars but Stripe price IDs are 28 chars
```

### 2. Archived Product Context Missing
**Issue:** Error message "Product prod_abcd1234 not found or inactive" doesn't explain these are ARCHIVED products.

**Impact:** Users don't understand why a price can't be used. Stripe UI helpfully shows: "This price is attached to an archived product so it can't be used to create new subscriptions."

**Root Cause:** Lines 76-78 in `prices_validate_command.rb` only check active products, but don't distinguish between non-existent and archived.

### 3. Validation Status Placement
**Issue:** VALIDATION FAILED status appears in middle of output (after table, before error details) instead of at the end.

**Impact:** Non-standard CLI pattern. Users expect summary at top and/or final status at bottom.

**Current Flow:**
```
Validating Stripe prices...

[TABLE]

Total: X price(s)

━━━━━━━━━━━━━━━━━━━━
❌  VALIDATION FAILED: 2 error(s) found
━━━━━━━━━━━━━━━━━━━━

  ✗ Error 1
  ✗ Error 2
```

### 4. Missing Price Count in Products Output
**Issue:** `products validate` command doesn't show price counts in actual output, only in validation messages.

**Impact:** Users can't see at-a-glance which products have prices configured.

**Current Code:** Lines 140-158 fetch price counts but only display in VALID section, not in summary table.

### 5. Inconsistent Status Indicators
**Issue:** Different emoji/text patterns across commands:
- `prices`: `✓`, `⚠️  WARNING`, `✗ INVALID`
- `plans`: `✓ Ready`, `⚠️  WARNING`, `✗ INVALID`, `✗ NOT READY - No prices`
- `products`: `✓`, `✗`

**Impact:** Inconsistent UX across related commands.

## Design Principles

### 1. Stripe Dashboard Patterns
Match Stripe's UX patterns for familiarity:
- Clear status badges (Active, Archived, Inactive)
- Helpful contextual messages
- Grouped information (products → prices hierarchy)
- Action-oriented guidance

### 2. CLI Best Practices
- Summary information at top (counts, scope)
- Detailed table in middle
- Status and errors at bottom
- Exit codes: 0 for success, 1 for failure
- Color coding for quick scanning (when TTY)

### 3. Actionability
Every error/warning should:
- Explain what's wrong
- Explain why it matters
- Suggest resolution when possible

### 4. Consistency
- Same column widths and formats across commands
- Same status indicator scheme
- Same error message patterns
- Same validation result format

## Proposed Output Format

### Standard Structure
```
[COMMAND HEADER]
[SCOPE INFORMATION]

[SUMMARY SECTION - counts and overview]

[DETAILED TABLE]

[ISSUES SECTION - errors and warnings grouped]

[FINAL STATUS - clear pass/fail with exit code]
```

### Example: `billing prices validate` (Success)

```
Validating Stripe prices...
Scope: All active prices (filtered: none)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total prices:        12
  Valid prices:        12
  Prices with errors:  0
  Prices with warnings: 0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRICES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRICE ID                      PRODUCT              AMOUNT      INTERVAL  STATUS
price_1SWaFKH54PcLeqtYrxz3Qn  Identity Plus (US)   USD 9.00    month     ✓ Valid
price_1SWaFL954PcLeqtYabcdXY  Identity Plus (US)   USD 90.00   year      ✓ Valid
price_1SWaFM054PcLeqtYdefgAB  Team Plus (US)       USD 29.00   month     ✓ Valid
[...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅  VALIDATION PASSED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

All prices are valid and ready for use.
```

### Example: `billing prices validate` (Failure)

```
Validating Stripe prices...
Scope: All active prices (filtered: none)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total prices:        12
  Valid prices:        10
  Prices with errors:  2
  Prices with warnings: 1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRICES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRICE ID                      PRODUCT              AMOUNT      INTERVAL  STATUS
price_1SWaFKH54PcLeqtYrxz3Qn  Identity Plus (US)   USD 9.00    month     ✓ Valid
price_1SWaFL954PcLeqtYabcdXY  (Archived Product)   USD 90.00   year      ✗ Unusable
price_1SWaFM054PcLeqtYdefgAB  Team Plus (US)       USD 29.00   month     ⚠ Warning
price_1SWaFN154PcLeqtYghijCD  (Archived Product)   USD 0.00    month     ✗ Invalid
[...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERRORS (2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✗ price_1SWaFL954PcLeqtYabcdXY: Attached to archived product

    Product prod_ABC123 is archived and cannot be used for new subscriptions.

    Resolution:
    - Create new active product if needed
    - Archive this price if no longer needed
    - See: https://dashboard.stripe.com/prices/price_1SWaFL954PcLeqtYabcdXY

  ✗ price_1SWaFN154PcLeqtYghijCD: Invalid price configuration

    Price amount is $0.00 (use free tier product instead of zero-price).
    Attached to archived product prod_DEF456.

    Resolution:
    - Archive this price
    - Use proper free tier product for $0 plans

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WARNINGS (1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⚠ price_1SWaFM054PcLeqtYdefgAB: Pricing consistency issue

    Yearly price $290.00 is not 10-12x monthly price $29.00.
    Consider adjusting for typical SaaS discount pattern.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌  VALIDATION FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2 price(s) have errors that prevent them from being used.
Fix errors above or use --help for guidance.

Run with --strict to treat warnings as errors.
```

### Example: `billing plans validate` (Improved)

```
Validating plan production readiness...
Scope: Active products with app=onetimesecret metadata

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total products:      6
  Production ready:    5
  Not ready:           1
  Issues found:        2 errors, 1 warning

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PLANS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRODUCT ID             PLAN ID              REGION  PRICES           STATUS
prod_ABC123456789012   identity_plus_v1_us  US      2 (month, year)  ✓ Ready
prod_DEF345678901234   team_plus_v1_us      US      2 (month, year)  ✓ Ready
prod_GHI567890123456   org_plus_v1_global   global  2 (month, year)  ✓ Ready
prod_JKL789012345678   org_max_v1_global    global  1 (month)        ⚠ Incomplete
prod_MNO901234567890   legacy_pro_v1_us     US      0                ✗ Not Ready
prod_PQR012345678901   identity_plus_v1_ca  CA      2 (month, year)  ✓ Ready

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERRORS (2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✗ prod_MNO901234567890 (legacy_pro_v1_us): No recurring prices

    Product has 0 recurring prices and cannot be used for subscriptions.

    Resolution:
    - Create monthly and yearly prices
    - Or archive product if no longer offered

  ✗ prod_PQR012345678901 (identity_plus_v1_ca): Missing required metadata

    Required metadata field 'tier' is missing.

    Resolution:
    - Update product metadata: bin/ots billing products update prod_PQR012345678901 --tier single_user

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WARNINGS (1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⚠ prod_JKL789012345678 (org_max_v1_global): Missing yearly price

    Product only has monthly pricing. Annual pricing is recommended for better LTV.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌  VALIDATION FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1 product(s) not production ready. 2 errors must be fixed.

Plans with errors cannot be offered to customers.
Run with --strict to treat warnings as errors.
```

### Example: `billing products validate` (Improved)

```
Fetching products from Stripe API [sk_live_51A2B.../2024-12-18]... found 8 product(s) in 234ms

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total products:      8
  Valid metadata:      6
  Incomplete:          2
  Duplicate plan_ids:  0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRODUCTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRODUCT ID             NAME                 PLAN ID              REGION  PRICES  STATUS
prod_ABC123456789012   Identity Plus (US)   identity_plus_v1_us  US      2       ✓ Valid
prod_DEF345678901234   Team Plus (US)       team_plus_v1_us      US      2       ✓ Valid
prod_GHI567890123456   Free Tier            free_v1              global  0       ✓ Valid
prod_JKL789012345678   Test Product         n/a                  n/a     1       ✗ Incomplete
prod_MNO901234567890   Legacy Pro           legacy_pro_v1        US      0       ✗ Incomplete
prod_PQR012345678901   Org Plus (Global)    org_plus_v1_global   global  2       ✓ Valid

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INCOMPLETE PRODUCTS (2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✗ prod_JKL789012345678 (Test Product)

    Missing required metadata: plan_id, region, tier

    Resolution:
    - Update metadata: bin/ots billing products update prod_JKL789012345678
    - Or archive if not needed

  ✗ prod_MNO901234567890 (Legacy Pro)

    Missing required metadata: tier

    Resolution:
    - Update metadata: bin/ots billing products update prod_MNO901234567890 --tier single_team

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌  VALIDATION FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2 product(s) have incomplete metadata.

See details: bin/ots billing products --invalid
```

## Technical Implementation

### 1. Enhanced Product Status Detection

```ruby
# In prices_validate_command.rb
def fetch_products_map
  # Fetch BOTH active AND archived products to distinguish states
  active = Stripe::Product.list({ active: true, limit: 100 }).auto_paging_each.to_a
  archived = Stripe::Product.list({ active: false, limit: 100 }).auto_paging_each.to_a

  {
    active: active.to_h { |p| [p.id, p] },
    archived: archived.to_h { |p| [p.id, p] }
  }
end

def validate_price(price, products_maps, errors, warnings)
  product = products_maps[:active][price.product]

  unless product
    # Check if archived
    archived_product = products_maps[:archived][price.product]
    if archived_product
      errors << {
        price_id: price.id,
        type: :archived_product,
        message: "Attached to archived product",
        details: "Product #{price.product} is archived and cannot be used for new subscriptions.",
        resolution: [
          "Create new active product if needed",
          "Archive this price if no longer needed",
          "See: https://dashboard.stripe.com/prices/#{price.id}"
        ]
      }
    else
      errors << {
        price_id: price.id,
        type: :missing_product,
        message: "Product not found",
        details: "Product #{price.product} does not exist in Stripe.",
        resolution: ["Verify product ID", "This price may need to be archived"]
      }
    end
    return
  end

  # ... rest of validation
end
```

### 2. Consistent Status Indicators

```ruby
# Shared module: apps/web/billing/cli/validation_helpers.rb
module ValidationHelpers
  STATUS_VALID = '✓ Valid'
  STATUS_WARNING = '⚠ Warning'
  STATUS_ERROR = '✗ Invalid'
  STATUS_UNUSABLE = '✗ Unusable'
  STATUS_INCOMPLETE = '⚠ Incomplete'
  STATUS_READY = '✓ Ready'
  STATUS_NOT_READY = '✗ Not Ready'

  def status_for_price(price, errors, warnings)
    price_errors = errors.select { |e| e[:price_id] == price.id }
    price_warnings = warnings.select { |w| w[:price_id] == price.id }

    return STATUS_UNUSABLE if price_errors.any? { |e| e[:type] == :archived_product }
    return STATUS_ERROR if price_errors.any?
    return STATUS_WARNING if price_warnings.any?
    STATUS_VALID
  end
end
```

### 3. Structured Error/Warning Format

```ruby
# Error structure
{
  price_id: 'price_1SWaFKH54PcLeqtYrxz3QnGS',  # Full ID
  type: :archived_product,  # Symbol for categorization
  message: 'Attached to archived product',  # Short message
  details: 'Product prod_ABC123 is archived...',  # Full explanation
  resolution: [  # Actionable steps
    'Create new active product if needed',
    'Archive this price if no longer needed',
    'See: https://dashboard.stripe.com/prices/price_1SWaFKH54PcLeqtYrxz3QnGS'
  ]
}
```

### 4. Full Price IDs in Table

```ruby
# Change from:
puts format('%-15s ...', price.id[0..13])

# To (with smart truncation if needed):
PRICE_ID_WIDTH = 29  # Full Stripe price ID length

def format_price_id(price_id, max_width = PRICE_ID_WIDTH)
  if price_id.length <= max_width
    price_id.ljust(max_width)
  else
    # Truncate with ellipsis if somehow longer
    "#{price_id[0..(max_width-4)]}..."
  end
end

puts format('%-29s ...', format_price_id(price.id))
```

### 5. Organized Output Sections

```ruby
def print_validation_results(errors, warnings, strict)
  # Summary section
  print_summary_section(errors, warnings)
  puts

  # Table section
  print_table_section
  puts

  # Issues section (errors + warnings)
  if errors.any?
    print_errors_section(errors)
    puts
  end

  if warnings.any?
    print_warnings_section(warnings)
    puts
  end

  # Final status
  print_final_status(errors, warnings, strict)
end

def print_errors_section(errors)
  puts '━' * 80
  puts "ERRORS (#{errors.size})"
  puts '━' * 80
  puts

  errors.each do |error|
    puts "  ✗ #{error[:price_id]}: #{error[:message]}"
    puts
    puts "    #{error[:details]}"
    puts
    if error[:resolution]
      puts "    Resolution:"
      error[:resolution].each { |step| puts "    - #{step}" }
    end
    puts
  end
end
```

### 6. Product Name Display for Archived Products

```ruby
def product_display_name(price, products_maps)
  product = products_maps[:active][price.product]
  return product.name if product

  archived = products_maps[:archived][price.product]
  return "(Archived Product)" if archived

  "(Unknown Product)"
end
```

## Column Width Standards

### prices validate
```
PRICE ID: 29 chars (full Stripe ID)
PRODUCT: 20 chars (truncate with ...)
AMOUNT: 12 chars (USD 123.00)
INTERVAL: 8 chars (month/year)
STATUS: 15 chars (✓ Valid, ✗ Unusable)
```

### plans validate
```
PRODUCT ID: 22 chars (full Stripe ID)
PLAN ID: 20 chars (truncate with ...)
REGION: 7 chars (US/CA/EU/global)
PRICES: 16 chars (2 (month, year))
STATUS: 15 chars (✓ Ready, ✗ Not Ready)
```

### products validate
```
PRODUCT ID: 22 chars (full Stripe ID)
NAME: 20 chars (truncate with ...)
PLAN ID: 20 chars (truncate with ...)
REGION: 7 chars (US/CA/EU/global)
PRICES: 7 chars (N)
STATUS: 15 chars (✓ Valid, ✗ Incomplete)
```

## Exit Code Standards

```ruby
EXIT_SUCCESS = 0
EXIT_VALIDATION_FAILED = 1

# Exit logic:
if errors.any?
  exit EXIT_VALIDATION_FAILED
elsif warnings.any? && strict
  exit EXIT_VALIDATION_FAILED
else
  exit EXIT_SUCCESS
end
```

## Error Message Catalog

### Archived Product (Critical)
```
✗ price_XXX: Attached to archived product

Product prod_YYY is archived and cannot be used for new subscriptions.

Resolution:
- Create new active product if needed
- Archive this price if no longer needed
- See: https://dashboard.stripe.com/prices/price_XXX
```

### Missing Product (Critical)
```
✗ price_XXX: Product not found

Product prod_YYY does not exist in Stripe.

Resolution:
- Verify product ID is correct
- This price may need to be archived
```

### Zero Amount (Critical)
```
✗ price_XXX: Invalid price configuration

Price amount is $0.00 (use free tier product instead of zero-price).

Resolution:
- Use proper free tier product for $0 plans
- Archive this price
```

### Missing Recurring Prices (Critical)
```
✗ prod_XXX (plan_id_YYY): No recurring prices

Product has 0 recurring prices and cannot be used for subscriptions.

Resolution:
- Create monthly and yearly prices
- Or archive product if no longer offered
```

### Missing Metadata (Critical)
```
✗ prod_XXX: Missing required metadata

Required metadata field 'tier' is missing.

Resolution:
- Update product metadata: bin/ots billing products update prod_XXX --tier single_user
```

### Missing Yearly Price (Warning)
```
⚠ prod_XXX (plan_id_YYY): Missing yearly price

Product only has monthly pricing. Annual pricing is recommended for better LTV.
```

### Pricing Inconsistency (Warning)
```
⚠ price_XXX: Pricing consistency issue

Yearly price $290.00 is not 10-12x monthly price $29.00.
Consider adjusting for typical SaaS discount pattern.
```

### Duplicate Prices (Warning)
```
⚠ prod_XXX (plan_id_YYY): Duplicate interval pricing

2 duplicate monthly USD prices found.
Consider archiving extras to avoid confusion.
```

## Testing Requirements

### Unit Tests
```ruby
# Test price ID display
it 'shows full price ID in table' do
  expect(output).to include('price_1SWaFKH54PcLeqtYrxz3QnGS')
  expect(output).not_to include('price_1SWaFKH5')
end

# Test archived product detection
it 'identifies archived products' do
  expect(output).to include('Attached to archived product')
  expect(output).to include('(Archived Product)')
end

# Test status placement
it 'shows final status at end' do
  lines = output.split("\n")
  status_line = lines.find { |l| l.include?('VALIDATION FAILED') }
  expect(lines.index(status_line)).to be > lines.length - 5
end
```

### Integration Tests
```ruby
# Test with real Stripe test mode data
it 'handles archived products correctly' do
  # Setup: create product, create price, archive product
  # Verify: price shows as unusable with helpful message
end

# Test error grouping
it 'groups errors by price ID' do
  # Verify multiple errors for same price are grouped
end
```

## Migration Plan

### Phase 1: Shared Helpers
1. Create `apps/web/billing/cli/validation_helpers.rb`
2. Define standard constants and helper methods
3. Include in all three validation commands

### Phase 2: prices validate
1. Update to fetch both active and archived products
2. Implement new error structure
3. Update output format with summary section
4. Add full price IDs to table
5. Update tests

### Phase 3: plans validate
1. Apply new output format
2. Update error messages with resolution steps
3. Add summary section
4. Update tests

### Phase 4: products validate
1. Add price counts to main table (not just valid section)
2. Apply new output format
3. Update error messages
4. Update tests

### Phase 5: Documentation
1. Update CLI help text
2. Update billing documentation
3. Add examples to docs/billing/README.md

## Success Metrics

- Users can correlate errors with table rows (full price IDs)
- Archived product errors are clear and actionable
- Validation status appears at end (standard CLI pattern)
- Price counts visible in products output
- Consistent status indicators across all commands
- All error messages include resolution steps
- Exit codes properly reflect validation state

## References

- Stripe Dashboard UX patterns: https://dashboard.stripe.com/prices
- CLI best practices: https://clig.dev/
- OneTimeSecret billing docs: docs/billing/
- Stripe API versioning: 2024-12-18
