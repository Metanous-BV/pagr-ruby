# frozen_string_literal: true

require "spec_helper"

# The signatures these specs check against are built here the way the Pagr
# server builds them (Pagr.Api.Shared/Services/Rendering/WebhookSigner.cs),
# with bare OpenSSL::HMAC — never by calling the SDK's own verifier, since a
# helper that agrees with itself proves nothing. The cases mirror
# Python/tests/test_webhook.py, plus the canonical vector in
# docs/parity-contract.md §9 asserted as hardcoded hex.

SIGNING_SECRET = "whsec_test-secret"
OTHER_ORG_SECRET = "whsec_someone-elses-secret"
ROTATED_IN_SECRET = "whsec_the-new-one"

SIGNED_AT = 1_754_899_200.0

# The exact byte string from parity-contract.md §9 — note the spaces after ":"
# and "," which are part of the signed bytes. Written out literally rather than
# built with JSON.generate, which emits no spaces and so would not be the
# canonical body.
CANONICAL_BODY = '{"jobId": "3f2504e0-4f89-11d3-9a0c-0305e82c3301", "state": "completed", ' \
                 '"status": "ok", "renderedCount": 2, "requestedCount": 2}'

CANONICAL_PROGRESS_BODY =
  '{"jobId": "3f2504e0-4f89-11d3-9a0c-0305e82c3301", "processed": 1, ' \
  '"requestedCount": 2, "documentIndex": 0, "document": ' \
  '{"id": "f47ac10b-58cc-4372-a567-0e02b2c3d479", "documentName": "Invoice 1", ' \
  '"templateId": "1b4e28ba-2fa1-11d2-883f-0016d3cca427", "versionNumber": 3, ' \
  '"environment": "test", "fileSizeBytes": 1024, "pageCount": 1, ' \
  '"renderedAt": "2026-08-11T09:00:00Z", "renderDuration": 42.0, ' \
  '"documentType": "Template"}}'

# The vector's expected hex, for CANONICAL_BODY signed at SIGNED_AT.
CANONICAL_V1 = "bcaa0dced1702951e44a0c10c9729c853d59433fbb954a8c299e743abd89b2bf"
CANONICAL_HEADER = "t=1754899200,v1=#{CANONICAL_V1}"
CANONICAL_V1_OTHER_ORG = "471267f764e691c424f4d19583d663595c632be130899c42565d07c216f7446a"
CANONICAL_V1_ROTATED_IN = "2ec463ea515f6d65cb098c2b65d38e6f54063459a1e3da06f56bd42e70772f33"

# A body whose bytes are not all ASCII, to pin that the digest covers bytes and
# not characters.
MULTIBYTE_BODY = '{"jobId": "job-1", "state": "completed", "status": "ok", "message": "café ✓"}'

