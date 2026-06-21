# try/system/logging_simple_try.rb
#
# frozen_string_literal: true

#
# Simple unit tests for the logging configuration without full boot.
# Tests the effective logging config: etc/defaults/logging.defaults.yaml
# deep-merged with the environment override found by ConfigResolver
# (spec/logging.test.yaml under RACK_ENV=test, etc/logging.yaml otherwise).
# This mirrors SetupLoggers#load_logging_config — no copied-into-place
# etc/logging.yaml is required to run these tests.

require 'erb'
require 'yaml'

require_relative '../../lib/onetime/utils/config_resolver'
require_relative '../../lib/onetime/utils/enumerables'

def load_effective_logging_config
  defaults_file = Onetime::Utils::ConfigResolver.defaults_path('logging')
  override_file = Onetime::Utils::ConfigResolver.resolve('logging')

  base_config = if defaults_file
    YAML.load(ERB.new(File.read(defaults_file)).result) || {}
  else
    {}
  end

  env_config = if override_file && override_file != defaults_file
    YAML.load(ERB.new(File.read(override_file)).result) || {}
  else
    {}
  end

  return base_config if env_config.empty?
  return env_config if base_config.empty?

  Onetime::Utils::Enumerables.deep_merge(base_config, env_config, preserve_nils: false)
end

## Configuration File - Resolves for this environment
config_path = Onetime::Utils::ConfigResolver.resolve('logging') ||
              Onetime::Utils::ConfigResolver.defaults_path('logging')
File.exist?(config_path)
#=> true

## Configuration File - Valid YAML
config = load_effective_logging_config
config.class
#=> Hash

## Configuration File - Has default_level
config = load_effective_logging_config
config.key?('default_level')
#=> true

## Configuration File - default_level is string
config = load_effective_logging_config
config['default_level'].class
#=> String

## Configuration File - Has loggers section
config = load_effective_logging_config
config.key?('loggers')
#=> true

## Configuration File - Loggers is hash
config = load_effective_logging_config
config['loggers'].class
#=> Hash

## Configuration File - Auth logger present
config = load_effective_logging_config
config['loggers'].key?('Auth')
#=> true

## Configuration File - Session logger present
config = load_effective_logging_config
config['loggers'].key?('Session')
#=> true

## Configuration File - HTTP logger present
config = load_effective_logging_config
config['loggers'].key?('HTTP')
#=> true

## Configuration File - Familia logger present
config = load_effective_logging_config
config['loggers'].key?('Familia')
#=> true

## Configuration File - Otto logger present
config = load_effective_logging_config
config['loggers'].key?('Otto')
#=> true

## Configuration File - Rhales logger present
config = load_effective_logging_config
config['loggers'].key?('Rhales')
#=> true

## Configuration File - Secret logger present
config = load_effective_logging_config
config['loggers'].key?('Secret')
#=> true

## Configuration File - App logger present (default)
config = load_effective_logging_config
config['loggers'].key?('App')
#=> true

## Configuration File - Has HTTP section
config = load_effective_logging_config
config.key?('http')
#=> true

## Configuration File - HTTP config is hash
config = load_effective_logging_config
config['http'].class
#=> Hash

## Configuration File - HTTP enabled flag exists
config = load_effective_logging_config
config['http'].key?('enabled')
#=> true

## Configuration File - HTTP capture mode exists
config = load_effective_logging_config
config['http'].key?('capture')
#=> true

## Configuration File - HTTP ignore_paths exists
config = load_effective_logging_config
config['http'].key?('ignore_paths')
#=> true

## Logging Module File - Exists
File.exist?('lib/onetime/logger_methods.rb')
#=> true

## Logging Module File - Valid Ruby
system('ruby -c lib/onetime/logger_methods.rb > /dev/null 2>&1')
#=> true
