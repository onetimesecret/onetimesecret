# apps/web/core/spec/templates/templates_parse_spec.rb
#
# frozen_string_literal: true

# Every Rhales template in Web Core parses.
#
# error.rue carried a Mustache section (`{{#support_email}}…{{/support_email}}`)
# that Rhales' Handlebars parser rejects. Nothing noticed: the template is only
# parsed when it is rendered or when the hydration schemas are generated, and
# the generator skipped it with a warning, so the error page's schema was
# never produced.

require 'spec_helper'
require 'rhales'

RSpec.describe 'Web Core .rue templates' do
  templates = Dir[File.expand_path('../../templates/**/*.rue', __dir__)]

  it 'finds the templates' do
    expect(templates.map { |path| File.basename(path) }).to include('index.rue', 'error.rue')
  end

  templates.each do |path|
    it "parses #{path.split('/templates/').last}" do
      expect { Rhales::RueDocument.new(File.read(path), path).parse! }.not_to raise_error
    end
  end
end
