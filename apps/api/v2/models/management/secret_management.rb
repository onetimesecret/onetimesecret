# apps/api/v2/models/management/secret_management.rb

module V2
  class Secret < Familia::Horreum

    module Management
      def self.spawn_pair custid, token=nil
        secret = V2::Secret.create(custid: custid, token: token)
        metadata = V2::Metadata.create(custid: custid, token: token)

        # TODO: Use Familia transaction
        metadata.secret_key = secret.key
        metadata.save

        secret.metadata_key = metadata.key
        secret.save

        [metadata, secret]
      end

      def self.encryption_key *entropy
        input = entropy.flatten.compact.join ':'
        Digest::SHA256.hexdigest(input) # TODO: Use Familila.generate_id
      end
    end

    extend Management
  end
end
