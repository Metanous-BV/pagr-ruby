# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pagr::HttpTransport do
  let(:transport) { described_class.new(BASE_URL, API_KEY) }

  before do
    # Retry/backoff tests assert attempt counts and Retry-After handling —
    # never let the suite actually sleep for the computed delay.
    allow(transport).to receive(:sleep)
  end

  describe "GET retries (idempotent)" do
    it "retries on a 500 and returns the response once it succeeds" do
      stub_request(:get, "#{BASE_URL}/v1/fonts")
        .to_return(status: 500, body: "boom").then
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      response = transport.get("v1/fonts")

      expect(response.status).to eq(200)
      expect(a_request(:get, "#{BASE_URL}/v1/fonts")).to have_been_made.times(2)
    end

    it "retries up to max_retries times then raises the mapped error" do
      stub_request(:get, "#{BASE_URL}/v1/fonts").to_return(status: 503, body: "boom")

      expect { transport.get("v1/fonts") }.to raise_error(Pagr::ApiError)
      expect(a_request(:get, "#{BASE_URL}/v1/fonts")).to have_been_made.times(3) # 1 + default max_retries(2)
    end

    it "max_retries: 0 disables retries" do
      transport.max_retries = 0
      stub_request(:get, "#{BASE_URL}/v1/fonts").to_return(status: 500, body: "boom")

      expect { transport.get("v1/fonts") }.to raise_error(Pagr::ApiError)
      expect(a_request(:get, "#{BASE_URL}/v1/fonts")).to have_been_made.times(1)
    end

    it "never retries a 429 — it reflects the caller's own request volume" do
      stub_request(:get, "#{BASE_URL}/v1/fonts").to_return(status: 429, body: "{}")

      expect { transport.get("v1/fonts") }.to raise_error(Pagr::RateLimitError)
      expect(a_request(:get, "#{BASE_URL}/v1/fonts")).to have_been_made.times(1)
    end

    it "retries a timeout, then raises PagrTimeoutError once retries are exhausted" do
      stub_request(:get, "#{BASE_URL}/v1/fonts").to_raise(Faraday::TimeoutError.new("boom"))

      expect { transport.get("v1/fonts") }.to raise_error(Pagr::PagrTimeoutError)
      expect(a_request(:get, "#{BASE_URL}/v1/fonts")).to have_been_made.times(3)
    end

    it "retries a connection failure, then raises PagrConnectionError once retries are exhausted" do
      stub_request(:get, "#{BASE_URL}/v1/fonts").to_raise(Faraday::ConnectionFailed.new("boom"))

      expect { transport.get("v1/fonts") }.to raise_error(Pagr::PagrConnectionError)
      expect(a_request(:get, "#{BASE_URL}/v1/fonts")).to have_been_made.times(3)
    end
  end

  describe "writes are never retried" do
    it "does not retry a POST even on a 503" do
      stub_request(:post, "#{BASE_URL}/v1/render").to_return(status: 503, body: "boom")

      expect { transport.post_json("v1/render", { "a" => 1 }) }.to raise_error(Pagr::ApiError)
      expect(a_request(:post, "#{BASE_URL}/v1/render")).to have_been_made.times(1)
    end

    it "does not retry a PATCH even on a 503" do
      stub_request(:patch, "#{BASE_URL}/v1/x").to_return(status: 503, body: "boom")

      expect { transport.patch_json("v1/x", { "a" => 1 }) }.to raise_error(Pagr::ApiError)
      expect(a_request(:patch, "#{BASE_URL}/v1/x")).to have_been_made.times(1)
    end
  end

  describe "backoff" do
    it "honors an integer Retry-After header, clamped to retry_after_max" do
      transport.retry_after_max = 5
      stub_request(:get, "#{BASE_URL}/v1/fonts")
        .to_return(status: 503, headers: { "Retry-After" => "9999" }, body: "boom").then
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      transport.get("v1/fonts")

      expect(transport).to have_received(:sleep).with(5.0)
    end

    it "falls back to capped exponential backoff with jitter when there is no Retry-After" do
      transport.backoff_base = 1.0
      transport.backoff_max = 100.0
      stub_request(:get, "#{BASE_URL}/v1/fonts")
        .to_return(status: 500, body: "boom").then
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      transport.get("v1/fonts")

      # attempt 1: ceiling = backoff_base * 2**0 = 1.0
      expect(transport).to have_received(:sleep).with(satisfy { |delay| delay >= 0 && delay <= 1.0 })
    end
  end

  describe "per-call timeout override" do
    it "accepts a timeout: override on get/post_json/patch_json without raising" do
      stub_get_ok = stub_request(:get, "#{BASE_URL}/v1/fonts")
                    .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })
      stub_post_ok = stub_request(:post, "#{BASE_URL}/v1/render")
                     .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      expect { transport.get("v1/fonts", timeout: 5) }.not_to raise_error
      expect { transport.post_json("v1/render", { "a" => 1 }, timeout: 5) }.not_to raise_error
      expect(stub_get_ok).to have_been_requested
      expect(stub_post_ok).to have_been_requested
    end
  end

  describe "headers: and non_raising_statuses: on post_json" do
    it "merges extra headers over the defaults" do
      stub_request(:post, "#{BASE_URL}/v1/render")
        .with(headers: { "Accept" => "application/pdf" })
        .to_return(status: 200, body: "%PDF", headers: { "Content-Type" => "application/pdf" })

      transport.post_json("v1/render", { "a" => 1 }, headers: { "Accept" => "application/pdf" })

      expect(a_request(:post, "#{BASE_URL}/v1/render").with(headers: { "Accept" => "application/pdf" }))
        .to have_been_made
    end

    it "returns (rather than raises for) a status listed in non_raising_statuses" do
      stub_request(:post, "#{BASE_URL}/v1/render").to_return(status: 422, body: '{"status":"failed"}')

      response = transport.post_json("v1/render", { "a" => 1 }, non_raising_statuses: [422])

      expect(response.status).to eq(422)
    end
  end
end
