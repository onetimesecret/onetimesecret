# frozen_string_literal: true

# spec/support/puma_integration/fork_workflow_rack_app.rb
#
# Minimal Rack application for testing Puma fork workflow.
# Exposes workflow state and initializer info via JSON endpoints.
#
# Usage: Called from the generated rackup file in puma_fork_registry_workflow_spec.rb

require 'json'

module PumaIntegration
  # Creates a Rack app that exposes fork workflow test endpoints.
  #
  # @param fork_sensitive_initializers [Array] List of fork-sensitive initializers from registry
  # @return [Proc] Rack application
  def self.build_workflow_app(fork_sensitive_initializers)
    fork_sensitive = fork_sensitive_initializers

    proc do |env|
      case env['PATH_INFO']
      when '/health'
        [200, { 'content-type' => 'text/plain' }, ['OK']]

      when '/pid'
        [200, { 'content-type' => 'text/plain' }, [Process.pid.to_s]]

      when '/workflow'
        status = {
          pid: Process.pid,
          boot_pids: $workflow_state[:boot_pids].uniq,
          cleanup_pids: $workflow_state[:cleanup_pids].uniq,
          reconnect_pids: $workflow_state[:reconnect_pids].uniq,
          cleanup_order: $workflow_state[:initializers_order][:cleanup],
          reconnect_order: $workflow_state[:initializers_order][:reconnect],
          cleanup_errors: $workflow_state[:errors][:cleanup],
          reconnect_errors: $workflow_state[:errors][:reconnect],
          fork_sensitive_count: fork_sensitive.size
        }
        [200, { 'content-type' => 'application/json' }, [status.to_json]]

      when '/initializers'
        data = {
          count: fork_sensitive.size,
          names: fork_sensitive.map(&:name),
          phases: fork_sensitive.map { |i| [i.name, i.phase] }.to_h
        }
        [200, { 'content-type' => 'application/json' }, [data.to_json]]

      else
        [404, { 'content-type' => 'text/plain' }, ['Not Found']]
      end
    end
  end
end
