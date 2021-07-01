# ruby -Ilib migrate/2012-01-05-fix-cust-planid.rb

# Some new customers have the short gibbler ID instead of
# the actual value for cust.planid. This updates cust.planid
# for only customers that are affected. If the bad cust.planid 
# does not return a plan, individual_v1 is assumed.

require 'onetime'

if true #ARGV.first != 'MIGRATE'
  OT.info "No change made"
  exit 
end

def run
  OT.load! :app
  
  OT::Customer.all.each do |cust|
    next if cust.nil? || cust.custid.to_s == 'GLOBAL'
    next unless cust.planid =~ /\A[a-f0-9]{8}+\z/
    plan = OT::Plan.plan(cust.planid)
    plan ||= OT::Plan.plan(:individual_v1)
    OT.info "Updating #{cust.custid} (#{cust.planid})"
    cust.planid = plan.planid
    OT.info " -> #{cust.planid}"
  end
  
end

begin
  run
rescue => ex
  puts "#{ex.class} #{ex.message}", ex.backtrace
  exit 1
end
