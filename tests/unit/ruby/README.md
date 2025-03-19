# Ruby Test Documentation

## Running Tests

### Tryouts

Navigate to the project root directory to ensure correct lib path resolution.

```bash
bundle exec try -v tests/unit/ruby/try/10_utils_try.rb
bundle exec try -v tests/unit/ruby/try/**/*_try.rb
```

### RSpec

Execute RSpec tests from project root:

```bash
bundle exec rspec tests/unit/ruby/rspec/**/*_spec.rb
bundle exec rspec tests/unit/ruby/rspec/onetime/config_spec.rb --format documentation
COVERAGE=1 bundle exec rspec tests/unit/ruby/rspec/**/*_spec.rb
```

Key test configurations:
- SimpleCov coverage reporting enabled via COVERAGE env var
- Random test execution order
- Shared Rack test context for request specs
- Mocked logging in test environment
- Custom refinements for Hash operations

Test suite components:
- Config validation specs
- Rack refinements specs
- Utils module specs

Test files location: `tests/unit/ruby/rspec/`
Config file: `tests/unit/ruby/config.test.yaml`

## Examples


### Example tryout

In `./try/10_utils_try.rb`:

```ruby
# frozen_string_literal: true

# These tryouts test the functionality of the Onetime::Utils module.
# The Utils module provides various utility functions used throughout
# the Onetime application.
#
# We're testing various aspects of the Utils module, including:
# 1. Generation of random strands
# 2. Email address obfuscation
#
# These tests aim to ensure that the utility functions work correctly,
# which is crucial for various operations in the Onetime application,
# such as generating unique identifiers and protecting user privacy.
#
# The tryouts simulate different scenarios of using the Utils module
# without needing to run the full application, allowing for targeted
# testing of these specific functionalities.

require_relative '../../../../lib/onetime'

# Familia.debug = true

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '../../../../etc', 'config.test.yaml')
OT.boot!

## Create a strand
Onetime::Utils.strand.class
#=> String

## strand is 12 chars by default
Onetime::Utils.strand.size
#=> 12

## strand can be n chars
Onetime::Utils.strand(20).size
#=> 20

## Obscure email address (6 or more chars)
Onetime::Utils.obscure_email('tryouts@onetimesecret.com')
#=> 'tr*****@o*****.com'

## Obscure email address (4 or more chars)
Onetime::Utils.obscure_email('dave@onetimesecret.com')
#=> 'da*****@o*****.com'

## Obscure email address (less than 4 chars)
Onetime::Utils.obscure_email('dm@onetimesecret.com')
#=> 'dm*****@o*****.com'

## Obscure email address (single char)
Onetime::Utils.obscure_email('r@onetimesecret.com')
#=> 'r*****@o*****.com'

## Obscure email address (Long)
Onetime::Utils.obscure_email('readyreadyreadyready@onetimesecretonetimesecretonetimesecret.com')
#=> 're*****@o*****.com'
```
