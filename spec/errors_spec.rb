# frozen_string_literal: true

require "spec_helper"

RSpec.describe "error mapping" do
  let(:client) { build_client }

  {
    401 => Pagr::AuthenticationError,
    403 => Pagr::ForbiddenError,
    404 => Pagr::NotFoundError,
    413 => Pagr::PayloadTooLargeError,
    422 => Pagr::ValidationFailedError,
    429 => Pagr::RateLimitError,
    400 => Pagr::ApiError,
    410 => Pagr::ApiError,
    503 => Pagr::ApiError,
  }.each do |status, error_class|
    it "maps HTTP #{status} to #{error_class}" do
      stub_get("v1/fonts",
               { "error" => { "code" => "SomeCode", "message" => "boom" } },
               status: status)

      expect { client.fonts }.to raise_error(error_class) do |error|
        expect(error.status_code).to eq(status)
        expect(error.code).to eq("SomeCode")
        expect(error.message).to eq("boom")
      end
    end
  end

  it "falls back to the raw body when the response is not the error envelope" do
    stub_get("v1/fonts", "upstream exploded", status: 500, content_type: "text/plain")

    expect { client.fonts }.to raise_error(Pagr::ApiError) do |error|
      expect(error.code).to be_nil
      expect(error.message).to eq("upstream exploded")
    end
  end

  it "uses a generic message for an empty error body" do
    stub_get("v1/meta/status", "", status: 503)

    expect { client.status }.to raise_error(Pagr::ApiError, "Pagr API returned HTTP 503.")
  end

  it "wraps a connection failure in PagrConnectionError" do
    no_retry_client = Pagr::Client.new(API_KEY, base_url: BASE_URL, max_retries: 0)
    stub_request(:get, "#{BASE_URL}/v1/fonts").to_raise(Faraday::ConnectionFailed.new("boom"))

    expect { no_retry_client.fonts }.to raise_error(Pagr::PagrConnectionError, /Could not reach the Pagr API/)
  end

  it "wraps a timeout in PagrTimeoutError" do
    no_retry_client = Pagr::Client.new(API_KEY, base_url: BASE_URL, max_retries: 0)
    stub_request(:get, "#{BASE_URL}/v1/fonts").to_raise(Faraday::TimeoutError.new("boom"))

    expect { no_retry_client.fonts }.to raise_error(Pagr::PagrTimeoutError, /Request to the Pagr API timed out/)
  end

  it "wraps a non-JSON body in PagrDecodeError instead of a bare JSON::ParserError" do
    stub_get("v1/fonts", "not json", content_type: "application/json")

    expect { client.fonts }.to raise_error(Pagr::PagrDecodeError)
  end

  it "parses Retry-After (integer seconds) onto RateLimitError#retry_after" do
    stub_request(:get, "#{BASE_URL}/v1/fonts")
      .to_return(status: 429, headers: { "Retry-After" => "30" }, body: "{}")

    expect { client.fonts }.to raise_error(Pagr::RateLimitError) do |error|
      expect(error.retry_after).to eq(30.0)
    end
  end

  it "leaves retry_after nil when Retry-After is absent or not an integer" do
    stub_request(:get, "#{BASE_URL}/v1/fonts").to_return(status: 429, body: "{}")

    expect { client.fonts }.to raise_error(Pagr::RateLimitError) do |error|
      expect(error.retry_after).to be_nil
    end
  end

  it "exposes PagrConnectionError/PagrTimeoutError/PagrDecodeError under the Pagr::Error base" do
    expect(Pagr::PagrConnectionError.ancestors).to include(Pagr::Error)
    expect(Pagr::PagrTimeoutError.ancestors).to include(Pagr::Error)
    expect(Pagr::PagrDecodeError.ancestors).to include(Pagr::Error)
  end

  it "exposes the status-mapped subclasses under the Pagr::Error base" do
    expect(Pagr::NotFoundError.ancestors).to include(Pagr::Error)
  end
end
