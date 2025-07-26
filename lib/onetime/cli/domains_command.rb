# lib/onetime/cli/domains_command.rb

module Onetime
  class DomainsCommand < Drydock::Command
    def domains
      puts format('%d custom domains', V2::CustomDomain.values.size)
      return unless option.list

      literally_all_domain_ids = V2::CustomDomain.values.all
      all_domains              = literally_all_domain_ids.map do |did|
        V2::CustomDomain.from_identifier(did)
      end

      # Group domains by display_domain
      grouped_domains = all_domains.group_by(&:display_domain)

      grouped_domains.sort.each do |display_domain, domains|
        if domains.size == 1
          domain = domains.first
          puts format('%s %s', display_domain, domain.dbkey)
        else
          dbkeys         = domains.map(&:dbkey)
          dbkeys_display = if dbkeys.size > 3
                                "#{dbkeys[0..2].join(', ')}, ..."
                              else
                                dbkeys.join(', ')
                              end
          puts format('%4d  %s (%s)', domains.size, display_domain, dbkeys_display)
        end
      end
    end

    def revalidate_domains
      domains_to_process = get_domains_to_process
      return unless domains_to_process

      total = domains_to_process.size
      puts "Processing #{total} domain#{'s' unless total == 1}"

      process_domains_in_batches(domains_to_process)

      puts "\nRevalidation complete"
    end

    private

    def get_domains_to_process
      if option.domain && option.custid
        get_specific_domain
      elsif option.custid
        get_customer_domains
      elsif option.domain
        get_domains_by_name
      else
        V2::CustomDomain.all
      end
    end

    def get_specific_domain
        domain = V2::CustomDomain.load(option.domain, option.custid)
        [domain]
    rescue Onetime::RecordNotFound
        puts "Domain #{option.domain} not found for customer #{option.custid}"
        nil
    end

    def get_customer_domains
      customer = V2::Customer.load(option.custid)
      unless customer
        puts "Customer #{option.custid} not found"
        return nil
      end

      begin
        customer.custom_domains.members.map do |domain_name|
          V2::CustomDomain.load(domain_name, option.custid)
        end
      rescue Onetime::RecordNotFound
        puts "Customer #{option.custid} not found"
        nil
      end
    end

    def get_domains_by_name
      matching_domains = V2::CustomDomain.all.select do |domain|
        domain.display_domain == option.domain
      end

      if matching_domains.empty?
        puts "Domain #{option.domain} not found"
        nil
      else
        matching_domains
      end
    end

    def process_domains_in_batches(domains)
      batch_size       = 10
      throttle_seconds = 4

      domains.each_slice(batch_size).with_index do |batch, batch_idx|
        puts "\nProcessing batch #{batch_idx + 1}..."
        process_batch(batch)

        # Throttle between batches
        if batch_idx < (domains.size.to_f / batch_size).ceil - 1
          puts "\nWaiting #{throttle_seconds} seconds before next batch..."
          sleep throttle_seconds
        end
      end
    end

    def process_batch(batch)
      batch.each do |domain|
        print "Revalidating #{domain.display_domain}... "
        revalidate_domain(domain)
      end
      sleep 0.25 # maintain a sane maximum of 4 requests per second
    end

    def revalidate_domain(domain)
        params           = { domain: domain.display_domain }
        verifier         = V2::Logic::Domains::VerifyDomain.new(nil, domain.custid, params)
        verifier.raise_concerns
        verifier.process
        status           = domain.verification_state
        resolving_status = domain.resolving == 'true' ? 'resolving' : 'not resolving'
        puts "#{status} (#{resolving_status})"
    rescue StandardError => ex
        puts "error: #{ex.message}"
        warn ex.backtrace
    end
  end
end
