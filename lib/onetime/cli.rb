require 'drydock'
require 'onetime'
require 'familia/tools'

class OT::CLI < Drydock::Command
  def init
    OT.boot! :cli
  end

  def move_keys
    sourcedb, targetdb, filter = *argv
    raise 'No target database supplied' unless sourcedb && targetdb
    raise 'No filter supplied' unless filter

    source_uri = URI.parse Familia.uri.to_s
    target_uri = URI.parse Familia.uri.to_s
    source_uri.db = sourcedb
    target_uri.db = targetdb
    Familia::Tools.move_keys filter, source_uri, target_uri do |idx, type, key, ttl|
      if global.verbose > 0
        puts "#{idx + 1.to_s.rjust(4)} (#{type.to_s.rjust(6)}, #{ttl.to_s.rjust(4)}): #{key}"
      else
        print "\rMoved #{idx + 1} keys"
      end
    end
    puts
  end

  def customers
    puts '%d customers' % OT::Customer.values.size
    if option.list
      all_customers = OT::Customer.values.all.map do |custid|
        OT::Customer.load(custid)
      end

      # Choose the field to group by
      field = option.check_email ? :email : :custid

      # Group customers by the domain portion of the email address
      grouped_customers = all_customers.group_by do |cust|
        next if cust.nil?
        email = cust.send(field).to_s
        domain = email.split('@')[1] || 'unknown'
        domain
      end

      # Sort the grouped customers by domain
      grouped_customers.sort_by { |_, customers| customers.size }.each do |domain, customers|
        puts "#{domain} #{customers.size}"
      end

    elsif option.check
      all_customers = OT::Customer.values.all.map do |custid|
        OT::Customer.load(custid)
      end

      mismatched_customers = all_customers.select do |cust|
        next if cust.nil?
        custid_email = cust.custid.to_s
        email_field = cust.email.to_s
        custid_email != email_field
      end
      if mismatched_customers.empty?
        puts "All customers have matching custid and email fields."
      end

      mismatched_customers.each do |cust|
        obscured_custid = OT::Utils.obscure_email(cust.custid)
        obscured_email = OT::Utils.obscure_email(cust.email)
        puts "CustID and email mismatch: CustID: #{obscured_custid}, Email: #{obscured_email}"
      end
    end
  end

  def domains
    puts '%d custom domains' % OT::CustomDomain.values.size
    if option.list
      literally_all_domain_ids = OT::CustomDomain.values.all
      all_domains = literally_all_domain_ids.map do |did|
        OT::CustomDomain.from_identifier(did)
      end

      # Group domains by display_domain
      grouped_domains = all_domains.group_by(&:display_domain)

      grouped_domains.sort.each do |display_domain, domains|
        if domains.size == 1
          domain = domains.first
          puts '%s %s' % [display_domain, domain.rediskey]
        else
          rediskeys = domains.map(&:rediskey)
          rediskeys_display = if rediskeys.size > 3
                                "#{rediskeys[0..2].join(', ')}, ..."
                              else
                                rediskeys.join(', ')
                              end
          puts '%4d  %s (%s)' % [domains.size, display_domain, rediskeys_display]
        end
      end
    end
  end

  def revalidate_domains
    batch_size = 10  # Process 10 domains at a time
    throttle_seconds = 4  # wait (in seconds) between batches

    domains_to_process = if option.domain && option.custid
      # Specific domain for a customer
      begin
        domain = OT::CustomDomain.load(option.domain, option.custid)
        [domain]
      rescue OT::RecordNotFound
        puts "Domain #{option.domain} not found for customer #{option.custid}"
        return
      end
    elsif option.custid
      # All domains for a customer
      customer = OT::Customer.load(option.custid)
      raise "Customer #{option.custid} not found" unless customer
      begin
        customer.custom_domains.members.map do |domain_name|
          OT::CustomDomain.load(domain_name, option.custid)
        end
      rescue OT::RecordNotFound
        puts "Customer #{option.custid} not found"
        return
      end
    elsif option.domain
      # All instances of the domain across customers
      matching_domains = OT::CustomDomain.all.select do |domain|
        domain.display_domain == option.domain
      end
      if matching_domains.empty?
        puts "Domain #{option.domain} not found"
        return
      else
        matching_domains
      end
    else
      # All domains
      OT::CustomDomain.all
    end

    total = domains_to_process.size
    puts "Processing #{total} domain#{total == 1 ? '' : 's'}"

    domains_to_process.each_slice(batch_size).with_index do |batch, batch_idx|
      puts "\nProcessing batch #{batch_idx + 1}..."

      batch.each do |domain|
        print "Revalidating #{domain.display_domain}... "
        begin
          params = {
            domain: domain.display_domain
          }
          verifier = OT::Logic::Domains::VerifyDomain.new(nil, domain.custid, params)
          verifier.raise_concerns
          verifier.process
          status = domain.verification_state
          resolving_status = domain.resolving == 'true' ? 'resolving' : 'not resolving'
          puts "#{status} (#{resolving_status})"
        rescue => e
          puts "error: #{e.message}"
          $stderr.puts e.backtrace
        end
      end

      sleep 0.25 # maintain a sane maximum of 4 requests per second

      # Throttle between batches
      if batch_idx < (domains_to_process.size.to_f / batch_size).ceil - 1
        puts "\nWaiting #{throttle_seconds} seconds before next batch..."
        sleep throttle_seconds
      end
    end

    puts "\nRevalidation complete"
  end

  def require_sudo
    return if Process.uid.zero?
    raise 'Must run as root or with sudo'
  end
end
