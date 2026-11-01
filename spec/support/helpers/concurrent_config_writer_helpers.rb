# spec/support/helpers/concurrent_config_writer_helpers.rb
#
# frozen_string_literal: true

# Puts a second writer of a per-domain config record in the middle of a
# request, for the specs of the guarded config writes
# (Onetime::Models::Features::GuardedConfigWrites). Include it in an example
# group and install a hook before sending the request.
module ConcurrentConfigWriterHelpers
  # Runs the block the way a second request would: in a fiber with empty
  # storage, so it checks out its own pool connection instead of the one the
  # request pinned for WATCH. A write on the pinned connection would not
  # abort that connection's own transaction.
  def as_concurrent_writer(&)
    Fiber.new(storage: {}, &).resume
  end

  # Commits fields to the stored record as a concurrent writer.
  def write_config_concurrently(model, domain_id, **fields)
    as_concurrent_writer do
      other = model.load(domain_id)
      fields.each { |name, value| other.public_send(:"#{name}=", value) }
      other.commit_fields
    end
  end

  # Yields the loaded record (or nil) once, right after the request's first
  # find_by_domain_id on the model: the load in raise_concerns.
  def after_config_load(model)
    fired = false
    allow(model).to receive(:find_by_domain_id).and_wrap_original do |original, *args|
      original.call(*args).tap do |config|
        next if fired

        fired = true
        yield config
      end
    end
  end

  # Yields after each of the first +times+ reads update_for_domain! makes
  # under WATCH, before it commits. The yielded attempt number starts at 1.
  def after_watched_read(model, times:)
    allow(model).to receive(:update_for_domain!).and_wrap_original do |original, *args, &block|
      reads = 0
      original.call(*args) do |config|
        block.call(config).tap { yield reads if (reads += 1) <= times }
      end
    end
  end
end
