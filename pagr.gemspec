# frozen_string_literal: true

require_relative "lib/pagr/version"

Gem::Specification.new do |spec|
  spec.name = "pagr"
  spec.version = Pagr::VERSION
  spec.authors = ["Metanous"]

  spec.summary = "Ruby client for the Pagr document rendering API."
  spec.description = "A synchronous Ruby client for the Pagr Public API: " \
                     "templates and versions, document rendering (sync " \
                     "and async jobs), data validation, document " \
                     "browsing, organisation stats and webhook parsing."

  spec.required_ruby_version = ">= 3.0"

  # TODO: confirm which licence this SDK should carry before publishing, then
  # set spec.license (and add a LICENSE file). Left unset for now.

  spec.files = Dir["lib/**/*.rb"] + ["README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"
end
