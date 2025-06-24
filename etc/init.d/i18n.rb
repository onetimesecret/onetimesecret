# etc/init.d/i18n.rb

config['enabled'] ||= false

config['locales'] ||= ['en']

config['default_locale'] ||= config['locales'].first

config['fallback_locale'] ||= nil
