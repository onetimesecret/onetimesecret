# spec/cli/queue/dlq_message_commands_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for the per-message DLQ verbs (#4343):
#
#   bin/ots queue dlq replay <queue> --id ID [--reason R]
#   bin/ots queue dlq discard <queue> --id ID [--dry-run] [--force] [--reason R]
#
# Pure adapter coverage: flag validation, the preview-then-prompt flow, the
# not_visible / refused / unconfirmed exits, and that the ops get the message
# id and reason. The ops (scan, transaction, audit) are covered by
# spec/unit/onetime/operations/dlq/{replay_message,discard}_spec.rb, so here
# they are stubbed at their constructors and the broker connection is a
# double (no RABBITMQ_URL needed).

require_relative '../cli_spec_helper'
require 'onetime/cli/queue/dlq_command'

RSpec.describe 'DLQ per-message commands', type: :cli do
  let(:dlq) { 'dlq.billing.event' }
  let(:message_id) { '6f1c2d3e-0000-4000-8000-00000000abcd' }
  let(:op_calls) { [] }
  let(:max_scan) { Onetime::Operations::Dlq::Store::MAX_SCAN }
  # The truncation hint reads the queue depth on a channel of its own.
  let(:depth_queue) { double('Bunny::Queue', message_count: 1200) }
  let(:depth_channel) { double('Bunny::Channel', queue: depth_queue, open?: true, close: nil) }

  before do
    allow(Bunny).to receive(:new)
      .and_return(double('Bunny::Session', start: nil, close: nil, create_channel: depth_channel))
  end

  def output_of(*args)
    run_cli_command_quietly(*args)
  end

  describe 'queue dlq replay --id' do
    def replay_result(status: :success, replayed: 1, failed: 0, errors: [], outcome: nil, scanned: 3, truncated: false)
      Onetime::Operations::Dlq::Replay::Result.new(
        status: status, queue: dlq, replayed: replayed, failed: failed, errors: errors, would_replay: 0,
        message_id: message_id, found: status != :not_visible, outcome: outcome, scanned: scanned, truncated: truncated,
      )
    end

    let(:result) { replay_result }

    before do
      allow(Onetime::Operations::Dlq::Replay).to receive(:new) do |args|
        op_calls << args
        instance_double(Onetime::Operations::Dlq::Replay, call: result)
      end
    end

    it 'replays the one message, passing the id and the reason' do
      output = output_of('queue', 'dlq', 'replay', 'billing.event', '--id', message_id, '--reason', 'customer waiting')

      expect(last_exit_code).to eq(0)
      expect(op_calls).to match([
        a_hash_including(queue: dlq, message_id: message_id, actor: 'cli', reason: 'customer waiting',
          max_scan: max_scan),
      ])
      expect(output[:stdout]).to include('Replayed: 1')
    end

    it 'passes a larger --max-scan to the op' do
      output_of('queue', 'dlq', 'replay', 'billing.event', '--id', message_id, '--max-scan', '5000')

      expect(op_calls).to match([a_hash_including(max_scan: 5000)])
    end

    it 'refuses a --max-scan that is not a positive integer' do
      output = output_of('queue', 'dlq', 'replay', 'billing.event', '--id', message_id, '--max-scan', '0')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: --max-scan must be a positive integer')
      expect(op_calls).to be_empty

      output = output_of('queue', 'dlq', 'replay', 'billing.event', '--id', message_id, '--max-scan', 'lots')
      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('--max-scan must be an integer')
    end

    it 'refuses --id together with --count before touching the broker' do
      output = output_of('queue', 'dlq', 'replay', 'billing.event', '--id', message_id, '--count', '2')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: --id and --count are exclusive')
      expect(op_calls).to be_empty
    end

    it 'exits 1 when the message is not visible, naming the scan' do
      not_visible = replay_result(status: :not_visible, replayed: 0, outcome: 'not_visible', scanned: 500, truncated: true)
      allow(Onetime::Operations::Dlq::Replay).to receive(:new)
        .and_return(instance_double(Onetime::Operations::Dlq::Replay, call: not_visible))

      output = output_of('queue', 'dlq', 'replay', 'billing.event', '--id', message_id)

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include(
        "Message not visible: #{message_id} (scanned 500 message(s), stopped at the scan limit)",
        'Scanned 500 of about 1200 message(s); the message may be deeper in the queue. Retry with --max-scan 1200.',
      )
    end

    it 'exits 1 with the reason when the email DLQ reservation refuses' do
      refused = replay_result(status: :refused, replayed: 0, outcome: 'already_replayed',
        errors: [{ message_id: message_id, error: 'Not republished: already sent' }])
      allow(Onetime::Operations::Dlq::Replay).to receive(:new)
        .and_return(instance_double(Onetime::Operations::Dlq::Replay, call: refused))

      output = output_of('queue', 'dlq', 'replay', 'email.message', '--id', message_id)

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Not replayed (already_replayed): Not republished: already sent')
    end

    it 'exits 1 when the replay failed' do
      failed = replay_result(replayed: 0, failed: 1, errors: [{ message_id: message_id, error: 'publish refused' }])
      allow(Onetime::Operations::Dlq::Replay).to receive(:new)
        .and_return(instance_double(Onetime::Operations::Dlq::Replay, call: failed))

      output = output_of('queue', 'dlq', 'replay', 'billing.event', '--id', message_id)

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Failed:   1', 'publish refused')
    end

    it 'keeps the bulk replay a bulk replay, now with the reason' do
      bulk = Onetime::Operations::Dlq::Replay::Result.new(
        status: :success, queue: dlq, replayed: 2, failed: 0, errors: [], would_replay: 0,
      )
      allow(Onetime::Operations::Dlq::Replay).to receive(:new) do |args|
        op_calls << args
        instance_double(Onetime::Operations::Dlq::Replay, call: bulk)
      end

      output_of('queue', 'dlq', 'replay', 'billing.event', '--reason', 'endpoint fixed')

      expect(op_calls.size).to eq(1)
      expect(op_calls.first).to include(queue: dlq, count: nil, actor: 'cli', reason: 'endpoint fixed')
      expect(op_calls.first).not_to have_key(:message_id)
    end
  end

  describe 'queue dlq show --id' do
    def show_result(found:, scanned:, truncated:)
      Onetime::Operations::Dlq::Show::Result.new(
        found: found, empty: false, message: found ? { message_id: message_id } : nil,
        scanned: scanned, truncated: truncated,
      )
    end

    def stub_show(result)
      allow(Onetime::Operations::Dlq::Show).to receive(:new) do |args|
        op_calls << args
        instance_double(Onetime::Operations::Dlq::Show, call: result)
      end
    end

    it 'adds a truncation hint to a miss that stopped at the scan limit' do
      stub_show(show_result(found: false, scanned: 500, truncated: true))

      output = output_of('queue', 'dlq', 'show', 'billing.event', '--id', message_id)

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include(
        "Message not found: #{message_id}",
        'Scanned 500 of about 1200 message(s); the message may be deeper in the queue. Retry with --max-scan 1200.',
      )
      expect(op_calls).to match([a_hash_including(message_id: message_id, max_scan: max_scan)])
    end

    it 'prints no hint when the scan reached the end of the queue' do
      stub_show(show_result(found: false, scanned: 12, truncated: false))

      output = output_of('queue', 'dlq', 'show', 'billing.event', '--id', message_id)

      expect(output[:stdout]).to include("Message not found: #{message_id}")
      expect(output[:stdout]).not_to include('may be deeper')
    end

    it 'scans deeper with --max-scan' do
      stub_show(show_result(found: true, scanned: 900, truncated: false))

      output_of('queue', 'dlq', 'show', 'billing.event', '--id', message_id, '--max-scan', '2000', '--format', 'json')

      expect(last_exit_code).to eq(0)
      expect(op_calls).to match([a_hash_including(max_scan: 2000)])
    end
  end

  describe 'queue dlq discard' do
    def discard_result(status:, found: true, outcome: nil, error: nil, scanned: 2, truncated: false)
      Onetime::Operations::Dlq::Discard::Result.new(
        status: status, queue: dlq, message_id: message_id, found: found, outcome: outcome,
        original_queue: found ? 'billing.event.process' : nil, scanned: scanned, truncated: truncated, error: error,
      )
    end

    let(:preview) { discard_result(status: :dry_run) }
    let(:applied) { discard_result(status: :success) }

    before do
      allow(Onetime::Operations::Dlq::Discard).to receive(:new) do |args|
        op_calls << args
        instance_double(Onetime::Operations::Dlq::Discard, call: args[:dry_run] ? preview : applied)
      end
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    it 'is registered under queue and queues' do
      output_of('queues', 'dlq', 'discard', 'billing.event', '--id', message_id, '--force')

      expect(last_exit_code).to eq(0)
      expect(op_calls.size).to eq(2)
    end

    it 'requires --id' do
      output = output_of('queue', 'dlq', 'discard', 'billing.event')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Error: Must specify --id')
      expect(op_calls).to be_empty
    end

    it 'finds the message first, prompts with its original queue, then drops it' do
      output = output_of('queue', 'dlq', 'discard', 'billing.event', '--id', message_id, '--reason', 'poison')

      expect(output[:stdout]).to include(
        "WARNING: This will permanently drop message #{message_id} from #{dlq} (original queue: billing.event.process)",
        "Discarded message #{message_id} from #{dlq}",
      )
      expect(op_calls).to match([
        a_hash_including(queue: dlq, message_id: message_id, actor: 'cli', dry_run: true, reason: 'poison',
          max_scan: max_scan),
        a_hash_including(queue: dlq, message_id: message_id, actor: 'cli', reason: 'poison', max_scan: max_scan),
      ])
      expect(op_calls.last).not_to have_key(:dry_run)
    end

    it 'drops nothing when the prompt is declined' do
      allow($stdin).to receive(:gets).and_return("n\n")

      output = output_of('queue', 'dlq', 'discard', 'billing.event', '--id', message_id)

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include('Aborted.')
      expect(op_calls.size).to eq(1)
    end

    it 'skips the prompt with --force' do
      output_of('queue', 'dlq', 'discard', 'billing.event', '--id', message_id, '--force')

      expect($stdin).not_to have_received(:gets)
      expect(op_calls.size).to eq(2)
    end

    it 'with --dry-run reports the message and drops nothing' do
      output = output_of('queue', 'dlq', 'discard', 'billing.event', '--id', message_id, '--dry-run')

      expect(last_exit_code).to eq(0)
      expect(output[:stdout]).to include(
        "Would discard message #{message_id} from #{dlq} (original queue: billing.event.process)",
      )
      expect(op_calls.map { |args| args[:dry_run] }).to eq([true])
      expect($stdin).not_to have_received(:gets)
    end

    it 'exits 1 without prompting when the preview does not see the message' do
      allow(Onetime::Operations::Dlq::Discard).to receive(:new) do |args|
        op_calls << args
        instance_double(Onetime::Operations::Dlq::Discard,
          call: discard_result(status: :not_visible, found: false, outcome: 'not_visible', scanned: 7))
      end

      output = output_of('queue', 'dlq', 'discard', 'billing.event', '--id', message_id)

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include("Message not visible: #{message_id} (scanned 7 message(s))")
      expect(output[:stdout]).not_to include('may be deeper')
      expect(op_calls.size).to eq(1)
      expect($stdin).not_to have_received(:gets)
    end

    it 'hints at --max-scan when the preview stopped at the scan limit, and passes it through' do
      allow(Onetime::Operations::Dlq::Discard).to receive(:new) do |args|
        op_calls << args
        instance_double(Onetime::Operations::Dlq::Discard,
          call: discard_result(status: :not_visible, found: false, outcome: 'not_visible', scanned: 800, truncated: true))
      end

      output = output_of('queue', 'dlq', 'discard', 'billing.event', '--id', message_id, '--max-scan', '800')

      expect(output[:stdout]).to include('Scanned 800 of about 1200 message(s)', 'Retry with --max-scan 1200.')
      expect(op_calls).to match([a_hash_including(dry_run: true, max_scan: 800)])
    end

    it 'exits 1 with the unknown-outcome text when the drop is not confirmed' do
      allow(Onetime::Operations::Dlq::Discard).to receive(:new) do |args|
        op_calls << args
        call = if args[:dry_run]
                 preview
               else
                 discard_result(status: :unconfirmed, outcome: 'unconfirmed', error: 'Discard outcome unknown: x')
               end
        instance_double(Onetime::Operations::Dlq::Discard, call: call)
      end

      output = output_of('queue', 'dlq', 'discard', 'billing.event', '--id', message_id, '--force')

      expect(last_exit_code).to eq(1)
      expect(output[:stdout]).to include('Discard outcome unknown: x')
    end

    it 'prints JSON with --format json' do
      output = output_of('queue', 'dlq', 'discard', 'billing.event', '--id', message_id, '--force', '--format', 'json')

      expect(JSON.parse(output[:stdout])).to eq(
        'queue' => dlq, 'message_id' => message_id, 'original_queue' => 'billing.event.process', 'discarded' => true,
      )
    end
  end
end
