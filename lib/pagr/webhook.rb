# frozen_string_literal: true

require "json"
require "openssl"

require_relative "errors"
require_relative "models/render"

module Pagr
  # A per-document progress webhook delivered during an async render. One is
  # sent for each document that successfully renders.
  #
  # +processed+ is how many have completed so far (completion order) and
  # +requested_count+ is the batch size. Documents render in parallel, so
  # callbacks arrive out of input order — +document_index+ is the field that
  # correlates this document back to its input (the embedded +document+
  # carries the same value).
  class RenderProgress
    attr_reader :job_id, :processed, :requested_count, :document_index, :document

    def initialize(job_id:, processed:, requested_count:, document_index:, document:)
      @job_id = job_id
      @processed = processed
      @requested_count = requested_count
      @document_index = document_index
      @document = document
    end

    # Completion percentage (0-100), computed from +processed+/
    # +requested_count+ — not a wire field.
    def progress_pct
      requested_count && !requested_count.zero? ? (processed.to_f / requested_count) * 100 : 0.0
    end

    def self.from_api(data)
      new(
        job_id: Common.require(data, "jobId"),
        processed: Common.require(data, "processed"),
        requested_count: Common.require(data, "requestedCount"),
        document_index: Common.require(data, "documentIndex"),
        document: RenderedDocument.from_api(Common.require(data, "document"))
      )
    end
  end

  # The final webhook delivered once an async render job finishes.
  #
  # +state+ is the terminal lifecycle value — :completed (one or more
  # documents produced, including partial/credit-stopped runs) or :failed
  # (nothing produced); the callback only ever fires at a terminal state, so
  # +state+ is never :pending here. +status+ is the render outcome
  # (:ok/:partial/:insufficient_credit/:failed). +missing_count+ is
  # +requested_count+ minus +rendered_count+ (every document not rendered,
  # whatever the reason); +issues+ carries the per-document diagnostics.
  class RenderCompletion
    attr_reader :job_id, :state, :status, :rendered_count, :requested_count,
                :missing_count, :message, :issues

    def initialize(job_id:, state:, status:, rendered_count: 0, requested_count: 0,
                   missing_count: 0, message: nil, issues: [])
      @job_id = job_id
      @state = state
      @status = status
      @rendered_count = rendered_count
      @requested_count = requested_count
      @missing_count = missing_count
      @message = message
      @issues = issues
    end

    # True when every document in the job rendered.
    def ok?
      status == RenderOutcome::OK
    end

    # True when the job stopped early because the organisation ran out of
    # credit.
    def insufficient_credit?
      status == RenderOutcome::INSUFFICIENT_CREDIT
    end

    def self.from_api(data)
      new(
        job_id: Common.require(data, "jobId"),
        state: RenderJobState.from_api(data["state"]),
        status: RenderOutcome.from_api(data["status"]),
        rendered_count: data.fetch("renderedCount", 0),
        requested_count: data.fetch("requestedCount", 0),
        missing_count: data.fetch("missingCount", 0),
        message: data["message"],
        issues: (data["issues"] || []).map { |i| RenderIssue.from_api(i) }
      )
    end
  end

  # Parses an incoming async-render webhook body into the right typed object: a
  # RenderProgress for per-document callbacks (they carry a "document"), or a
  # RenderCompletion for the final callback.
  #
  # The full expected shape is validated before dispatch, so a payload
  # matching neither shape raises PagrDecodeError rather than being silently
  # mis-parsed into a bogus-but-valid-looking result.
  def self.parse_callback(payload)
    unless payload.is_a?(Hash)
      raise Pagr::PagrDecodeError, "webhook payload must be a JSON object, not #{payload.class}"
    end

    if !payload["document"].nil?
      require_webhook_keys(payload, %w[jobId processed requestedCount documentIndex], shape: "progress")
      RenderProgress.from_api(payload)
    else
      require_webhook_keys(payload, %w[jobId state status], shape: "completion")
      RenderCompletion.from_api(payload)
    end
  end

  # Name of the header carrying the callback signature.
  #
  #   X-Pagr-Signature: t=<unix seconds>,v1=<hex>[,v1=<hex>]
  #
  # Each +v1+ is lowercase-hex <tt>HMAC-SHA256(secret, "{t}.{raw_body}")</tt>.
  # Verifying it is how a receiver tells a genuine callback from any POST that
  # reaches the listening URL. The timestamp is *inside* the signed material,
  # so rejecting an old +t+ also rejects replays of a captured delivery.
  #
  # A second +v1+ appears only while a rotated-out secret is still inside its
  # 24h grace period — verification accepts the callback when *any* +v1+
  # matches, so a receiver can move to a new secret without dropping
  # deliveries.
  SIGNATURE_HEADER = "X-Pagr-Signature"

  # Name of the header carrying the callback's event type: +render.progress+
  # for a per-document callback, +render.completed+ or +render.failed+ for the
  # final one. Useful for routing before the body is parsed; the parsed
  # callback's own type (RenderProgress vs RenderCompletion) is authoritative.
  EVENT_HEADER = "X-Pagr-Event"

  # Name of the header carrying a stable id for this callback. **Retry
  # attempts repeat it**, and the delivery worker makes up to 5 attempts, so
  # this is how a receiver deduplicates — a handler that ignores it will
  # double-process a callback whose first attempt the receiver answered too
  # slowly.
  DELIVERY_HEADER = "X-Pagr-Delivery"

  # How far the signed timestamp may drift from local time, in seconds. Bounds
  # how long a captured callback stays replayable; wide enough to absorb clock
  # skew and the sender's retry backoff.
  DEFAULT_SIGNATURE_TOLERANCE = 300.0

  # Verifies the +X-Pagr-Signature+ header of an async-render callback.
  #
  # Returns +nil+ on success and raises on every failure, so a caller that
  # forgets to check a return value still fails closed.
  #
  # +body+ must be the **raw request body, exactly as received** — the byte
  # string your web framework read off the wire (Rack: +request.body.read+).
  # A body that was parsed into a Hash and re-serialized will *not* reproduce
  # the digest, because +JSON.generate+ changes separators and can change key
  # order. This is by far the most common cause of a signature that "should"
  # match but doesn't. The bytes are used as-is whatever the String's encoding
  # is, so a binary (ASCII-8BIT) body straight out of Rack and the same body
  # as UTF-8 verify identically.
  #
  # +signature_header+ is the header value, or +nil+ when the request carried
  # none (which is itself a failure). +secret+ is the organisation's webhook
  # signing secret — copy it from Settings → API keys in the Pagr web app; it
  # is not available on the +/v1+ API.
  #
  # +tolerance+ is the maximum accepted difference, in seconds, between the
  # signed timestamp and +now+, in either direction; the 5-minute default
  # matches what the Pagr server assumes receivers enforce. +now+ is the
  # current Unix time in seconds and defaults to +Time.now+ — present for
  # testing and for callers with their own clock.
  #
  #   begin
  #     Pagr.verify_signature(raw_body, request.get_header("HTTP_X_PAGR_SIGNATURE"), SECRET)
  #   rescue Pagr::PagrSignatureError
  #     return [400, {}, ["bad signature"]]   # not from Pagr — do not act on it
  #   end
  #   callback = Pagr.parse_callback(JSON.parse(raw_body))
  #
  # Raises PagrSignatureError if the header is absent, malformed, carries a
  # timestamp outside +tolerance+, or if no signature in it matches +secret+ —
  # i.e. anything short of a proven-genuine callback. Raises +ArgumentError+ if
  # +secret+ is blank or +nil+: that is a misconfiguration in the receiver (an
  # unset environment variable, typically), not an untrustworthy callback, so
  # it is deliberately not a PagrSignatureError. Whitespace-only counts as
  # blank — it is always a botched config read, and letting it through to fail
  # as a signature mismatch would diagnose a broken receiver as a forged call.
  def self.verify_signature(body, signature_header, secret,
                            tolerance: DEFAULT_SIGNATURE_TOLERANCE, now: nil)
    if secret.nil? || secret.to_s.strip.empty?
      raise ArgumentError,
            "a webhook signing secret is required to verify a callback; " \
            "copy it from Settings → API keys in the Pagr web app"
    end

    if signature_header.nil? || signature_header.to_s.strip.empty?
      raise PagrSignatureError, "request carried no #{SIGNATURE_HEADER} header"
    end

    timestamp = nil
    candidates = []
    # Any scheme version other than v1 is ignored, so a future v2 alongside v1
    # does not make an otherwise-verifiable callback look malformed.
    signature_header.to_s.split(",").each do |part|
      key, _, value = part.strip.partition("=")
      case key
      when "t" then timestamp = value
      when "v1" then candidates << value
      end
    end

    if timestamp.nil? || candidates.empty?
      raise PagrSignatureError, "unparsable #{SIGNATURE_HEADER} header: #{signature_header.inspect}"
    end

    begin
      signed_at = Integer(timestamp, 10)
    rescue ArgumentError, TypeError
      raise PagrSignatureError,
            "#{SIGNATURE_HEADER} timestamp is not an integer: #{timestamp.inspect}"
    end

    drift = ((now || Time.now.to_f) - signed_at).abs
    if drift > tolerance
      raise PagrSignatureError,
            "callback was signed #{format('%.0f', drift)}s from now, outside the " \
            "#{format('%.0f', tolerance)}s tolerance — stale delivery or a replay"
    end

    # #b takes the raw bytes whatever the incoming encoding is (Rack hands over
    # an ASCII-8BIT body), and keeps the concatenation from ever raising
    # Encoding::CompatibilityError.
    signed = "#{signed_at}.".b << body.to_s.b
    expected = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, signed)

    # Any match wins: during a secret rotation Pagr signs with both the new and
    # the outgoing secret, so only one of them is the one we hold. The compare
    # is constant-time — a timing leak would let an attacker recover a valid
    # signature byte by byte. OpenSSL.secure_compare (not
    # .fixed_length_secure_compare) because it hashes both sides first, so a
    # candidate of the wrong length is a plain mismatch rather than an
    # ArgumentError.
    return nil if candidates.any? { |candidate| OpenSSL.secure_compare(expected, candidate) }

    raise PagrSignatureError,
          "none of the #{candidates.size} signature(s) in #{SIGNATURE_HEADER} " \
          "matched the configured secret"
  end

  # Verifies a callback's signature and parses it, in one call.
  #
  # Preferred over calling .verify_signature and .parse_callback separately: it
  # takes the raw body (the only form the signature can be checked against)
  # and decodes the JSON itself, so there is no window in which an unverified
  # payload has already been parsed and handed to application code.
  #
  #   # Sinatra
  #   post "/pagr-callback" do
  #     raw_body = request.body.read        # raw bytes — never a re-serialized Hash
  #     begin
  #       callback = Pagr.parse_signed_callback(
  #         raw_body, request.env["HTTP_X_PAGR_SIGNATURE"], ENV.fetch("PAGR_WEBHOOK_SECRET")
  #       )
  #     rescue Pagr::PagrSignatureError
  #       halt 400
  #     end
  #     # X-Pagr-Delivery repeats across retries: dedupe on it before acting.
  #     ...
  #   end
  #
  # Arguments are exactly those of .verify_signature. Returns a RenderProgress
  # for per-document callbacks, or a RenderCompletion for the final one.
  #
  # Raises PagrSignatureError if the callback cannot be proven to come from
  # Pagr — *before* the body is decoded, so an unverified payload is never
  # parsed. Raises PagrDecodeError if the verified body is not valid JSON, or
  # matches neither the progress nor the completion shape, and +ArgumentError+
  # if +secret+ is empty.
  def self.parse_signed_callback(body, signature_header, secret,
                                 tolerance: DEFAULT_SIGNATURE_TOLERANCE, now: nil)
    verify_signature(body, signature_header, secret, tolerance: tolerance, now: now)

    begin
      # Read the verified bytes as UTF-8 regardless of the encoding they
      # arrived in, so a binary Rack body parses like any other.
      payload = JSON.parse(body.to_s.b.force_encoding(Encoding::UTF_8))
    rescue JSON::ParserError, EncodingError
      raise PagrDecodeError, "webhook payload is not valid JSON"
    end

    parse_callback(payload)
  end

  # Raises PagrDecodeError if payload is missing any of keys.
  def self.require_webhook_keys(payload, keys, shape:)
    missing = keys.reject { |key| payload.key?(key) }
    return if missing.empty?

    raise Pagr::PagrDecodeError,
          "webhook payload looks like a #{shape} callback but is missing required field(s): #{missing}"
  end
  private_class_method :require_webhook_keys
end
