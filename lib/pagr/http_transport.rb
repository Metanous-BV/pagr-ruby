# frozen_string_literal: true

require "json"
require "faraday"
require_relative "errors"

module Pagr
  # A raw HTTP response: status, headers and the undecoded body. The body is
  # kept as-is so a binary response (the +application/pdf+ Client#render_pdf
  # opts into, or a document download) can be surfaced alongside JSON —
  # decide "PDF vs JSON" from #pdf? before calling #json.
  class RawResponse
    attr_reader :status, :headers, :body

    def initialize(status, headers, body)
      @status = status
      @headers = headers
      @body = body
    end

    # The response's Content-Type header, or an empty string when absent.
    def content_type
      headers["content-type"].to_s
    end

    # The body parsed as JSON. Raises PagrDecodeError (not a bare
    # JSON::ParserError) when the body is not valid JSON, so callers only
    # ever need to catch Pagr::Error subclasses.
    def json
      JSON.parse(body)
    rescue JSON::ParserError
      raise Pagr::PagrDecodeError.new(
        "the Pagr API returned a response whose body was not valid JSON",
        status_code: status
      )
    end

    # Whether the response carried a PDF body.
    def pdf?
      content_type.downcase.include?("application/pdf")
    end
  end

  # Internal HTTP transport shared by Client: request building, bearer
  # authentication, nil-param dropping, retries and error mapping. Not part
  # of the public API surface.
  #
  # Idempotent GET requests are retried on transient failures (see
  # RETRIABLE_STATUS, plus timeouts and connection errors) with capped
  # exponential backoff and full jitter. Writes (POST/PATCH) are never
  # retried: the API has no idempotency keys, so a request that was applied
  # but whose response was lost must not be repeated (it would
  # render/charge twice).
  class HttpTransport
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 2
    DEFAULT_BACKOFF_BASE = 0.5
    DEFAULT_BACKOFF_MAX = 8.0
    # Defensive upper bound on a server Retry-After value we will actually
    # wait. The header is honored as-is up to this many seconds; a larger (or
    # hostile) value is clamped so a single retry can never park the caller
    # for an unbounded time. This is intentionally much larger than
    # backoff_max — the latter caps our own computed backoff, not the
    # server's explicit request.
    DEFAULT_RETRY_AFTER_MAX = 60.0

    # HTTP statuses worth retrying on an idempotent (GET) request: transient
    # server/gateway failures. 4xx statuses are deterministic and never
    # retried — including 429: rate limiting reflects the caller's own
    # request volume, so it is surfaced as RateLimitError for the caller to
    # handle, not retried silently.
    RETRIABLE_STATUS = [500, 502, 503, 504].freeze

    attr_accessor :max_retries, :backoff_base, :backoff_max, :retry_after_max

    def initialize(base_url, api_key, timeout: DEFAULT_TIMEOUT,
                   max_retries: DEFAULT_MAX_RETRIES,
                   backoff_base: DEFAULT_BACKOFF_BASE,
                   backoff_max: DEFAULT_BACKOFF_MAX,
                   retry_after_max: DEFAULT_RETRY_AFTER_MAX)
      raise ArgumentError, "A base URL is required." if base_url.nil? || base_url.to_s.strip.empty?

      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @api_key = api_key
      @max_retries = max_retries
      @backoff_base = backoff_base
      @backoff_max = backoff_max
      @retry_after_max = retry_after_max
      @connection = Faraday.new do |conn|
        conn.options.timeout = timeout
        # FlatParamsEncoder keeps keys like "filters[0].field" intact (percent-
        # encoded) rather than treating the brackets as nested-param syntax.
        conn.options.params_encoder = Faraday::FlatParamsEncoder
        conn.adapter Faraday.default_adapter
      end
    end

    # Replaces the API key used for subsequent requests.
    def set_api_key(value)
      @api_key = value
    end

    def get(path, params = nil, timeout: nil)
      send_request(:get, path, params: params, timeout: timeout, retriable: true)
    end

    def post_json(path, payload, params = nil, headers: nil,
                   non_raising_statuses: [], timeout: nil)
      send_request(
        :post, path, params: params, payload: payload, headers: headers,
                      non_raising_statuses: non_raising_statuses, timeout: timeout
      )
    end

    def patch_json(path, payload, timeout: nil)
      send_request(:patch, path, payload: payload, timeout: timeout)
    end

    private

    # Runs one HTTP attempt and maps the outcome, retrying transient failures
    # up to +max_retries+ extra times when +retriable+ is true. Writes always
    # pass retriable: false so a request that was applied but whose response
    # was lost is never silently repeated.
    def send_request(method, path, params: nil, payload: nil, headers: nil,
                      non_raising_statuses: [], timeout: nil, retriable: false)
      max_attempts = retriable ? @max_retries + 1 : 1
      attempt = 0
      loop do
        attempt += 1
        begin
          response = run_request(method, path, params, payload, headers, timeout)
        rescue Faraday::TimeoutError => e
          if retriable && attempt < max_attempts
            backoff(attempt, nil)
            next
          end
          raise Pagr::PagrTimeoutError, "Request to the Pagr API timed out: #{e.message}"
        rescue Faraday::Error => e
          if retriable && attempt < max_attempts
            backoff(attempt, nil)
            next
          end
          raise Pagr::PagrConnectionError, "Could not reach the Pagr API: #{e.message}"
        end

        raw = RawResponse.new(response.status, response.headers, response.body)

        if retriable && attempt < max_attempts && RETRIABLE_STATUS.include?(raw.status)
          backoff(attempt, raw.headers["Retry-After"])
          next
        end

        # A caller may opt to handle certain statuses itself (e.g. a 422 that
        # carries a business-outcome envelope, not a bind error).
        return raw if non_raising_statuses.include?(raw.status)

        raise_for_status(raw)
        return raw
      end
    end

    def run_request(method, path, params, payload, headers, timeout)
      url = "#{@base_url}/#{path}"
      @connection.run_request(method, url, nil, nil) do |req|
        cleaned = clean_params(params)
        # Merge into the request's existing ParamsHash rather than replacing
        # it with a plain Hash (which would not respond to #to_query).
        req.params.update(cleaned) if cleaned
        req.headers["Accept"] = "application/json"
        unless @api_key.nil? || @api_key.to_s.strip.empty?
          req.headers["Authorization"] = "Bearer #{@api_key}"
        end
        unless payload.nil?
          req.headers["Content-Type"] = "application/json"
          req.body = JSON.generate(payload)
        end
        req.headers.update(headers) if headers
        req.options.timeout = timeout unless timeout.nil?
      end
    end

    # Sleeps before the next retry. When the server sends a Retry-After
    # header carrying an integer number of seconds, that value is honored
    # as-is — only clamped to retry_after_max as a defensive upper bound,
    # never shortened below what the server asked for. Otherwise (no header,
    # or a non-integer value such as an HTTP-date) it uses capped exponential
    # backoff with full jitter.
    def backoff(attempt, retry_after_header)
      delay = parse_retry_after(retry_after_header)
      if delay
        delay = [delay, @retry_after_max].min
      else
        ceiling = [@backoff_base * (2**(attempt - 1)), @backoff_max].min
        delay = rand(0.0..ceiling)
      end
      sleep(delay)
    end

    # Parses a Retry-After header value expressed as an integer number of
    # seconds. Returns nil when absent or not an integer (e.g. an HTTP-date),
    # since the SDK does not interpret the date form.
    def parse_retry_after(value)
      return nil if value.nil? || value.to_s.strip.empty?

      # Force base 10 to prevent octal misparsing (e.g., "010" -> 10, not 8)
      parsed_seconds = Integer(value, 10)

      # Clamp negative values to 0 to prevent Kernel#sleep from crashing
      [parsed_seconds, 0].max.to_f
    rescue ArgumentError, TypeError
      nil
    end

    # Drops keys whose value is nil so optional query args can be passed
    # unconditionally without appearing in the URL.
    def clean_params(params)
      return nil if params.nil? || params.empty?

      cleaned = params.reject { |_, value| value.nil? }
      cleaned.empty? ? nil : cleaned
    end

    def raise_for_status(raw)
      return if raw.status < 400

      code, message = parse_error(raw)
      error_class = STATUS_ERRORS.fetch(raw.status, ApiError)
      if error_class == RateLimitError
        raise error_class.new(
          message, status_code: raw.status, code: code,
                   retry_after: parse_retry_after(raw.headers["Retry-After"])
        )
      end
      raise error_class.new(message, status_code: raw.status, code: code)
    end

    # Extracts a [code, message] pair from an error response, reading the API's
    # {"error":{"code","message"}} envelope and falling back to the raw body.
    def parse_error(raw)
      body = raw.body.to_s
      return [nil, "Pagr API returned HTTP #{raw.status}."] if body.strip.empty?

      begin
        parsed = JSON.parse(body)
        error = parsed.is_a?(Hash) ? parsed["error"] : nil
        return [error["code"], error["message"] || body] if error.is_a?(Hash)
      rescue JSON::ParserError
        # Not JSON; keep the raw body as the message.
      end

      [nil, body]
    end
  end
end
