# ruby -Ilib migrate/2011-11-17-metadata.rb

# This migration was run on 2011-11-17 (and it was kind of broken)
exit 

require 'onetime'
require 'familia/tools'

# Migration steps:
#     ruby support/delete-old-secrets DELETE
#     sudo mkdir /etc/onetime
#     sudo cp etc/dev/config.yml /etc/onetime/config
#     [EDIT CONFIG FILE: move :redis into the root]
#     bundle exec thin -e prod -R config.ru -p 7143 stop
#     ruby -Ilib migrate/2011-11-17-metadata.rb
#     bundle exec thin -e prod -R config.ru -p 7143 start

class OldSecret < Storable
  include Familia
  include Gibbler::Complex
  prefix [:onetime, :secret]
  index :key
  field :kind
  field :key
  field :value
  field :state
  field :original_size
  field :size
  field :passphrase
  field :paired_key
  field :metadata_key
  field :secret_key
  field :custid
  field :value_encryption => Integer
  field :passphrase_encryption => Integer
  gibbler :kind, :entropy
  field :viewed => Integer
  field :shared => Integer
  include Familia::Stamps
  def key
    @key ||= gibbler.base(36)
    @key
  end
  def kind? guess
    kind.to_s == guess.to_s
  end
end

class OT::Secret
  field :kind
  field :paired_key
  def kind? guess
    kind.to_s == guess.to_s
  end
end
class OT::Metadata
  field :kind
  field :paired_key
  def kind? guess
    kind.to_s == guess.to_s
  end
end

begin
  OT.load! :app
  Familia::Tools.rename 'onetime:secret:*:object', OT::Secret.uri do |idx, type, key, ttl|
    obj = OldSecret.from_key(key)
    prefix = obj.kind?(:private) ? :metadata : :secret
    newkey = Familia.join [prefix, obj.key, :object]
    newkey
  end
  
  secrets = OT::Secret.redis.keys '*secret:*:object'; nil
  secrets.each { |key|
    obj = OT::Secret.from_key(key)
    next unless obj.kind?(:shared)
    obj.metadata_key = obj.paired_key unless obj.paired_key.to_s.empty?
    obj.save 
  }; nil
  metadatas = OT::Metadata.redis.keys '*metadata:*:object'; nil
  metadatas.each { |key|
    obj = OT::Metadata.from_key(key)
    next unless obj.kind?(:private)
    obj.secret_key = obj.paired_key unless obj.paired_key.to_s.empty?
    obj.save
  }
  
rescue => ex
  puts "#{ex.class} #{ex.message}", ex.backtrace
  exit 1
end
