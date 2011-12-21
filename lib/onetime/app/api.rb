
require 'onetime/app/api/base'

class Onetime::App
  class API
    include Onetime::App::API::Base
    
    def status
      authorized do
        sess.event_incr! :check_status
        json :status => :nominal
      end
    end
    
    def share
      authorized do
        req.params[:kind] = :share
        logic = OT::Logic::CreateSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        if req.get?
          res.redirect app_path(logic.redirect_uri)
        else
          json metadata_hsh(logic.metadata)
        end
      end
    end
    
    def metadata_hsh md, opts={:with_secret => false}
      hsh = md.all
      ret = {
        :custid => hsh['custid'],
        :metadata_key => hsh['key'],
        :secret_key => hsh['secret_key'],
        :ttl => hsh['ttl'],
        :state => hsh['state'],
        :updated => hsh['updated'],
        :created => hsh['created']
      }
      ret[:shared] = hsh['shared'] if hsh['state'].to_s == 'shared'
      if opts[:with_secret]
        secret = md.load_secret
        ret[:value] = secret.decrypted_value if secret.can_decrypt?
      end
      ret
    end
          
    def generate
      authorized do
        req.params[:kind] = :generate
        logic = OT::Logic::CreateSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        if req.get?
          res.redirect app_path(logic.redirect_uri)
        else
          json metadata_hsh(logic.metadata, :with_secret => true)
        end
      end
    end
    
    def show_secret
      authorized do
        req.params[:continue] = 'true'
        logic = OT::Logic::ShowSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        if logic.show_secret
          json :secret => logic.secret_value, :secret_key => req.params[:key]
          logic.secret.destroy!
        else
          not_found :msg => 'Unknown secret', :secret_key => req.params[:key]
        end
      end
    end
    
    def show_metadata
      authorized do
        logic = OT::Logic::ShowMetadata.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        if logic.show_secret
          json metadata_hsh(logic.metadata, :with_secret => true)
          logic.metadata.delete :secret_key
        else
          json metadata_hsh(logic.metadata)
        end
      end
    end
    
  end
end