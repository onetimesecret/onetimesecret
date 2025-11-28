# tests/unit/ruby/try/12_indifferent_hash_try.rb
# frozen_string_literal: true

require_relative '../../../../lib/onetime/indifferent_hash'
require 'yaml'

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

@simple_hash = Onetime::IndifferentHash.deep_convert({
  site: { host: 'example.com', ssl: true },
  emailer: { from: 'test@example.com', port: 587 }
})

@nested_hash = Onetime::IndifferentHash.deep_convert({
  site: {
    authentication: {
      enabled: true,
      colonels: ['admin@example.com']
    },
    secret_options: {
      ttl_options: [3600, 7200, 86400],
      default_ttl: 3600
    }
  }
})

@hash_with_arrays = Onetime::IndifferentHash.deep_convert({
  items: [{ name: 'one', value: 1 }, { name: 'two', value: 2 }],
  tags: ['alpha', 'beta']
})

# -----------------------------------------------------------------------------
# Basic Type Checks
# -----------------------------------------------------------------------------

## Creates IndifferentHash from nested hash
@simple_hash.class
#=> Onetime::IndifferentHash

## Nested hash is also IndifferentHash
@simple_hash[:site].class
#=> Onetime::IndifferentHash

## Deeply nested hash is IndifferentHash
@nested_hash[:site][:authentication].class
#=> Onetime::IndifferentHash

# -----------------------------------------------------------------------------
# Symbol Key Access
# -----------------------------------------------------------------------------

## Symbol key access works for top level
@simple_hash[:site].nil?
#=> false

## Symbol key access works for nested keys
@simple_hash[:site][:host]
#=> 'example.com'

## Symbol key access works for boolean values
@simple_hash[:site][:ssl]
#=> true

## Symbol key access works for numeric values
@simple_hash[:emailer][:port]
#=> 587

# -----------------------------------------------------------------------------
# String Key Access
# -----------------------------------------------------------------------------

## String key access works for top level
@simple_hash['site'].nil?
#=> false

## String key access works for nested keys
@simple_hash['site']['host']
#=> 'example.com'

## String key access works for boolean values
@simple_hash['site']['ssl']
#=> true

## String key access works for numeric values
@simple_hash['emailer']['port']
#=> 587

# -----------------------------------------------------------------------------
# Mixed Key Access
# -----------------------------------------------------------------------------

## Mixed keys work: symbol then string
@simple_hash[:site]['host']
#=> 'example.com'

## Mixed keys work: string then symbol
@simple_hash['site'][:host]
#=> 'example.com'

## Both access patterns return identical values
@simple_hash[:site][:host] == @simple_hash['site']['host']
#=> true

# -----------------------------------------------------------------------------
# dig Method
# -----------------------------------------------------------------------------

## dig with all symbols works
@simple_hash.dig(:site, :host)
#=> 'example.com'

## dig with all strings works
@simple_hash.dig('site', 'host')
#=> 'example.com'

## dig with mixed keys works (symbol, string)
@simple_hash.dig(:site, 'host')
#=> 'example.com'

## dig with mixed keys works (string, symbol)
@simple_hash.dig('site', :host)
#=> 'example.com'

## dig returns nil for missing keys
@simple_hash.dig(:missing, :key)
#=> nil

## dig returns nil for partially missing path
@simple_hash.dig(:site, :missing)
#=> nil

## dig works with deeply nested paths
@nested_hash.dig(:site, :authentication, :enabled)
#=> true

## dig works with array values in nested hash
@nested_hash.dig(:site, :authentication, :colonels)
#=> ['admin@example.com']

## dig works with array of integers
@nested_hash.dig(:site, :secret_options, :ttl_options)
#=> [3600, 7200, 86400]

# -----------------------------------------------------------------------------
# fetch Method
# -----------------------------------------------------------------------------

## fetch with symbol key works
@simple_hash.fetch(:site).class
#=> Onetime::IndifferentHash

## fetch with string key works
@simple_hash.fetch('site').class
#=> Onetime::IndifferentHash

## fetch returns same value for symbol and string
@simple_hash.fetch(:site)[:host] == @simple_hash.fetch('site')['host']
#=> true

