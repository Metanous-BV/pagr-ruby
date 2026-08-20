# frozen_string_literal: true

module Pagr
  # Base class for every error raised by the SDK's HTTP layer. Rescue this to
  # handle any error the client can raise.
  #
  # +status_code+ is the HTTP status when known. +code+ is the API's
  # machine-readable error code (for example "EntityNotFound",
  # "NoPublishedVersion", "InsufficientCredit", "PdfDeleted" or "QueueFull"),
  # or +nil+ when the response did not carry the expected
  # +{"error": {"code", "message"}}+ body.
  class Error < StandardError
    attr_reader :status_code, :code

    def initialize(message = nil, status_code: nil, code: nil)
      @status_code = status_code
      @code = code
      super(message)
    end
  end

  # 401 — invalid or missing API key.
  class AuthenticationError < Error; end

  # 403 — authenticated but not allowed to access this resource.
  class ForbiddenError < Error; end

  # 404 — template, version, document or job not found.
  class NotFoundError < Error; end

  # 413 — a submitted document exceeds the maximum payload size (50 MB).
  class PayloadTooLargeError < Error; end

  # 422 — the request body could not be bound or validated.
  class ValidationFailedError < Error; end

  # 429 — too many requests; the organisation exceeded its rate limit over the
  # current sliding 60-second window.
  class RateLimitError < Error
    # The number of seconds the server asked the caller to wait before
    # retrying, parsed from the +Retry-After+ response header when it carries
    # an integer number of seconds. +nil+ when the header is absent or not an
    # integer (for example an HTTP-date) — the API does not currently send one
    # on 429s, so treat +nil+ as "back off using your own policy."
    attr_reader :retry_after

    def initialize(message = nil, status_code: nil, code: nil, retry_after: nil)
      @retry_after = retry_after
      super(message, status_code: status_code, code: code)
    end
  end

  # Any other API error (4xx/5xx), including HTTP 400 (for example a test-mode
  # batch over the 10-document limit), 410 (code "PdfDeleted") and 503
  # (code "QueueFull").
  class ApiError < Error; end

  # The request never produced an HTTP response: connection refused, DNS
  # failure, TLS handshake error, connection reset, or another transport-level
  # failure. Wraps the underlying Faraday error (available via +#cause+).
  # +status_code+ and +code+ are always +nil+.
  class PagrConnectionError < Error; end

  # The request exceeded the configured timeout. +status_code+ and +code+ are
  # always +nil+.
  class PagrTimeoutError < Error; end

  # A response was received but its body could not be parsed into the shape a
  # method expected — a non-JSON or empty body where JSON was expected, or a
  # payload missing a required field. When it stems from an HTTP response,
  # +status_code+ carries that response's status; +code+ is always +nil+.
  class PagrDecodeError < Error; end

  # An async-render webhook callback could not be proven to come from Pagr.
  #
  # Raised by Pagr.verify_signature and Pagr.parse_signed_callback when the
  # +X-Pagr-Signature+ header is absent or malformed, when its timestamp falls
  # outside the accepted replay window, or when no signature it carries matches
  # the configured signing secret. Every case means the same thing to a
  # receiver: do not act on the payload — answer the POST with a 4xx and drop
  # it. +status_code+ and +code+ are always +nil+; this is a local verification
  # failure, not an API response.
  #
  # A missing/empty secret raises +ArgumentError+ instead, so a misconfigured
  # receiver stays distinguishable from a forged callback.
  class PagrSignatureError < Error; end

  # Maps an HTTP status code to the error class raised for it. Statuses not
  # listed here raise ApiError.
  STATUS_ERRORS = {
    401 => AuthenticationError,
    403 => ForbiddenError,
    404 => NotFoundError,
    413 => PayloadTooLargeError,
    422 => ValidationFailedError,
    429 => RateLimitError,
  }.freeze
end
