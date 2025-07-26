# etc/init.d/mail.rb


unless config['validation'].key?('defaults')
  abort 'No Validation config found'
end

# NOTE: Key normalization to symbols has been moved to the configure_truemail
# service. Any symbol keys set in these init scripts are auto-normalized back
# to strings.
# validation_type = config['validation']['defaults']['default_validation_type']
# config['validation']['defaults']['default_validation_type'] = validation_type.to_sym
