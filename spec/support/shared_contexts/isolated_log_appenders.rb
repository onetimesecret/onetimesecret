# spec/support/shared_contexts/isolated_log_appenders.rb
#
# frozen_string_literal: true

# For examples that add and remove real SemanticLogger appenders.
#
# Every appender the process already has is set aside for the example and
# put back afterwards, together with SetupLoggers' record of the appenders
# it owns, the file sink's write-failure listeners and the log scrubber's
# registration. Each example starts from an empty appender list and leaves
# the suite's own logging as it found it, whether or not the run itself
# captures logs to a file (tests/lanes/run --capture-logs).
#
# Appenders the example added are removed, which closes them.
RSpec.shared_context 'with isolated log appenders' do
  around do |example|
    registry        = Onetime::Initializers::SetupLoggers.owned_appenders
    was_registered  = Onetime::LogScrubber.registered?
    saved_appenders = SemanticLogger.appenders.to_a
    saved_registry  = registry.dup
    listeners       = Onetime::Initializers::SetupLoggers::FileSink.write_failure_listeners
    saved_listeners = listeners.dup
    saved_appenders.each { |appender| SemanticLogger.appenders.delete(appender) }
    registry.clear
    listeners.clear
    example.run
  ensure
    SemanticLogger.appenders.to_a.each { |appender| SemanticLogger.remove_appender(appender) }
    saved_appenders.each { |appender| SemanticLogger.appenders << appender }
    registry.replace(saved_registry)
    listeners.replace(saved_listeners)
    SemanticLogger::Logger.subscribers&.delete(Onetime::LogScrubber) unless was_registered
  end
end
