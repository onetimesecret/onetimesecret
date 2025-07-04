# rsfc.gemspec

require_relative 'lib/rsfc/version'

Gem::Specification.new do |spec|
  spec.name          = "rsfc"
  spec.version       = RSFC::VERSION
  spec.authors       = ["OneTime Secret"]
  spec.email         = ["support@onetimesecret.com"]
  
  spec.summary       = "Ruby Single File Components - Server-rendered components with client-side hydration"
  spec.description   = <<~DESC
    RSFC (Ruby Single File Components) is a framework for building server-rendered 
    components with client-side data hydration using .rue files. Similar to Vue.js 
    single file components but for Ruby applications.
    
    Features include Handlebars-style templating, JSON data injection, partial support, 
    pluggable authentication adapters, and security-first design.
  DESC
  
  spec.homepage      = "https://github.com/onetimesecret/onetimesecret"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/onetimesecret/onetimesecret"
  spec.metadata["changelog_uri"] = "https://github.com/onetimesecret/onetimesecret/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/onetimesecret/onetimesecret/blob/main/README.md"

  # Specify which files should be added to the gem
  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "*.md", "*.txt", "*.gemspec"].select { |f| File.file?(f) }
  end
  
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "prism", "~> 1.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "simplecov", "~> 0.22"

  # Optional dependencies for enhanced functionality
  spec.add_development_dependency "rack", "~> 2.0" # For request handling examples
  spec.add_development_dependency "benchmark-ips", "~> 2.0" # For performance testing
end