## fetch with default for missing key
@simple_hash.fetch(:missing, 'default_value')
#=> 'default_value'

## fetch with empty hash default
@simple_hash.fetch(:missing, {})
#=> {}

## fetch with block for missing key
@simple_hash.fetch(:missing) { 'from_block' }
#=> 'from_block'

## chained fetch works
@simple_hash.fetch(:site, {}).fetch(:host, nil)
#=> 'example.com'

# -----------------------------------------------------------------------------
# key? / has_key? / include? Methods
# -----------------------------------------------------------------------------

## key? with symbol returns true for existing key
@simple_hash.key?(:site)
#=> true

## key? with string returns true for existing key
@simple_hash.key?('site')
#=> true

## key? returns false for missing key
@simple_hash.key?(:missing)
#=> false

## has_key? is aliased to key?
@simple_hash.has_key?(:site)
#=> true

## include? is aliased to key?
@simple_hash.include?('emailer')
#=> true

## member? is aliased to key?
@simple_hash.member?(:site)
#=> true

# -----------------------------------------------------------------------------
# Assignment
# -----------------------------------------------------------------------------

## Assignment with symbol key stores as string internally
hash = Onetime::IndifferentHash.deep_convert({})
hash[:new_key] = 'value'
hash.keys
#=> ['new_key']

## Assigned value accessible via symbol
hash = Onetime::IndifferentHash.deep_convert({})
hash[:test] = 'hello'
hash[:test]
#=> 'hello'

## Assigned value accessible via string
hash = Onetime::IndifferentHash.deep_convert({})
hash[:test] = 'hello'
hash['test']
#=> 'hello'

## Assignment with string key works
hash = Onetime::IndifferentHash.deep_convert({})
hash['string_key'] = 'string_value'
hash[:string_key]
#=> 'string_value'

# -----------------------------------------------------------------------------
# delete Method
# -----------------------------------------------------------------------------

## delete with symbol key removes the key
hash = Onetime::IndifferentHash.deep_convert({ remove_me: 'value' })
hash.delete(:remove_me)
hash.key?(:remove_me)
#=> false

## delete with string key removes the key
hash = Onetime::IndifferentHash.deep_convert({ remove_me: 'value' })
hash.delete('remove_me')
hash.key?('remove_me')
#=> false

## delete returns the removed value
hash = Onetime::IndifferentHash.deep_convert({ key: 'the_value' })
hash.delete(:key)
#=> 'the_value'

# -----------------------------------------------------------------------------
# merge Method
# -----------------------------------------------------------------------------

## merge returns IndifferentHash
merged = @simple_hash.merge({ new: 'data' })
merged.class
#=> Onetime::IndifferentHash

## merge does not modify original
original_keys = @simple_hash.keys.sort
@simple_hash.merge({ new: 'data' })
@simple_hash.keys.sort == original_keys
#=> true

## merged hash has new keys accessible by symbol
merged = @simple_hash.merge({ added: 'value' })
merged[:added]
#=> 'value'

## merged hash has new keys accessible by string
merged = @simple_hash.merge({ added: 'value' })
merged['added']
#=> 'value'

## merge! modifies in place
hash = Onetime::IndifferentHash.deep_convert({ original: 'data' })
hash.merge!({ added: 'new' })
hash[:added]
#=> 'new'

# -----------------------------------------------------------------------------
# slice Method
# -----------------------------------------------------------------------------

## slice with symbol keys works
sliced = @simple_hash.slice(:site)
sliced.keys
#=> ['site']

## slice with string keys works
sliced = @simple_hash.slice('emailer')
sliced.keys
#=> ['emailer']

## slice with mixed keys works
sliced = @simple_hash.slice(:site, 'emailer')
sliced.keys.sort
#=> ['emailer', 'site']

## slice returns IndifferentHash
@simple_hash.slice(:site).class
#=> Onetime::IndifferentHash

## sliced values are accessible
@simple_hash.slice(:site)[:site][:host]
#=> 'example.com'

# -----------------------------------------------------------------------------
# except Method
# -----------------------------------------------------------------------------

## except removes specified keys (symbol)
result = @simple_hash.except(:emailer)
result.key?(:emailer)
#=> false

## except removes specified keys (string)
result = @simple_hash.except('emailer')
result.key?('emailer')
#=> false

