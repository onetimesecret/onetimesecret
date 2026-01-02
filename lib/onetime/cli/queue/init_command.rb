# lib/onetime/cli/queue/init_command.rb
#
# frozen_string_literal: true

#
# CLI command for initializing RabbitMQ vhost and infrastructure
#
# Creates the vhost specified in RABBITMQ_URL and sets up permissions.
# Also declares exchanges and queues.
#
# Usage:
#   ots queue init [options]
#
# Options:
#   -f, --force       Skip confirmation prompt
#   --dry-run         Show what would be created without doing it
#
# Prerequisites:
#   - RabbitMQ Management API must be enabled (rabbitmq-plugins enable rabbitmq_management)
#   - RABBITMQ_MANAGEMENT_URL env var (default: http://localhost:15672)
#   - Management user credentials (default: guest:guest)
#

require 'bunny'
require 'net/http'
require 'json'
require 'uri'
require_relative '../../jobs/queue_config'

module Onetime
  module CLI
    module Queue
      class InitCommand < Command
        desc 'Initialize RabbitMQ vhost, exchanges, and queues'

        option :force, type: :boolean, default: false, aliases: ['f'],
          desc: 'Skip confirmation prompt'
        option :dry_run, type: :boolean, default: false,
          desc: 'Show what would be created without doing it'

        def call(force: false, dry_run: false, **)
          boot_application!

          amqp_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
          parsed   = parse_amqp_url(amqp_url)

          puts "RabbitMQ Initialization"
          puts "=" * 60
          puts
          puts "AMQP URL: #{amqp_url.gsub(/:[^:@]+@/, ':***@')}"
          puts "VHost: #{parsed[:vhost]}"
          puts "User: #{parsed[:user]}"
          puts

          if dry_run
            puts "[DRY RUN] Would perform the following:"
            puts "  1. Create vhost '#{parsed[:vhost]}' (if not exists)"
            puts "  2. Set permissions for user '#{parsed[:user]}' on vhost '#{parsed[:vhost]}'"
            puts "  3. Declare exchanges and queues"
            return
          end

          unless force
            print "Continue? [y/N] "
            response = $stdin.gets&.strip&.downcase
            unless response == 'y'
              puts "Aborted."
              return
            end
          end

          # Step 1: Create vhost via Management API
          create_vhost(parsed)

          # Step 2: Set permissions
          set_permissions(parsed)

          # Step 3: Declare exchanges and queues via AMQP
          declare_infrastructure(amqp_url)

          puts
          puts "Initialization complete."
        end

        private

        def parse_amqp_url(url)
          uri      = URI.parse(url)
          raw_path = uri.path&.sub(%r{^/}, '')
          vhost    = raw_path.nil? || raw_path.empty? ? '/' : raw_path
          {
            host: uri.host || 'localhost',
            port: uri.port || 5672,
            user: uri.user || 'guest',
            password: uri.password || 'guest',
            vhost: vhost,
            scheme: uri.scheme || 'amqp',
          }
        end

        def management_url
          ENV.fetch('RABBITMQ_MANAGEMENT_URL', 'http://localhost:15672')
        end

        def management_credentials
          # Try to get from RABBITMQ_URL first, fall back to defaults
          amqp_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
          parsed   = parse_amqp_url(amqp_url)
          [parsed[:user], parsed[:password]]
        end

        def create_vhost(parsed)
          vhost = parsed[:vhost]
          return if vhost == '/' # Default vhost always exists

          puts "Creating vhost '#{vhost}'..."

          uri      = URI.parse("#{management_url}/api/vhosts/#{URI.encode_www_form_component(vhost)}")
          user, pw = management_credentials

          http             = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl     = uri.scheme == 'https'
          http.open_timeout = 5
          http.read_timeout = 10

          request                  = Net::HTTP::Put.new(uri.path)
          request.basic_auth(user, pw)
          request['Content-Type'] = 'application/json'
          request.body             = '{}'

          response = http.request(request)

          case response.code.to_i
          when 201
            puts "  Created vhost '#{vhost}'"
          when 204
            puts "  Vhost '#{vhost}' already exists"
          else
            puts "  Failed to create vhost: #{response.code} #{response.message}"
            puts "  #{response.body}" if response.body && !response.body.empty?
            exit 1
          end
        rescue Errno::ECONNREFUSED
          puts "  ERROR: Cannot connect to RabbitMQ Management API at #{management_url}"
          puts "  Ensure rabbitmq_management plugin is enabled:"
          puts "    rabbitmq-plugins enable rabbitmq_management"
          puts
          puts "  Or create vhost manually with rabbitmqctl:"
          puts "    rabbitmqctl add_vhost #{vhost}"
          puts "    rabbitmqctl set_permissions -p #{vhost} #{parsed[:user]} \".*\" \".*\" \".*\""
          exit 1
        rescue StandardError => ex
          puts "  ERROR: #{ex.message}"
          exit 1
        end

        def set_permissions(parsed)
          vhost = parsed[:vhost]
          user  = parsed[:user]

          puts "Setting permissions for '#{user}' on vhost '#{vhost}'..."

          uri          = URI.parse("#{management_url}/api/permissions/#{URI.encode_www_form_component(vhost)}/#{URI.encode_www_form_component(user)}")
          admin, pw    = management_credentials

          http             = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl     = uri.scheme == 'https'
          http.open_timeout = 5
          http.read_timeout = 10

          request                  = Net::HTTP::Put.new(uri.path)
          request.basic_auth(admin, pw)
          request['Content-Type'] = 'application/json'
          request.body             = JSON.generate({
            configure: '.*',
            write: '.*',
            read: '.*',
          })

          response = http.request(request)

          case response.code.to_i
          when 201, 204
            puts "  Permissions set for '#{user}'"
          else
            puts "  Failed to set permissions: #{response.code} #{response.message}"
            puts "  #{response.body}" if response.body && !response.body.empty?
            exit 1
          end
        rescue StandardError => ex
          puts "  ERROR: #{ex.message}"
          exit 1
        end

        def declare_infrastructure(amqp_url)
          puts "Declaring exchanges and queues..."

          bunny_config = {
            logger: Onetime.get_logger('Bunny'),
          }
          bunny_config.merge!(Onetime::Jobs::QueueConfig.tls_options(amqp_url))

          conn = Bunny.new(amqp_url, **bunny_config)
          conn.start
          channel = conn.create_channel

          # Declare exchanges
          Onetime::Initializers::SetupRabbitMQ.declare_exchanges(channel)
          puts "  Exchanges declared"

          # Declare queues
          Onetime::Initializers::SetupRabbitMQ.declare_queues(channel)
          puts "  Queues declared"

          channel.close
          conn.close
        rescue Bunny::TCPConnectionFailed => ex
          puts "  ERROR: Cannot connect to RabbitMQ: #{ex.message}"
          exit 1
        rescue StandardError => ex
          puts "  ERROR: #{ex.message}"
          exit 1
        end
      end
    end

    register 'queue init', Queue::InitCommand
    register 'queues init', Queue::InitCommand  # Alias
  end
end
