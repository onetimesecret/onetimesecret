# try/system/logging_simple_try.rb
#
# frozen_string_literal: true

#
# Simple unit tests for the logging configuration without full boot.
# Tests YAML config file structure and basic module inclusion.

require 'yaml'

## Configuration File - Exists
File.exist?('etc/logging.yaml')
#=> true

## Configuration File - Valid YAML
config = YAML.load_file('etc/logging.yaml')
config.class
#=> Hash

## Configuration File - Has default_level
config = YAML.load_file('etc/logging.yaml')
config.key?('default_level')
#=> true

## Configuration File - default_level is string
config = YAML.load_file('etc/logging.yaml')
config['default_level'].class
#=> String

## Configuration File - Has loggers section
config = YAML.load_file('etc/logging.yaml')
config.key?('loggers')
#=> true

## Configuration File - Loggers is hash
config = YAML.load_file('etc/logging.yaml')
config['loggers'].class
#=> Hash

## Configuration File - Auth logger present
config = YAML.load_file('etc/logging.yaml')
config['loggers'].key?('Auth')
#=> true

## Configuration File - Session logger present
config = YAML.load_file('etc/logging.yaml')
config['loggers'].key?('Session')
#=> true

## Configuration File - HTTP logger present
config = YAML.load_file('etc/logging.yaml')
config['loggers'].key?('HTTP')
#=> true

## Configuration File - Familia logger present
config = YAML.load_file('etc/logging.yaml')
config['loggers'].key?('Familia')
#=> true

## Configuration File - Otto logger present
config = YAML.load_file('etc/logging.yaml')
config['loggers'].key?('Otto')
#=> true

## Configuration File - Rhales logger present
config = YAML.load_file('etc/logging.yaml')
config['loggers'].key?('Rhales')
#=> true

## Configuration File - Secret logger present
config = YAML.load_file('etc/logging.yaml')
config['loggers'].key?('Secret')
#=> true

## Configuration File - App logger present (default)
config = YAML.load_file('etc/logging.yaml')
config['loggers'].key?('App')
#=> true

## Configuration File - Has HTTP section
config = YAML.load_file('etc/logging.yaml')
config.key?('http')
#=> true

## Configuration File - HTTP config is hash
config = YAML.load_file('etc/logging.yaml')
config['http'].class
#=> Hash

## Configuration File - HTTP enabled flag exists
config = YAML.load_file('etc/logging.yaml')
config['http'].key?('enabled')
#=> true

## Configuration File - HTTP capture mode exists
config = YAML.load_file('etc/logging.yaml')
config['http'].key?('capture')
#=> true

## Configuration File - HTTP ignore_paths exists
config = YAML.load_file('etc/logging.yaml')
config['http'].key?('ignore_paths')
#=> true

## Logging Module File - Exists
File.exist?('lib/onetime/logger_methods.rb')
#=> true

## Logging Module File - Valid Ruby
system('ruby -c lib/onetime/logger_methods.rb > /dev/null 2>&1')
#=> true

## Migration Guide - Exists
File.exist?('docs/logging-migration-guide.md')
#=> true

## Migration Guide - Not empty
File.read('docs/logging-migration-guide.md').length > 100
#=> true
