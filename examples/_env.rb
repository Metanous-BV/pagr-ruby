# frozen_string_literal: true

# Shared setup for the example scripts. Reads configuration from the
# environment (never hard-code keys). Run an example with, e.g.:
#
#   PAGR_API_KEY=pagr_test_... \
#     ruby -Ilib examples/render_single.rb
#
# On Windows (PowerShell):
#   $env:PAGR_API_KEY = "pagr_test_..."
#   ruby -Ilib examples/render_single.rb

require "pagr"

module Example
  module_function

  def client
    base_url = ENV.fetch("PAGR_BASE_URL", "http://localhost:5110")
    api_key = ENV.fetch("PAGR_API_KEY") do
      abort "Set PAGR_API_KEY to a pagr_test_ or pagr_prod_ key."
    end
    Pagr::Client.new(api_key, base_url: base_url)
  end

  # Fetches an arbitrary existing template's ID from the API rather than
  # requiring one to be hard-coded or configured.
  def template_id
    first = client.templates(take: 1).items.first
    first ? first.id : abort("No templates found in this organisation. Create one first.")
  end
end
