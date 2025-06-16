# etc/init.d/experimental.rb

# Remove nil elements that have inadvertently been set in
# the list of previously used global secrets. Happens easily
# when using environment vars in the config.yaml that aren't
# set or are set to an empty string.
rotated_secrets = config['experimental']['rotated_secrets'] ||= []

# Convert empty strings to nil
rotated_secrets.map! { |secret| secret == "" ? nil : secret }
rotated_secrets.compact!

config['experimental']['rotated_secrets'] = rotated_secrets
