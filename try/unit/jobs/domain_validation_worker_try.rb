# try/unit/jobs/domain_validation_worker_try.rb
#
# frozen_string_literal: true

# Tests for domain validation background job infrastructure
#
# Validates:
# 1. Queue configuration matches QueueConfig
# 2. DLX/DLQ configuration
# 3. QueueDeclarator integration
# 4. Publisher convenience method exists
# 5. Sync fallback when jobs are disabled

require_relative '../../support/test_helpers'
require 'securerandom'

OT.boot! :test

require 'onetime/jobs/queues/config'
require 'onetime/jobs/queues/declarator'
require 'onetime/jobs/publisher'
require 'onetime/operations/validate_sender_domain'
require 'onetime/models/custom_domain/mailer_config'

@sneakers_opts = Onetime::Jobs::QueueDeclarator.sneakers_options_for('domain.validation.check')

@timestamp = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "dvw_owner_#{@timestamp}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("DVW Test Org #{@timestamp}", @owner, "dvw_#{@timestamp}@test.com")
@domain = Onetime::CustomDomain.create!("dvw-test-#{@timestamp}.example.com", @org.objid)

@config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier,
  provider: 'ses',
  from_name: 'Test Sender',
  from_address: "noreply@dvw-test-#{@timestamp}.example.com",
)

## Queue 'domain.validation.check' exists in QueueConfig
Onetime::Jobs::QueueConfig::QUEUES.key?('domain.validation.check')
#=> true

## Queue is durable
Onetime::Jobs::QueueConfig::QUEUES['domain.validation.check'][:durable]
#=> true

## Queue is not auto_delete
Onetime::Jobs::QueueConfig::QUEUES['domain.validation.check'][:auto_delete]
#=> false

## Queue has dead letter exchange configured
Onetime::Jobs::QueueConfig::QUEUES['domain.validation.check'][:arguments]['x-dead-letter-exchange']
#=> 'dlx.domain.validation'

## DLX exists in DEAD_LETTER_CONFIG
Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.key?('dlx.domain.validation')
#=> true

## DLQ name follows convention
Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG['dlx.domain.validation'][:queue]
#=> 'dlq.domain.validation'

## QueueDeclarator returns sneakers options with ack: true
@sneakers_opts[:ack]
#=> true

## Sneakers queue_options durable matches QueueConfig
@sneakers_opts[:queue_options][:durable]
#=> true

## Sneakers queue_options auto_delete matches QueueConfig
@sneakers_opts[:queue_options][:auto_delete]
#=> false

## Publisher responds to enqueue_domain_validation class method
Onetime::Jobs::Publisher.respond_to?(:enqueue_domain_validation)
#=> true

## Publisher instance responds to enqueue_domain_validation
Onetime::Jobs::Publisher.new.respond_to?(:enqueue_domain_validation)
#=> true

## Sync fallback returns true when jobs disabled (no $rmq_channel_pool)
@pub_result = Onetime::Jobs::Publisher.enqueue_domain_validation(@domain.identifier)
@pub_result
#=> true

## Sync fallback executes validation synchronously (status updated from pending)
@reloaded = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
%w[verified failed].include?(@reloaded.verification_status)
#=> true

# Teardown
Familia.dbclient.flushdb
