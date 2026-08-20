# Pagr Ruby SDK

A synchronous Ruby client for the [Pagr](https://pagr.io) Public API (`/v1`):
templates and versions, document rendering (synchronous and
fire-and-forget async jobs), data validation, document browsing, organisation
statistics, and webhook payload parsing with signature verification.

Requires Ruby 3.0+. The only runtime dependency is
[Faraday](https://lostisland.github.io/faraday/) (signature verification uses
`openssl` from the standard library, so it adds no dependency).

## Installation

Add it to your `Gemfile`:

```ruby
gem "pagr"
```

Then `bundle install`. (The gem is not published yet — for local development,
point at this directory: `gem "pagr", path: "path/to/Pagr.SDK/Ruby"`.)

## Quick start

```ruby
require "pagr"

client = Pagr::Client.new(ENV.fetch("PAGR_API_KEY"))   # hosted API by default

# List templates
client.templates(take: 25).each { |t| puts t.name }

# Render a document and save the PDF
result = client.render(template_id, { "customer" => "Acme", "total" => 42 },
                       include_document: true)
result.document.save("invoice.pdf") if result.ok?
```

The API key prefix selects the mode: `pagr_test_` keys render with test
restrictions (watermarked output, batches capped at 10 documents per request);
`pagr_prod_` keys render fully and consume credit. Swap the key at runtime with
`client.set_api_key(new_key)`.

## What you can do

| Area | Methods |
|------|---------|
| Templates | `templates`, `template`, `template_versions`, `template_version`, `update_document_name_template`, `preview_image_url` |
| Render | `render`, `render_pdf`, `render_batch`, `enqueue_batch_render`, `job_status`, `wait_for_job` |
| Validate | `validate` |
| Documents | `documents`, `document`, `download_document` |
| Fonts / Org / Meta | `fonts`, `org_stats`, `status`, `version` |
| Webhooks (module methods) | `Pagr.parse_signed_callback`, `Pagr.verify_signature`, `Pagr.parse_callback` |

Data inputs (`json_data`, template DSL, translations) accept a `Hash` **or** a
JSON `String` throughout.

Async-render callbacks are signed (`X-Pagr-Signature`). Verify and parse one in
a single call, passing the **raw** request body:

```ruby
callback = Pagr.parse_signed_callback(request.body.read,           # never re-serialized JSON
                                      request.env["HTTP_X_PAGR_SIGNATURE"],
                                      ENV.fetch("PAGR_WEBHOOK_SECRET"))
```

The secret comes from Settings → API keys in the web app. Deliveries are
retried and delivered concurrently, so dedupe on `X-Pagr-Delivery` — see
[`docs/user-guide.md`](docs/user-guide.md#4-async-rendering--webhooks).

## Errors vs. outcomes

HTTP-level failures raise a typed `Pagr::Error` subclass:

| Status | Exception |
|--------|-----------|
| 401 | `Pagr::AuthenticationError` |
| 403 | `Pagr::ForbiddenError` |
| 404 | `Pagr::NotFoundError` |
| 413 | `Pagr::PayloadTooLargeError` |
| 422 | `Pagr::ValidationFailedError` |
| 429 | `Pagr::RateLimitError` |
| other (incl. 400/410/503) | `Pagr::ApiError` |

Each carries `#status_code` and `#code` (the API's machine-readable code).
Local failures are `Pagr::Error` subclasses too: `Pagr::PagrTimeoutError` /
`Pagr::PagrConnectionError` (no response), `Pagr::PagrDecodeError` (unusable
body) and `Pagr::PagrSignatureError` (a webhook callback that could not be
proven to come from Pagr).

**Business outcomes are data, not exceptions**: a document that failed
validation, insufficient credit, or a per-document render failure all come back
on the result objects — inspect `result.ok?`, `result.status`, and
`result.issues`.

```ruby
begin
  result = client.render(template_id, data)
  if result.ok?
    result.document.save("out.pdf")
  else
    result.issues.each { |issue| warn issue }        # e.g. MissingBinding, RenderTimeout
  end
rescue Pagr::AuthenticationError
  warn "Check your API key."
rescue Pagr::Error => e
  warn "Pagr API error (#{e.status_code}): #{e.message}"
end
```

## Documentation

See [`docs/user-guide.md`](docs/user-guide.md) for the full reference and
[`examples/`](examples/) for runnable scripts.

## Development

```bash
bundle install
bundle exec rspec      # unit tests (WebMock — no network)
```
