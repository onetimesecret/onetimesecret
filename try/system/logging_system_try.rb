# try/system/logging_system_try.rb
#
# Tryouts for the structured logging system with strategic categories.
# Tests SemanticLogger integration, backward compatibility, and the Logging module.

require_relative '../support/test_helpers'
require 'semantic_logger'

# Initialize SemanticLogger for tests
SemanticLogger.default_level = :info
SemanticLogger.add_appender(io: $stdout, formatter: :color) unless SemanticLogger.appenders.any?

OT.boot! :test, true

# Onetime Logging System Tests
#
# Tests for the structured logging system with strategic categories.
# Categories: Auth, Session, HTTP, Familia, Otto, Rhales, Secret, App

## Configuration Loading - Config file exists
File.exist?(File.join(Dir.pwd, 'etc', 'logging.yaml'))
#=> true

## Configuration Loading - Config file structure
config = YAML.load_file(File.join(Dir.pwd, 'etc', 'logging.yaml'))
config.key?('default_level')
#=> true

## Configuration Loading - Loggers configuration exists
config = YAML.load_file(File.join(Dir.pwd, 'etc', 'logging.yaml'))
config.key?('loggers')
#=> true

## Configuration Loading - Auth logger configured
config = YAML.load_file(File.join(Dir.pwd, 'etc', 'logging.yaml'))
config['loggers'].key?('Auth')
#=> true

## Configuration Loading - HTTP config exists
config = YAML.load_file(File.join(Dir.pwd, 'etc', 'logging.yaml'))
config.key?('http')
#=> true

## SemanticLogger Integration - Auth logger exists
SemanticLogger['Auth']
#=:> SemanticLogger::Logger

## SemanticLogger Integration - Session logger exists
SemanticLogger['Session']
#=:> SemanticLogger::Logger

## SemanticLogger Integration - HTTP logger exists
SemanticLogger['HTTP']
#=:> SemanticLogger::Logger

## SemanticLogger Integration - Familia logger exists
SemanticLogger['Familia']
#=:> SemanticLogger::Logger

## SemanticLogger Integration - Otto logger exists
SemanticLogger['Otto']
#=:> SemanticLogger::Logger

## SemanticLogger Integration - Rhales logger exists
SemanticLogger['Rhales']
#=:> SemanticLogger::Logger

## SemanticLogger Integration - Secret logger exists
SemanticLogger['Secret']
#=:> SemanticLogger::Logger

## SemanticLogger Integration - App logger exists (default)
SemanticLogger['App']
#=:> SemanticLogger::Logger

## Logging Module - Include in test class
class TestLoggingClass
  include Onetime::Logging
end
test_instance = TestLoggingClass.new
test_instance.respond_to?(:logger)
#=> true

## Logging Module - Auth logger accessor
test_instance = TestLoggingClass.new
test_instance.auth_logger
#=:> SemanticLogger::Logger

## Logging Module - Session logger accessor
test_instance = TestLoggingClass.new
test_instance.session_logger
#=:> SemanticLogger::Logger

## Logging Module - HTTP logger accessor
test_instance = TestLoggingClass.new
test_instance.http_logger
#=:> SemanticLogger::Logger

## Logging Module - Secret logger accessor
test_instance = TestLoggingClass.new
test_instance.secret_logger
#=:> SemanticLogger::Logger

## Logging Module - App logger accessor (default)
test_instance = TestLoggingClass.new
test_instance.app_logger
#=:> SemanticLogger::Logger

## Category Inference - Auth pattern detection
class TestAuthClass
  include Onetime::Logging
end
test_auth = TestAuthClass.new
test_auth.send(:infer_category)
#=> "Auth"

## Category Inference - Session pattern detection
class TestSessionClass
  include Onetime::Logging
end
test_session = TestSessionClass.new
test_session.send(:infer_category)
#=> "Session"

## Category Inference - Secret pattern detection
class TestSecretClass
  include Onetime::Logging
