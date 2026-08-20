# frozen_string_literal: true

require_relative "lib/pagr/version"

Gem::Specification.new do |spec|
  spec.name = "pagr"
  spec.version = Pagr::VERSION
  spec.authors = ["Metanous"]
  spec.license = "Apache-2.0"

  spec.summary = "Ruby client for the Pagr document rendering API."
  spec.description = "A synchronous Ruby client for the Pagr Public API: " \
                     "templates and versions, document rendering (sync " \
                     "and async jobs), data validation, document " \
                     "browsing, organisation stats and webhook parsing."
  spec.homepage = "https://github.com/Metanous-BV/pagr-ruby"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "documentation_uri" => "#{spec.homepage}/blob/main/docs/user-guide.md",
    "rubygems_mfa_required" => "true"
  }

  # The built gem carries the library, the docs and the runnable examples —
  # but not the spec suite, which needs the development Gemfile.
  spec.files = Dir["lib/**/*.rb"] + Dir["docs/**/*"] + Dir["examples/**/*"] +
               ["README.md", "LICENSE", "CHANGELOG.md", "CONTRIBUTING.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"
end
