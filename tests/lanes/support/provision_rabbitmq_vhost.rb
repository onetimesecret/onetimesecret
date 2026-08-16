# tests/lanes/support/provision_rabbitmq_vhost.rb
#
# frozen_string_literal: true

# Ensures the per-worktree RabbitMQ vhost exists and grants the lane's user
# full rights on it, so concurrent lane runs in a worktree forest do not share
# queues, exchanges, or in-flight messages (#4168).
#
# Called by tests/lanes/run, once, before the lane's tasks exec — only for
# lanes that actually address the test broker, and only when the runner
# assigned a nonzero worktree index. Reads RABBITMQ_URL, whose vhost segment
# the runner has already rewritten to w<index>.
#
# WHY THE VHOST IS THE ONLY ISOLATION AVAILABLE
#
# AMQP scopes every queue and exchange name to the vhost named in
# Connection.Open, and that vhost comes from the URL alone. Two examples in
# spec/integration/all/jobs/rabbitmq_publishing_spec.rb delete, declare,
# publish to, and auto-ack-consume from 'email.message.send' and its DLQ/DLX —
# names hardcoded in lib/onetime/jobs/publisher.rb, so they cannot be salted
# per run the way the rest of that file's queues are. Separate vhosts is what
# keeps two lanes from eating each other's messages.
#
# WHY THERE IS NO LOCK, UNLIKE THE POSTGRESQL PROVISIONER
#
# provision_pg_database.rb holds an advisory lock because CREATE DATABASE
# followed by a multi-statement init script has an observable half-provisioned
# window: the database exists but carries no grants, and a loser that merely
# checked existence would hand its specs that database. There is no such
# window here. Both management-API calls are idempotent create-or-update PUTs
# (201 created / 204 already existed), so two runners starting together
# converge: whoever loses the vhost PUT gets 204, and the permissions PUT is
# last-write-wins with a byte-identical body. That only holds if BOTH PUTs run
# unconditionally on every invocation — short-circuiting on "vhost exists"
# would reintroduce exactly the window the lock exists to close, because the
# winner's permissions may not be set yet when the loser observes the vhost.
#
# WHY IT FAILS LOUD
#
# Three of the four live-AMQP spec files rescue StandardError in before(:all)
# and skip when the broker is unreachable — which a missing vhost also
# produces (a 530 surfaces as Bunny::NotAllowedError). A broken provisioner
# would therefore show up as ~21 quietly skipped examples, not as a red lane.
# Every failure path here exits 69 instead.

require 'json'
require 'net/http'
require 'uri'

module ProvisionRabbitmqVhost
  # The management API is published by compose.test.yml on the loopback port
  # that follows the file's own scheme ("21 + last two digits of the canonical
  # port", 15672 -> 2172). Hardcoded exactly as the rest of this tree
  # hardcodes 2163/2154/2156, and deliberately NOT read from
  # RABBITMQ_MANAGEMENT_URL: that name is scrubbed from every lane run and
  # must not become another keep-list entry.
  MANAGEMENT_URL = 'http://127.0.0.1:2172'

  # Mirrors provision_pg_database.rb's TEST_NAME guard. This script hands a
  # user full configure/write/read on whatever it is pointed at, so it refuses
  # anything that is not a runner-derived worktree vhost — '/' included.
  VHOST_NAME = /\Aw\d+\z/.freeze

  # The container may be up on 5672 before the management plugin is listening:
  # the compose health check probes AMQP only, and the runner's port preflight
  # probes 2156 only, so `up --wait` can return with 2172 still coming up.
  # Short and bounded — this is a just-started broker, not an outage.
  CONNECT_ATTEMPTS = 10
  CONNECT_BACKOFF  = 0.5

  class ProvisioningError < StandardError; end

  class << self
    def run(url)
      uri   = URI.parse(url)
      vhost = uri.path.to_s.delete_prefix('/')
      user  = uri.user && URI.decode_www_form_component(uri.user)
      pass  = uri.password && URI.decode_www_form_component(uri.password)

      unless vhost.match?(VHOST_NAME)
        abort "[lane:rabbitmq] refusing to provision non-worktree vhost #{vhost.inspect}"
      end
      abort '[lane:rabbitmq] RABBITMQ_URL carries no credentials; cannot provision' if user.nil?

      created = put(
        "/api/vhosts/#{URI.encode_www_form_component(vhost)}",
        '{}',
        user,
        pass,
        retry_connect: true,
      )
      put(
        "/api/permissions/#{URI.encode_www_form_component(vhost)}/#{URI.encode_www_form_component(user)}",
        JSON.generate({ configure: '.*', write: '.*', read: '.*' }),
        user,
        pass,
      )

      warn "[lane:rabbitmq] provisioned vhost #{vhost}" if created
    end

    private

    # One idempotent PUT. Returns true when the resource was created (201),
    # false when it already existed (204) — the same two codes
    # lib/onetime/cli/queue/init_command.rb:121-126,172-174 treats as success
    # for these exact endpoints.
    def put(path, body, user, pass, retry_connect: false)
      uri = URI.parse("#{MANAGEMENT_URL}#{path}")

      request                 = Net::HTTP::Put.new(uri.path)
      request.basic_auth(user, pass)
      request['Content-Type'] = 'application/json'
      request.body            = body

      response = request!(uri, request, retry_connect)

      case response.code.to_i
      when 201 then true
      when 204 then false
      else
        detail = response.body.to_s.empty? ? '' : " — #{response.body.strip}"
        raise ProvisioningError,
          "PUT #{path} returned #{response.code} #{response.message}#{detail}"
      end
    end

    def request!(uri, request, retry_connect)
      remaining = retry_connect ? CONNECT_ATTEMPTS : 1
      begin
        remaining        -= 1
        http              = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = 10
        http.request(request)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError, SocketError, Timeout::Error => ex
        if remaining.positive?
          sleep CONNECT_BACKOFF
          retry
        end
        raise ProvisioningError, <<~MSG.strip
          cannot reach the management API at #{MANAGEMENT_URL} (#{ex.class}: #{ex.message})
          The rabbitmq_management plugin and its published port arrived with #4168; a
          container started before that needs recreating:
            docker compose -f compose.test.yml up -d --force-recreate rabbitmq
        MSG
      end
    end
  end
end

url = ENV['RABBITMQ_URL'].to_s
if url.empty?
  warn '[lane:rabbitmq] RABBITMQ_URL is unset; cannot provision'
  exit 69
end

begin
  ProvisionRabbitmqVhost.run(url)
rescue ProvisionRabbitmqVhost::ProvisioningError => ex
  warn "[lane:rabbitmq] provisioning failed: #{ex.message}"
  exit 69
end