end
test_secret = TestSecretClass.new
test_secret.send(:infer_category)
#=> "Secret"

## Category Inference - HTTP/Controller pattern detection
class TestController
  include Onetime::Logging
end
test_controller = TestController.new
test_controller.send(:infer_category)
#=> "HTTP"

## Category Inference - Default fallback
class TestRandomClass
  include Onetime::Logging
end
test_random = TestRandomClass.new
test_random.send(:infer_category)
#=> "App"

## Thread-Local Category - Set and use custom category
test_instance = TestLoggingClass.new
Thread.current[:log_category] = 'Auth'
category = Thread.current[:log_category]
Thread.current[:log_category] = nil
category
#=> "Auth"

## Thread-Local Category - with_log_category helper
test_instance = TestLoggingClass.new
result = nil
test_instance.with_log_category('Session') do
  result = Thread.current[:log_category]
end
result
#=> "Session"

## Thread-Local Category - Cleanup after with_log_category
test_instance = TestLoggingClass.new
Thread.current[:log_category] = 'Initial'
test_instance.with_log_category('Temporary') do
  # Inside block
end
Thread.current[:log_category]
#=> "Initial"

## Structured Logging - li with payload (uses SemanticLogger)
class TestStructuredLogging
  include Onetime::Logging
  def test_li_structured
    # Capture would require SemanticLogger appender configuration
    # For now, verify the method accepts keyword arguments
    Onetime.li "Test", user_id: 123
    true
  end
end
TestStructuredLogging.new.test_li_structured
#=> true

## Structured Logging - le with payload (uses SemanticLogger)
class TestStructuredLogging
  include Onetime::Logging
  def test_le_structured
    Onetime.le "Error", code: 500
    true
  end
end
TestStructuredLogging.new.test_le_structured
#=> true

## Structured Logging - lw with payload (uses SemanticLogger)
class TestStructuredLogging
  include Onetime::Logging
  def test_lw_structured
    Onetime.lw "Warning", threshold: 100
    true
  end
end
TestStructuredLogging.new.test_lw_structured
#=> true

## Structured Logging - ld with payload (uses SemanticLogger)
ENV['ONETIME_DEBUG'] = '1'
class TestStructuredLogging
  include Onetime::Logging
  def test_ld_structured
    Onetime.ld "Debug", step: 1
    true
  end
end
result = TestStructuredLogging.new.test_ld_structured
ENV['ONETIME_DEBUG'] = nil
result
#=> true

## Logger Method - Returns SemanticLogger instance
class TestLoggerMethod
  include Onetime::Logging
end
test_logger = TestLoggerMethod.new.logger
test_logger
#=:> SemanticLogger::Logger

## Logger Method - Respects thread-local category
class TestLoggerMethod
  include Onetime::Logging
end
test_instance = TestLoggerMethod.new
Thread.current[:log_category] = 'Secret'
logger_name = test_instance.logger.name.to_s
Thread.current[:log_category] = nil
logger_name
#=> "Secret"

## Configuration Loading - Config path from Onetime.conf
site_path = Onetime.conf.dig(:site, :path) || Dir.pwd
config_path = File.join(site_path, 'etc', 'logging.yaml')
File.exist?(config_path)
#=> true

## Configuration Loading - Config loads successfully
site_path = Onetime.conf.dig(:site, :path) || Dir.pwd
config = YAML.load_file(File.join(site_path, 'etc', 'logging.yaml'))
!config.nil?
#=> true

## Configuration Loading - Config has required keys
site_path = Onetime.conf.dig(:site, :path) || Dir.pwd
config = YAML.load_file(File.join(site_path, 'etc', 'logging.yaml'))
config.key?('default_level') && config.key?('loggers') && config.key?('http')
#=> true

## Configuration Loading - Auth logger is configured
site_path = Onetime.conf.dig(:site, :path) || Dir.pwd
config = YAML.load_file(File.join(site_path, 'etc', 'logging.yaml'))
config['loggers'].key?('Auth')
#=> true
