# TrueMail Configuration Fix

## Issue

In the file `lib/onetime/config.rb`, the `after_load` method is attempting to configure TrueMail using the settings from the configuration file. When an invalid configuration key is encountered, the code logs an error but then still attempts to set the value on the TrueMail configuration object, causing a NoMethodError.

The specific error encountered during testing:

```
Failures:
  1) Onetime TrueMail configuration Truemail integration in Config.after_load logs error when Truemail config key does not exist
     Failure/Error: config.send("#{actual_key}=", value)
       #<Double "TruemailConfig"> received unexpected message :invalid_key= with ("value")
```

## Current Implementation

The current implementation in `lib/onetime/config.rb` is:

```ruby
mtc.each do |key, value|
  actual_key = mapped_key(key)
  unless config.respond_to?("#{actual_key}=")
    OT.le "config.#{actual_key} does not exist"
  end
  OT.ld "Setting Truemail config key #{key} to #{value}"
  config.send("#{actual_key}=", value)
end
```

This code:
1. Iterates through each key/value in the TrueMail config
2. Maps the key to the actual TrueMail API key name
3. Checks if the configuration object responds to the setter method
4. Logs an error if the setter doesn't exist
5. Attempts to set the value regardless of whether the check passed

## Solution

The solution is to only call the setter method if the configuration object responds to it:

```ruby
mtc.each do |key, value|
  actual_key = mapped_key(key)
  if config.respond_to?("#{actual_key}=")
    OT.ld "Setting Truemail config key #{key} to #{value}"
    config.send("#{actual_key}=", value)
  else
    OT.le "config.#{actual_key} does not exist"
  end
end
```

This change:
1. Only attempts to set values for valid configuration keys
2. Still logs errors for invalid keys
3. Prevents NoMethodError exceptions when invalid configuration is provided

## Testing

The test that verifies this behavior now passes because it:
1. Creates a configuration with an invalid key
2. Mocks the TrueMail configuration object to return false for `respond_to?(:invalid_key=)`
3. Expects an error to be logged
4. No longer expects the setter method to be called
