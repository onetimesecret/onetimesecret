# spec/lib/onetime/jobs/queue_ownership_spec.rb

require 'onetime/jobs/workers/email_worker'

RSpec.describe 'Queue declaration ownership' do
  describe 'Sneakers workers' do
    it 'declares work queues via from_queue' do
      # Workers own their queues
      expect(Onetime::Jobs::Workers::EmailWorker.queue_name).to eq('email.message.send')
    end
  end
end
