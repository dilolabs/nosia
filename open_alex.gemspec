$LOAD_PATH.push File.expand_path("lib", __dir__)
require "open_alex/version"

Gem::Specification.new do |spec|
  spec.name          = "open_alex"
  spec.version       = OpenAlex::Version::STRING
  spec.authors       = ["Nosia Team"]
  spec.email         = ["team@nosia.ai"]

  spec.summary       = "OpenAlex API integration for Rails"
  spec.description   = "Rails engine for integrating OpenAlex scholarly API"
  spec.homepage      = "https://github.com/nosia-ai/nosia"
  spec.license       = "MIT"

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:\.git|spec|features|bin)/|\.(?:git|DS_Store|rvmrc|rbi|doctree|buildinfo|project|rxg|swp|bak|~)|Gemfile(?:\.lock)?|gems\.locked)$})
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "faraday"
  spec.add_dependency "json"

  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "webmock"
end