RSpec.describe "Pagr webhook signature verification" do
  # Builds an X-Pagr-Signature header exactly the way the server does.
  def sign(body, *secrets, at: SIGNED_AT)
    timestamp = at.to_i
    signed = "#{timestamp}.".b << body.to_s.b
    parts = ["t=#{timestamp}"]
    parts += secrets.map { |secret| "v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, signed)}" }
    parts.join(",")
  end

  describe "the canonical vector from parity-contract.md §9" do
    it "is what the server-side signing used by these specs produces" do
      expect(sign(CANONICAL_BODY, SIGNING_SECRET)).to eq(CANONICAL_HEADER)
      expect(sign(CANONICAL_BODY, OTHER_ORG_SECRET)).to eq("t=1754899200,v1=#{CANONICAL_V1_OTHER_ORG}")
      expect(sign(CANONICAL_BODY, ROTATED_IN_SECRET)).to eq("t=1754899200,v1=#{CANONICAL_V1_ROTATED_IN}")
    end

    it "verifies against the hardcoded header" do
      expect(Pagr.verify_signature(CANONICAL_BODY, CANONICAL_HEADER, SIGNING_SECRET, now: SIGNED_AT))
        .to be_nil
    end

    it "verifies the hardcoded rotation header when only the rotated-out secret is held" do
      header = "t=1754899200,v1=#{CANONICAL_V1_ROTATED_IN},v1=#{CANONICAL_V1}"

      expect(Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT)).to be_nil
    end

    it "rejects the hardcoded header of another organisation" do
      header = "t=1754899200,v1=#{CANONICAL_V1_OTHER_ORG}"

      expect { Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrSignatureError)
    end
  end

  describe ".verify_signature" do
    it "accepts a signature produced by the server, returning nil" do
      # nil rather than a boolean: nothing to accidentally ignore.
      header = sign(CANONICAL_BODY, SIGNING_SECRET)

      expect(Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT)).to be_nil
    end

    it "accepts a binary (ASCII-8BIT) body identically to a UTF-8 one" do
      # Rack hands the raw body over as ASCII-8BIT; the digest must cover the
      # same bytes either way.
      header = sign(CANONICAL_BODY, SIGNING_SECRET)
      raw = CANONICAL_BODY.b

      expect(raw.encoding).to eq(Encoding::ASCII_8BIT)
      expect(Pagr.verify_signature(raw, header, SIGNING_SECRET, now: SIGNED_AT)).to be_nil
    end

    it "accepts a multi-byte body whatever encoding the String carries" do
      header = sign(MULTIBYTE_BODY, SIGNING_SECRET)

      expect(Pagr.verify_signature(MULTIBYTE_BODY, header, SIGNING_SECRET, now: SIGNED_AT)).to be_nil
      expect(Pagr.verify_signature(MULTIBYTE_BODY.b, header, SIGNING_SECRET, now: SIGNED_AT)).to be_nil
    end

    it "accepts a callback during rotation when only the old secret is held" do
      # The server signs with both secrets for the grace period, so a receiver
      # that has not switched over yet must still verify — that is what makes
      # rotation non-breaking.
      header = sign(CANONICAL_BODY, ROTATED_IN_SECRET, SIGNING_SECRET)

      expect(Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT)).to be_nil
    end

    it "accepts a retry signed within the tolerance" do
      # Each retry attempt is re-signed with a fresh timestamp, so a delivery
      # that lands on attempt 4 is not mistaken for a replay.
      header = sign(CANONICAL_BODY, SIGNING_SECRET, at: SIGNED_AT - 120)

      expect(Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT)).to be_nil
    end

    it "ignores an unknown scheme version" do
      # A future v2= alongside v1= must not make the header unparsable.
      header = "#{sign(CANONICAL_BODY, SIGNING_SECRET)},v2=deadbeef"

      expect(Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT)).to be_nil
    end

    it "rejects a tampered body" do
      header = sign(CANONICAL_BODY, SIGNING_SECRET)
      tampered = CANONICAL_BODY.sub("completed", "failed!!!")

      expect { Pagr.verify_signature(tampered, header, SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrSignatureError, /matched the configured/)
    end

    it "rejects a re-serialized body" do
      # The documented footgun: same JSON *value*, different bytes. Worth
      # pinning, because it is the failure everyone hits first.
      header = sign(CANONICAL_BODY, SIGNING_SECRET)
      re_serialized = JSON.generate(JSON.parse(CANONICAL_BODY))

      expect(re_serialized).not_to eq(CANONICAL_BODY)
      expect { Pagr.verify_signature(re_serialized, header, SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrSignatureError)
    end

    it "rejects a signature from another organisation" do
      header = sign(CANONICAL_BODY, OTHER_ORG_SECRET)

      expect { Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrSignatureError)
    end

    it "rejects a replayed callback" do
      header = sign(CANONICAL_BODY, SIGNING_SECRET, at: SIGNED_AT - 1800)

      expect { Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrSignatureError, /outside the/)
    end

    it "rejects a future-dated callback" do
      # Drift is absolute in both directions, matching the server-side
      # verifier — a far-future t must not buy an attacker an open window.
      header = sign(CANONICAL_BODY, SIGNING_SECRET, at: SIGNED_AT + 1800)

      expect { Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrSignatureError, /outside the/)
    end

    it "takes the tolerance from a keyword argument" do
      header = sign(CANONICAL_BODY, SIGNING_SECRET, at: SIGNED_AT - 600)

      expect(Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, tolerance: 900, now: SIGNED_AT))
        .to be_nil
      expect { Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, tolerance: 60, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrSignatureError)
    end

    it "defaults the tolerance to five minutes" do
      expect(Pagr::DEFAULT_SIGNATURE_TOLERANCE).to eq(300.0)

      inside = sign(CANONICAL_BODY, SIGNING_SECRET, at: SIGNED_AT - 299)
      outside = sign(CANONICAL_BODY, SIGNING_SECRET, at: SIGNED_AT - 301)

      expect(Pagr.verify_signature(CANONICAL_BODY, inside, SIGNING_SECRET, now: SIGNED_AT)).to be_nil
      expect { Pagr.verify_signature(CANONICAL_BODY, outside, SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrSignatureError)
    end

    it "defaults now to the current clock" do
      header = sign(CANONICAL_BODY, SIGNING_SECRET, at: Time.now.to_f)

      expect(Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET)).to be_nil
    end

    it "names the header it looks for" do
      expect(Pagr::SIGNATURE_HEADER).to eq("X-Pagr-Signature")
    end

    [nil, "", "   "].each do |header|
      it "rejects an unsigned request (header #{header.inspect})" do
        expect { Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT) }
          .to raise_error(Pagr::PagrSignatureError, /no X-Pagr-Signature/)
      end
    end

    [
      "garbage",
      "t=notanumber,v1=abc",
      "t=1754899200",   # no signature at all
      "v1=abc",         # no timestamp, so nothing bounds a replay
    ].each do |header|
      it "rejects a malformed header (#{header.inspect})" do
        expect { Pagr.verify_signature(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT) }
          .to raise_error(Pagr::PagrSignatureError)
      end
    end

    [nil, "", "   ", "\t\n"].each do |secret|
      it "treats a blank secret (#{secret.inspect}) as a configuration error, not a bad signature" do
        # Deliberately NOT PagrSignatureError, and deliberately not a silent
        # pass: an unset env var must be loud and distinguishable from a forged
        # callback. Whitespace-only counts as absent — it is always a botched
        # config read, never a real secret.
        header = sign(CANONICAL_BODY, SIGNING_SECRET)

        expect { Pagr.verify_signature(CANONICAL_BODY, header, secret, now: SIGNED_AT) }
          .to raise_error(ArgumentError, /signing secret is required/)
      end
    end

    it "does not let a configuration error be rescued as a signature error" do
      expect { Pagr.verify_signature(CANONICAL_BODY, "t=1,v1=a", "", now: SIGNED_AT) }
        .to raise_error(ArgumentError) { |error| expect(error).not_to be_a(Pagr::PagrSignatureError) }
    end
  end

  describe ".parse_signed_callback" do
    it "verifies and parses a completion" do
      callback = Pagr.parse_signed_callback(
        CANONICAL_BODY, sign(CANONICAL_BODY, SIGNING_SECRET), SIGNING_SECRET, now: SIGNED_AT
      )

      expect(callback).to be_a(Pagr::RenderCompletion)
      expect(callback.job_id).to eq("3f2504e0-4f89-11d3-9a0c-0305e82c3301")
      expect(callback).to be_ok
    end

    it "verifies and parses a progress callback" do
      callback = Pagr.parse_signed_callback(
        CANONICAL_PROGRESS_BODY, sign(CANONICAL_PROGRESS_BODY, SIGNING_SECRET), SIGNING_SECRET,
        now: SIGNED_AT
      )

      expect(callback).to be_a(Pagr::RenderProgress)
      expect(callback.document_index).to eq(0)
      expect(callback.document.document_name).to eq("Invoice 1")
    end

    it "parses a binary body carrying multi-byte characters" do
      raw = MULTIBYTE_BODY.b

      callback = Pagr.parse_signed_callback(raw, sign(raw, SIGNING_SECRET), SIGNING_SECRET, now: SIGNED_AT)

      expect(callback.message).to eq("café ✓")
    end

    it "does not parse an unverified payload" do
      # The point of the combined helper: a bad signature must fail before the
      # body is decoded, so application code never sees a payload that was not
      # proven to come from Pagr.
      header = sign(CANONICAL_BODY, OTHER_ORG_SECRET)

      expect { Pagr.parse_signed_callback(CANONICAL_BODY, header, SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrSignatureError)
    end

    it "raises PagrDecodeError for a verified but unparsable body" do
      body = "not json at all"

      expect { Pagr.parse_signed_callback(body, sign(body, SIGNING_SECRET), SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrDecodeError, /not valid JSON/)
    end

    it "raises PagrDecodeError for a verified body of the wrong shape" do
      body = '{"jobId": "3f2504e0-4f89-11d3-9a0c-0305e82c3301"}'

      expect { Pagr.parse_signed_callback(body, sign(body, SIGNING_SECRET), SIGNING_SECRET, now: SIGNED_AT) }
        .to raise_error(Pagr::PagrDecodeError, /missing/)
    end

    it "raises ArgumentError for an absent secret" do
      header = sign(CANONICAL_BODY, SIGNING_SECRET)

      expect { Pagr.parse_signed_callback(CANONICAL_BODY, header, "", now: SIGNED_AT) }
        .to raise_error(ArgumentError, /signing secret is required/)
    end
  end
end
