# etc/init.d/mail.rb


unless config['validation'].key?('defaults')
  abort 'No Validation config found'
end

# NOTE: This does not work. Because we use redis as athe backend and because
# we use JSON schema validation and because we need common config conventions
# between Ruby code and Typescript code, all keys are stored as strings and
# all string-like values are stored as strings. So enforcing a Symbol for
# this field init the init scripts does not work. We can only do that in
# the mail validation provider.
# validation_type = config['validation']['defaults']['default_validation_type']
# config['validation']['defaults']['default_validation_type'] = validation_type.to_sym
