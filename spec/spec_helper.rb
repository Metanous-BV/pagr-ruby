# frozen_string_literal: true

# Pin the timezone so date-parsing assertions are deterministic regardless of
# the machine running the suite.
ENV["TZ"] = "UTC"

require "webmock/rspec"
require "pagr"

# The base URL and key used across the suite. WebMock intercepts every request,
# so nothing real is contacted and the key is never sent anywhere.
BASE_URL = "https://api.pagr.test"
API_KEY = "pagr_test_key"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random

  config.include Fixtures
  config.include HttpHelpers

  def build_client
    Pagr::Client.new(API_KEY, base_url: BASE_URL)
  end
end
