# spec/rsfc/integration_spec.rb

require 'spec_helper'

RSpec.describe 'RSFC Integration' do
  let(:business_data) do
    {
      greeting: 'Welcome to RSFC',
      user: { name: 'John Doe' }
    }
  end

  describe 'end-to-end template rendering' do
    it 'renders complete template with hydration' do
      # Create authenticated user and session
      user = RSFC::Adapters::AuthenticatedAuth.new(name: 'John Doe', theme: 'dark')
      session = RSFC::Adapters::AuthenticatedSession.new(id: 'test_session', created_at: Time.now)

      # Create view with business data
      view = RSFC::View.new(nil, session, user, 'en', business_data: business_data)

      # Render the test template
      html = view.render('test')

      # Verify template content
      expect(html).to include('<h1>Welcome to RSFC</h1>')
      expect(html).to include('<p>Hello, John Doe!</p>')
      expect(html).to include('class="theme-dark"')

      # Verify data hydration
      expect(html).to include('<script id="rsfc-data-')
      expect(html).to include('type="application/json"')
      expect(html).to include('"message":"Welcome to RSFC"')
      expect(html).to include('"authenticated":true')
      expect(html).to include('window.data = JSON.parse(')
    end

    it 'handles anonymous users' do
      anon_business_data = business_data.merge(user: { name: 'Guest' })
      view = RSFC::View.new(nil, nil, nil, 'en', business_data: anon_business_data)
      html = view.render('test')

      expect(html).to include('<p>Please log in.</p>')
      expect(html).to include('"authenticated":false')
      expect(html).to include('class="theme-light"')
    end
  end

  describe 'template-only rendering' do
    it 'renders just the template section' do
      test_data = business_data.merge(user: { name: 'Guest' })
      view = RSFC::View.new(nil, nil, nil, 'en', business_data: test_data)
      html = view.render_template_only('test')

      expect(html).to include('<h1>Welcome to RSFC</h1>')
      expect(html).not_to include('<script')
    end
  end

  describe 'hydration-only rendering' do
    it 'renders just the data hydration' do
      test_data = business_data.merge(user: { name: 'Guest' })
      view = RSFC::View.new(nil, nil, nil, 'en', business_data: test_data)
      html = view.render_hydration_only('test')

      expect(html).to include('<script id="rsfc-data-')
      expect(html).to include('window.data = JSON.parse(')
      expect(html).not_to include('<h1>')
    end
  end

  describe 'data hash extraction' do
    it 'returns processed data as hash' do
      test_data = business_data.merge(user: { name: 'Guest' })
      view = RSFC::View.new(nil, nil, nil, 'en', business_data: test_data)
      data = view.data_hash('test')

      expect(data).to be_a(Hash)
      expect(data['message']).to eq('Welcome to RSFC')
      expect(data['user']['name']).to eq('Guest')
      expect(data['user']['authenticated']).to be(false)
    end
  end

  describe 'convenience methods' do
    it 'renders via RSFC.render' do
      html = RSFC.render('test', **business_data)

      expect(html).to include('Welcome to RSFC')
      expect(html).to include('<script')
    end

    it 'renders template via RSFC.render_template' do
      template = '{{#if authenticated}}Hello {{user.name}}{{/if}}'
      result = RSFC.render_template(template, authenticated: true, user: { name: 'Test' })

      expect(result).to eq('Hello Test')
    end
  end
end