## except keeps other keys
result = @simple_hash.except(:emailer)
result.key?(:site)
#=> true

## except returns IndifferentHash
@simple_hash.except(:site).class
#=> Onetime::IndifferentHash

## except does not modify original
@simple_hash.except(:site, :emailer)
@simple_hash.key?(:site)
#=> true

# -----------------------------------------------------------------------------
# values_at Method
# -----------------------------------------------------------------------------

## values_at with symbol keys
values = @simple_hash.values_at(:site, :emailer)
values.length
#=> 2

## values_at with string keys
values = @simple_hash.values_at('site', 'emailer')
values.first.class
#=> Onetime::IndifferentHash

## values_at with mixed keys
values = @simple_hash.values_at(:site, 'emailer')
values.all? { |v| v.is_a?(Onetime::IndifferentHash) }
#=> true

# -----------------------------------------------------------------------------
# dup Method
# -----------------------------------------------------------------------------

## dup returns IndifferentHash
@simple_hash.dup.class
#=> Onetime::IndifferentHash

## dup creates independent copy
duped = @simple_hash.dup
duped[:site][:host] = 'changed.com'
@simple_hash[:site][:host]
#=> 'example.com'

## duped nested hashes are also IndifferentHash
@simple_hash.dup[:site].class
#=> Onetime::IndifferentHash

# -----------------------------------------------------------------------------
# Array Handling
# -----------------------------------------------------------------------------

## Arrays are preserved in conversion
@hash_with_arrays[:tags]
#=> ['alpha', 'beta']

## Arrays of hashes have IndifferentHash elements
@hash_with_arrays[:items].first.class
#=> Onetime::IndifferentHash

## Array hash elements accessible via symbol
@hash_with_arrays[:items].first[:name]
#=> 'one'

## Array hash elements accessible via string
@hash_with_arrays[:items].first['name']
#=> 'one'

## Array hash elements support dig
@hash_with_arrays[:items].last.dig(:value)
#=> 2

# -----------------------------------------------------------------------------
# Edge Cases
# -----------------------------------------------------------------------------

## nil values are preserved
hash = Onetime::IndifferentHash.deep_convert({ key: nil })
hash[:key]
#=> nil

## false values are preserved (not treated as nil)
hash = Onetime::IndifferentHash.deep_convert({ enabled: false })
hash[:enabled]
#=> false

## empty hash conversion works
hash = Onetime::IndifferentHash.deep_convert({})
hash.class
#=> Onetime::IndifferentHash

## empty nested hash works
hash = Onetime::IndifferentHash.deep_convert({ empty: {} })
hash[:empty].class
#=> Onetime::IndifferentHash

## numeric string keys work
hash = Onetime::IndifferentHash.deep_convert({ '123' => 'numeric_key' })
hash['123']
#=> 'numeric_key'

## to_h returns regular Hash data
@simple_hash.to_h.class
#=> Hash

# -----------------------------------------------------------------------------
# YAML Serialization (Critical for deep_clone compatibility)
# -----------------------------------------------------------------------------

## YAML.dump outputs plain Hash format (no !ruby/hash:Onetime::IndifferentHash tag)
yaml_output = YAML.dump(@simple_hash)
yaml_output.include?('IndifferentHash')
#=> false

## YAML round-trip works without Psych::DisallowedClass error
begin
  yaml_str = YAML.dump(@simple_hash)
  loaded = YAML.load(yaml_str)
  loaded['site']['host']
rescue Psych::DisallowedClass => e
  "ERROR: #{e.message}"
end
#=> 'example.com'

## YAML.safe_load works after dump (no class tag to reject)
begin
  yaml_str = YAML.dump(@simple_hash)
  loaded = YAML.safe_load(yaml_str, permitted_classes: [Symbol])
  loaded['site']['host']
rescue Psych::DisallowedClass => e
  "ERROR: #{e.message}"
end
#=> 'example.com'

## Nested IndifferentHash also serializes as plain Hash
nested = Onetime::IndifferentHash.deep_convert({ a: { b: { c: 'deep' } } })
yaml_str = YAML.dump(nested)
yaml_str.include?('IndifferentHash')
#=> false
