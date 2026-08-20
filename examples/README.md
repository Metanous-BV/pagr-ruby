# Pagr SDK examples

Runnable scripts, one per topic. Start with `getting_started.rb` and pick the
others as you need them.

| Example | What it shows |
|---|---|
| [`getting_started.rb`](getting_started.rb) | Connect, health check, list templates. |
| [`templates.rb`](templates.rb) | Browse templates and versions: paging, sorting, filters. |
| [`render_single.rb`](render_single.rb) | Render one document and save the PDF. |
| [`render_pdf.rb`](render_pdf.rb) | Opt-in raw-PDF streaming: `render_pdf` returns the PDF bytes with metadata in headers; blocked renders come back as data. |
| [`render_batch.rb`](render_batch.rb) | Synchronous batch render: successes, failures, saving each document. |
| [`batch_async.rb`](batch_async.rb) | Fire-and-forget batch render, tracked by polling the job status. |
| [`validate.rb`](validate.rb) | Validate data against a template without rendering or spending credit. |
| [`documents.rb`](documents.rb) | Listing and downloading previously rendered documents. |
| [`account.rb`](account.rb) | Organisation usage/credit, available fonts, API key rotation. |
| [`error_handling.rb`](error_handling.rb) | Exceptions vs. business outcomes — when to catch what. |

## Setup

The examples talk to the hosted Pagr API; none of them needs a `base_url`.
They read configuration from the environment, or from a `.env` file next to the
scripts. Copy [`.env.example`](.env.example) to `.env` and fill in your key:

```env
PAGR_API_KEY=pagr_test_your_key_here
```

Get the key from **Settings → API keys** in the Pagr web app. The prefix picks
the mode: `pagr_test_*` renders are watermarked and batches are capped at 10
documents; `pagr_prod_*` renders for real and consumes credit. Never commit a
real key — `.env` is gitignored.

Then run any example from the repository root, with the gem's `lib` on the load
path:

```bash
ruby -Ilib examples/getting_started.rb
```

Rendered PDFs are written next to where you run the script, and `*.pdf` is
gitignored.
