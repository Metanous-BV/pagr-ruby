# frozen_string_literal: true

require "json"

# Convenience wrappers around WebMock for stubbing the Pagr API. Each stub
# matches any query string (assert specific query params separately with
# `a_request(...).with(query: hash_including(...))`).
module HttpHelpers
  def stub_get(path, body = {}, status: 200, content_type: "application/json")
    stub_endpoint(:get, path, body, status, content_type)
  end

  def stub_post(path, body = {}, status: 200, content_type: "application/json")
    stub_endpoint(:post, path, body, status, content_type)
  end

  def stub_patch(path, body = {}, status: 200, content_type: "application/json")
    stub_endpoint(:patch, path, body, status, content_type)
  end

  def stub_endpoint(method, path, body, status, content_type)
    stub_request(method, "#{BASE_URL}/#{path}")
      .with(query: hash_including({}))
      .to_return(
        status: status,
        body: body.is_a?(String) ? body : JSON.generate(body),
        headers: { "Content-Type" => content_type }
      )
  end
end
