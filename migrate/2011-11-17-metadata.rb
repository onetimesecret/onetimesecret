# ruby -Ilib migrate/2011-11-17-metadata.rb

require 'onetime'
require 'familia/tools'

# Migration steps:
#     ruby support/delete-old-secrets DELETE
#     sudo mkdir /etc/onetime
#     sudo cp etc/dev/config.yml /etc/onetime/config
#     [EDIT CONFIG FILE: move :redis into the root]
#     bundle exec thin -e prod -R config.ru -p 7143 stop
#     git co production
#     git pull origin metadata-refactor
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
  field :paired_key
end
class OT::Metadata
  field :paired_key
end

begin
  OT.load! :app
  Familia::Tools.rename 'onetime:secret:*:object', OldSecret.uri do |idx, type, key, ttl|
    obj = OldSecret.from_key(key)
    prefix = obj.kind?(:private) ? :metadata : :secret
    newkey = Familia.join [prefix, obj.key, :object]
    newkey
  end
  secrets = OT::Secret.redis.keys 'secret:*:object'
  secrets.each { |key|
    obj = OT::Secret.from_key(key)
    obj.metadata_key = obj.paired_key unless obj.paired_key.to_s.empty?
    obj.save
  }
  metadatas = OT::Metadata.redis.keys 'metadata:*:object'
  metadatas.each { |key|
    obj = OT::Metadata.from_key(key)
    obj.secret_key = obj.paired_key unless obj.paired_key.to_s.empty?
    obj.save
  }
  
rescue => ex
  puts "#{ex.class} #{ex.message}", ex.backtrace
  exit 1
end
