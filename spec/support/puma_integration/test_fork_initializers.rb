# spec/support/puma_integration/test_fork_initializers.rb
#
# frozen_string_literal: true

# Test initializer classes for Puma fork workflow integration tests.
# These simulate fork-sensitive initializers with cleanup/reconnect hooks.
#
# Usage: Loaded by the test Rack app in puma_fork_registry_workflow_spec.rb
#
# Requires $workflow_state to be defined before loading this file.

# Ensure workflow state is initialized
$workflow_state ||= {
  boot_pids: [],
  cleanup_pids: [],
  reconnect_pids: [],
  initializers_order: { cleanup: [], reconnect: [] },
  errors: { cleanup: [], reconnect: [] }
}

# Base fork-sensitive initializer with dependency chain: Init1 -> Init2 -> Init3
class TestForkInit1 < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  @provides = [:test_fork_1]
  @depends_on = []
  @optional = false

  def execute(context)
    puts "[preload] TestForkInit1 executed"
    $workflow_state[:boot_pids] << Process.pid
  end

  def cleanup
    puts "[cleanup] TestForkInit1.cleanup called (PID: #{Process.pid})"
    $workflow_state[:cleanup_pids] << Process.pid
    $workflow_state[:initializers_order][:cleanup] << :init1
  end

  def reconnect
    puts "[reconnect] TestForkInit1.reconnect called (PID: #{Process.pid})"
    $workflow_state[:reconnect_pids] << Process.pid
    $workflow_state[:initializers_order][:reconnect] << :init1
  end
end

class TestForkInit2 < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  @provides = [:test_fork_2]
  @depends_on = [:test_fork_1]
  @optional = false

  def execute(context)
    puts "[preload] TestForkInit2 executed"
  end

  def cleanup
    puts "[cleanup] TestForkInit2.cleanup called (PID: #{Process.pid})"
    $workflow_state[:initializers_order][:cleanup] << :init2
  end

  def reconnect
    puts "[reconnect] TestForkInit2.reconnect called (PID: #{Process.pid})"
    $workflow_state[:initializers_order][:reconnect] << :init2
  end
end

class TestForkInit3 < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  @provides = [:test_fork_3]
  @depends_on = [:test_fork_2]
  @optional = false

  def execute(context)
    puts "[preload] TestForkInit3 executed"
  end

  def cleanup
    puts "[cleanup] TestForkInit3.cleanup called (PID: #{Process.pid})"
    $workflow_state[:initializers_order][:cleanup] << :init3
  end

  def reconnect
    puts "[reconnect] TestForkInit3.reconnect called (PID: #{Process.pid})"
    $workflow_state[:initializers_order][:reconnect] << :init3
  end
end

# Initializers that fail to test degraded mode operation
class TestForkFailingCleanup < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  @provides = [:test_fork_failing_cleanup]
  @depends_on = []
  @optional = false

  def execute(context)
    puts "[preload] TestForkFailingCleanup executed"
  end

  def cleanup
    puts "[cleanup] TestForkFailingCleanup.cleanup - RAISING ERROR"
    $workflow_state[:errors][:cleanup] << :failing_cleanup
    raise StandardError, 'Cleanup failed intentionally'
  end

  def reconnect
    puts "[reconnect] TestForkFailingCleanup.reconnect called (PID: #{Process.pid})"
    $workflow_state[:initializers_order][:reconnect] << :failing_cleanup
  end
end

class TestForkFailingReconnect < Onetime::Boot::Initializer
  @phase = :fork_sensitive
  @provides = [:test_fork_failing_reconnect]
  @depends_on = []
  @optional = false

  def execute(context)
    puts "[preload] TestForkFailingReconnect executed"
  end

  def cleanup
    puts "[cleanup] TestForkFailingReconnect.cleanup called (PID: #{Process.pid})"
    $workflow_state[:initializers_order][:cleanup] << :failing_reconnect
  end

  def reconnect
    puts "[reconnect] TestForkFailingReconnect.reconnect - RAISING ERROR"
    $workflow_state[:errors][:reconnect] << :failing_reconnect
    raise StandardError, 'Reconnect failed intentionally'
  end
end
