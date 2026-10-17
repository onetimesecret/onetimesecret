# try/unit/models/features/guarded_config_writes_try.rb
#
# frozen_string_literal: true

# Onetime::Models::Features::GuardedConfigWrites: create, update and delete
# of a per-domain config record, atomic against a concurrent writer of the
# same record. Exercised through SignupConfig.
#
# The concurrent writer runs in a fiber with empty storage, so it checks out
# its own pool connection instead of the one the guarded method pinned for
# WATCH (a write on that connection would not abort its own transaction).
#
# Run: try --agent try/unit/models/features/guarded_config_writes_try.rb

require_relative '../../../support/test_models'

OT.boot! :test

@klass  = Onetime::CustomDomain::SignupConfig
@ts     = "#{Familia.now.to_i}_#{SecureRandom.hex(4)}"
@ids    = []
@domain = lambda do |name|
  id = "guarded_#{name}_#{@ts}"
  @ids << id
  id
end
@concurrently = ->(&block) { Fiber.new(storage: {}, &block).resume }
@write        = lambda do |domain_id, **fields|
  @concurrently.call do
    other = @klass.load(domain_id)
    fields.each { |name, value| other.public_send(:"#{name}=", value) }
    other.commit_fields
  end
end

## The pool exists, so the guarded methods pin a connection
!Onetime::Runtime.infrastructure.database_pool.nil?
#=> true

## update_for_domain! commits what the block assigns and returns the record and the block's value
@d_update = @domain.call('update')
@klass.create!(domain_id: @d_update)
config, value = @klass.update_for_domain!(@d_update) do |stored|
  stored.signup_enabled = true
  :assigned
end
[config.signup_enabled?, value, @klass.find_by_domain_id(@d_update).signup_enabled?]
#=> [true, :assigned, true]

## A write between the read and the commit makes it read again: neither write is lost
@d_retry = @domain.call('retry')
@klass.create!(domain_id: @d_retry)
reads = 0
_, seen = @klass.update_for_domain!(@d_retry) do |stored|
  reads += 1
  @write.call(@d_retry, autoverify: true) if reads == 1
  stored.signup_enabled = true
  stored.autoverify?
end
stored = @klass.find_by_domain_id(@d_retry)
[reads, seen, stored.signup_enabled?, stored.autoverify?]
#=> [2, true, true, true]

## A record still changing after three attempts raises and keeps the other writer's state
@d_busy = @domain.call('busy')
@klass.create!(domain_id: @d_busy)
attempts = 0
outcome = begin
  @klass.update_for_domain!(@d_busy) do |stored|
    attempts += 1
    @write.call(@d_busy, autoverify: attempts.odd?)
    stored.signup_enabled = true
  end
  :committed
rescue Familia::OptimisticLockError
  :refused
end
[outcome, attempts, @klass.find_by_domain_id(@d_busy).signup_enabled?]
#=> [:refused, 3, false]

## A missing record raises KeyNotFoundError and creates nothing
@d_missing = @domain.call('missing')
outcome = begin
  @klass.update_for_domain!(@d_missing) { |stored| stored.signup_enabled = true }
  :committed
rescue Familia::KeyNotFoundError
  :refused
end
[outcome, @klass.exists_for_domain?(@d_missing)]
#=> [:refused, false]

## A block that raises writes nothing, and the connection is clean for the next write
@d_raise = @domain.call('raise')
@klass.create!(domain_id: @d_raise)
begin
  @klass.update_for_domain!(@d_raise) do |stored|
    stored.signup_enabled = true
    raise ArgumentError, 'refused by the caller'
  end
rescue ArgumentError
  nil
end
_, = @klass.update_for_domain!(@d_raise) { |stored| stored.autoverify = true }
stored = @klass.find_by_domain_id(@d_raise)
[stored.signup_enabled?, stored.autoverify?]
#=> [false, true]

## remove_for_domain! returns the record as deleted; a second call finds nothing
@d_remove = @domain.call('remove')
@klass.create!(domain_id: @d_remove, validation_strategy: 'mx')
removed = @klass.remove_for_domain!(@d_remove)
[removed.validation_strategy, @klass.remove_for_domain!(@d_remove), @klass.exists_for_domain?(@d_remove)]
#=> ['mx', nil, false]

## delete_for_domain! keeps its boolean contract
@d_delete = @domain.call('delete')
@klass.create!(domain_id: @d_delete)
[@klass.delete_for_domain!(@d_delete), @klass.delete_for_domain!(@d_delete), @klass.delete_for_domain!('')]
#=> [true, false, false]

## create! for an existing record raises ConfigExistsError, an Onetime::Problem, with the old message
@d_exists = @domain.call('exists')
@klass.create!(domain_id: @d_exists)
begin
  @klass.create!(domain_id: @d_exists)
rescue Onetime::Problem => ex
  [ex.class.name.split('::').last, ex.message]
end
#=> ['ConfigExistsError', 'Signup config already exists for this domain']

## save_new_config! refuses a record created after the caller's check
@d_race = @domain.call('race')
fresh = @klass.new(domain_id: @d_race, validation_strategy: 'passthrough')
@concurrently.call { @klass.create!(domain_id: @d_race, validation_strategy: 'mx') }
begin
  @klass.save_new_config!(fresh, 'taken')
  :saved
rescue Onetime::Models::Features::GuardedConfigWrites::ConfigExistsError => ex
  [ex.message, @klass.find_by_domain_id(@d_race).validation_strategy]
end
#=> ['taken', 'mx']

## upsert_for_domain! turns a lost create into an update of the record that won
@d_upsert = @domain.call('upsert')
build = lambda do
  @concurrently.call { @klass.create!(domain_id: @d_upsert, validation_strategy: 'mx') }
  @klass.new(domain_id: @d_upsert, validation_strategy: 'passthrough')
end
upserted = @klass.upsert_for_domain!(@d_upsert, 'taken', build: build) { |stored| stored.signup_enabled = true }
stored   = @klass.find_by_domain_id(@d_upsert)
[upserted.signup_enabled?, stored.validation_strategy, stored.signup_enabled?]
#=> [true, 'mx', true]

# Teardown
@ids.each { |id| @klass.delete_for_domain!(id) }
