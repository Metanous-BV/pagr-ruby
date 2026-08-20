# Pagr Ruby SDK

Official synchronous Ruby client for the [Pagr](https://www.pagr.eu) document
rendering API (`/v1`): manage templates and versions, render documents (single,
batch, or fire-and-forget with webhooks), validate data, browse rendered
documents, and read organisation usage stats.

> [!TIP]
> Want to chat live with Pagr engineers? Join us on our
> [Discord server](https://discord.gg/GajJxfKXZ5).

## Requirements

- **Ruby 3.1** or later.
- A **Pagr API key** — grab it from **Settings → API keys** in the Pagr web app.
  The prefix picks the mode: `pagr_test_*` renders are watermarked and batches are
  capped at 10 documents; `pagr_prod_*` renders for real and consumes credit.
- [Faraday](https://lostisland.github.io/faraday/) 2.x — installed for you as a
  dependency; no other runtime gems are needed. Signature verification uses
  `openssl` from the standard library.

## Installation

The gem is not on RubyGems yet. Point your `Gemfile` at the repository:

```ruby
gem "pagr", git: "https://github.com/Metanous-BV/pagr-ruby.git"
```

Then `bundle install`.

## Quick start

```ruby
require "pagr"

# Targets the hosted Pagr API by default; pass base_url: only to reach another instance.
client = Pagr::Client.new(ENV.fetch("PAGR_API_KEY"))

# List templates
client.templates(take: 25).each { |t| puts t.name }

# Render a document and save the PDF
result = client.render(template_id, { "customer" => "Acme", "total" => 42 },
                       include_document: true)
result.document.save("invoice.pdf") if result.ok?
```

Swap the key at runtime with `client.api_key = new_key` (or the cross-SDK
spelling, `client.set_api_key(new_key)`).

Read-only (GET) calls are retried automatically on transient server-side
failures (HTTP 500/502/503/504, timeouts, connection errors) with capped
exponential backoff and full jitter, honouring a `Retry-After` header when the
server sends one; tune with `Pagr::Client.new(..., max_retries: 2)` (`0`
disables). Rate limits (429) are **not** retried — they reflect your own call
volume, so `Pagr::RateLimitError` is raised for you to handle. Writes
(POST/PATCH) are never retried: the API has no idempotency keys, so a repeat
could render and charge twice.

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

## Webhook callbacks

Async-render callbacks are signed (`X-Pagr-Signature`). Verify and parse one in
a single call, passing the **raw** request body:

```ruby
callback = Pagr.parse_signed_callback(request.body.read,           # never re-serialized JSON
                                      request.env["HTTP_X_PAGR_SIGNATURE"],
                                      ENV.fetch("PAGR_WEBHOOK_SECRET"))
```

The secret comes from Settings → API keys in the web app. Deliveries are
retried and delivered concurrently, so dedupe on `X-Pagr-Delivery` — see the
[User Guide](https://github.com/Metanous-BV/pagr-ruby/blob/main/docs/user-guide.md#4-async-rendering--webhooks).

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
proven to come from Pagr). The hierarchy is flat, so `rescue Pagr::Error` is a
complete safety net — but `rescue Pagr::ApiError` does **not** catch a 404.

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

The full documentation lives in the
[docs wiki](https://github.com/Metanous-BV/pagr-ruby/blob/main/docs/README.md):

- **[User Guide](https://github.com/Metanous-BV/pagr-ruby/blob/main/docs/user-guide.md)**
  — rendering (single, batch, async with webhooks), validation, paging and
  filtering, error handling, and the complete model list.
- **[Contributing](https://github.com/Metanous-BV/pagr-ruby/blob/main/CONTRIBUTING.md)**
  — for maintainers of the SDK.

Runnable scripts are in
[`examples/`](https://github.com/Metanous-BV/pagr-ruby/blob/main/examples/) —
one per topic, from
[`getting_started.rb`](https://github.com/Metanous-BV/pagr-ruby/blob/main/examples/getting_started.rb)
to batch rendering, async jobs, validation, and error handling. See the
[examples README](https://github.com/Metanous-BV/pagr-ruby/blob/main/examples/README.md)
for the full list and setup.

## License

Apache-2.0. See [LICENSE](https://github.com/Metanous-BV/pagr-ruby/blob/main/LICENSE).

- Repository: https://github.com/Metanous-BV/pagr-ruby
- Issues: https://github.com/Metanous-BV/pagr-ruby/issues
