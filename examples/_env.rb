# frozen_string_literal: true

# Shared setup for the example scripts. Reads configuration from the
# environment, or from a `.env` file in this directory (see `.env.example`) —
# never hard-code keys. Run an example with, e.g.:
#
#   PAGR_API_KEY=pagr_test_... ruby -Ilib examples/render_single.rb
#
# On Windows (PowerShell):
#   $env:PAGR_API_KEY = "pagr_test_..."
#   ruby -Ilib examples/render_single.rb

require "pagr"

module Example
  # Fallback for the async-render callback URL. It must be reachable by the
  # Pagr server, so a public URL or a tunnel — never localhost.
  DEFAULT_CALLBACK_URL = "https://your-app.example/pagr/callback"

  module_function

  # Loads `examples/.env` into ENV if it exists, without adding a dependency:
  # `KEY=value` per line, `#` comments and blank lines ignored, surrounding
  # quotes stripped. Existing environment variables always win.
  def load_dotenv
    path = File.join(__dir__, ".env")
    return unless File.exist?(path)

    File.foreach(path) do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      key, separator, value = line.partition("=")
      next if separator.empty?

      ENV[key.strip] ||= value.strip.gsub(/\A["']|["']\z/, "")
    end
  end

  # A client pointed at the hosted Pagr API. No base_url is passed — the SDK
  # defaults to production, which is what an integrator's code should look
  # like.
  def client
    load_dotenv
    api_key = ENV.fetch("PAGR_API_KEY") do
      abort "Set PAGR_API_KEY to a pagr_test_ or pagr_prod_ key (see examples/.env.example)."
    end
    Pagr::Client.new(api_key)
  end

  # Where async-render callbacks should be delivered. Only batch_async.rb uses
  # this; polling works whether or not the callback is ever delivered.
  def callback_url
    load_dotenv
    ENV.fetch("PAGR_CALLBACK_URL", DEFAULT_CALLBACK_URL)
  end

  # Fetches an arbitrary existing template's ID from the API rather than
  # requiring one to be hard-coded or configured.
  def template_id
    first = client.templates(take: 1).items.first
    first ? first.id : abort("No templates found in this organisation. Create one first.")
  end
end
