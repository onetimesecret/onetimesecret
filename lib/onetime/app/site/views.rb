module Onetime
  module Views
    class Homepage < Onetime::View
      def init *args
        self[:title] = "Share a secret"
        self[:monitored_link] = true
      end
    end
    module Info
      class Privacy < Onetime::View
        def init *args
          self[:title] = "Privacy Policy"
          self[:monitored_link] = true
        end
      end
       class Security < Onetime::View
        def init *args
          self[:title] = "Security Policy"
          self[:monitored_link] = true
        end
      end
    end
     class UnknownSecret < Onetime::View
      def init 
        self[:title] = "No such secret"
      end
    end
    class Shared < Onetime::View
      def init 
        self[:title] = "You received a secret"
        self[:body_class] = :generate
      end
      def display_lines
        ret = self[:secret_value].to_s.scan(/\n/).size + 2
        ret = ret > 20 ? 20 : ret
      end
      def one_liner
        self[:secret_value].to_s.scan(/\n/).size.zero?
      end
    end
    class Private < Onetime::View
      def init metadata, secret
        self[:title] = "You saved a secret"
        self[:body_class] = :generate
        self[:metadata_key] = metadata.key
        self[:been_shared] = metadata.state?(:shared)
        self[:shared_date] = natural_time(metadata.shared.to_i || 0)
        unless secret.nil?
          self[:secret_key] = secret.key
          self[:show_passphrase] = !secret.passphrase_temp.to_s.empty?
          self[:passphrase_temp] = secret.passphrase_temp
          self[:secret_value] = secret.can_decrypt? ? secret.decrypted_value : secret.value
        end
      end
      def share_uri
        [baseuri, :secret, self[:secret_key]].join('/')
      end
      def admin_uri
        [baseuri, :private, self[:metadata_key]].join('/')
      end
      def display_lines
        ret = self[:secret_value].to_s.scan(/\n/).size + 2
        ret = ret > 20 ? 20 : ret
      end
      def one_liner
        self[:secret_value].to_s.scan(/\n/).size.zero?
      end
    end
    class Error < Onetime::View
      def init *args
        self[:title] = "Oh cripes!"
      end
    end
  end
  
end
