# lib/tasks/dev.rake
#
# frozen_string_literal: true

# First-session seed data for contributors (install-onboarding D6).
#
# `bin/dev` gets you a running instance; this gets you something to log in
# with and something to look at. Creates a pre-verified dev account with a
# known password (web signup requires email verification, which needs SMTP —
# CLI-provisioned accounts skip that) plus a couple of sample secrets, and
# prints the credentials.
#
# Idempotent: an existing account is left untouched (password NOT reset);
# sample secrets are only seeded when the account has no receipts yet.
#
#   bundle exec rake dev:seed
#   EMAIL=me@example.com PASSWORD=hunter2! bundle exec rake dev:seed

namespace :dev do
  desc 'Seed a dev account + sample secrets, print credentials (EMAIL=, PASSWORD=)'
  task :seed do
    rack_env = ENV['RACK_ENV'] || 'development'
    unless %w[development dev].include?(rack_env)
      abort "dev:seed only runs in development (RACK_ENV=#{rack_env}) — it creates an account with a known password"
    end

    email    = ENV['EMAIL'] || 'dev@example.com'
    password = ENV['PASSWORD'] || 'devpassword'

    require 'onetime'
    require 'onetime/models'

    begin
      Onetime.boot! :cli
    rescue StandardError => ex
      abort "dev:seed: boot failed (#{ex.class}: #{ex.message})\n" \
            'Is the datastore running? Start it with `bin/dev` or `pnpm run database:start`.'
    end

    created = false
    unless Onetime::Customer.email_exists?(email)
      # bin/ots apitoken owns account provisioning for BOTH auth modes
      # (simple = Redis-only, full = Redis + Rodauth SQL) — delegate rather
      # than duplicating the full-mode path here.
      system('bin/ots', 'apitoken', email, '--create', '--password', password, exception: true)
      created = true
    end

    cust = Onetime::Customer.find_by_email(email)
    abort 'dev:seed: could not load customer after creation' unless cust

    seeded = []
    if cust.receipts.empty?
      samples = [
        ['Welcome to your local Onetime Secret! This sample secret self-destructs after one viewing.',
         7 * 24 * 3600],
        ["Seeded by `rake dev:seed` on #{Time.now.utc.strftime('%Y-%m-%d')}. " \
         'Burn this one from the dashboard to see the burn flow.',
         3 * 24 * 3600],
      ]
      samples.each do |content, lifespan|
        receipt, secret = Onetime::Receipt.spawn_pair(cust.objid, lifespan, content)
        cust.add_receipt receipt
        cust.increment_field :secrets_created
        Onetime::Customer.secrets_created.increment
        seeded << secret
      end
    end

    host   = Onetime.conf&.dig('site', 'host') || 'localhost:3000'
    scheme = Onetime.conf&.dig('site', 'ssl') ? 'https' : 'http'
    base   = "#{scheme}://#{host}"

    puts
    puts 'Dev account ready'
    puts "  Email:    #{email}"
    puts(created ? "  Password: #{password}" : '  Password: (existing account — unchanged)')
    puts "  Sign in:  #{base}/signin"
    puts
    if seeded.any?
      puts 'Sample secrets (also on the dashboard after sign-in):'
      seeded.each { |secret| puts "  #{base}/secret/#{secret.objid}" }
    else
      puts 'Sample secrets: account already has receipts — skipped'
    end
  end
end
