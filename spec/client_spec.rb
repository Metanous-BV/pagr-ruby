# frozen_string_literal: true

require "spec_helper"

RSpec.describe Pagr::Client do
  let(:client) { build_client }
  let(:template_id) { "22222222-2222-2222-2222-222222222222" }

  describe "authentication" do
    it "sends the API key as a bearer token" do
      stub_get("v1/fonts", ["Arial"])
      client.fonts
      expect(
        a_request(:get, "#{BASE_URL}/v1/fonts")
          .with(headers: { "Authorization" => "Bearer #{API_KEY}" })
      ).to have_been_made
    end

    it "swaps the key at runtime with #set_api_key" do
      stub_get("v1/fonts", [])
      client.set_api_key("pagr_prod_new")
      client.fonts
      expect(
        a_request(:get, "#{BASE_URL}/v1/fonts")
          .with(headers: { "Authorization" => "Bearer pagr_prod_new" })
      ).to have_been_made
    end

    it "swaps the key at runtime with #api_key=" do
      stub_get("v1/fonts", [])
      client.api_key = "pagr_prod_alias"
      client.fonts
      expect(
        a_request(:get, "#{BASE_URL}/v1/fonts")
          .with(headers: { "Authorization" => "Bearer pagr_prod_alias" })
      ).to have_been_made
    end
  end

  describe "#templates" do
    it "lists templates and maps them into a PagedResult" do
      stub_get("v1/templates", { "items" => [template], "total" => 50, "skip" => 10, "take" => 5 })

      page = client.templates(
        skip: 10, take: 5, sort_by: "name",
        filters: [{ field: "name", op: :contains, value: "inv" }]
      )

      expect(page).to be_a(Pagr::PagedResult)
      expect(page.total).to eq(50)
      expect(page.items.first.name).to eq("Invoice")
      expect(page).to be_more
      # NB: exact filter[i] serialisation is asserted in list_options_spec.rb.
      # WebMock's URI parser mangles the bracketed keys on interception, so we
      # only assert the plain params here.
      expect(
        a_request(:get, "#{BASE_URL}/v1/templates").with(query: hash_including(
          "skip" => "10", "take" => "5", "sortBy" => "name"
        ))
      ).to have_been_made
    end

    it "scopes to a project when project_id is given" do
      project_id = "33333333-3333-3333-3333-333333333333"
      stub_get("v1/projects/#{project_id}/templates", { "items" => [], "total" => 0 })
      client.templates(project_id: project_id)
      expect(a_request(:get, "#{BASE_URL}/v1/projects/#{project_id}/templates")).to have_been_made
    end
  end

  describe "#template_version" do
    it "targets the latest published version when version is nil" do
      stub_get("v1/templates/#{template_id}/versions/latest",
               { "id" => "v", "versionNumber" => 3, "templateJson" => "{}",
                 "sampleData" => "{}", "documentNameTemplate" => nil,
                 "publishedAt" => nil, "publishedBy" => nil,
                 "templateId" => template_id, "updatedAt" => nil })
      version = client.template_version(template_id)
      expect(version.version_number).to eq(3)
      expect(a_request(:get, "#{BASE_URL}/v1/templates/#{template_id}/versions/latest")).to have_been_made
    end

    it "targets a specific version number" do
      stub_get("v1/templates/#{template_id}/versions/2",
               { "id" => "v", "versionNumber" => 2, "templateJson" => "{}",
                 "sampleData" => "{}", "documentNameTemplate" => nil,
                 "publishedAt" => nil, "publishedBy" => nil,
                 "templateId" => template_id, "updatedAt" => nil })
      client.template_version(template_id, 2)
      expect(a_request(:get, "#{BASE_URL}/v1/templates/#{template_id}/versions/2")).to have_been_made
    end
  end

  describe "#update_document_name_template" do
    it "PATCHes an explicit null to clear the name template" do
      stub_patch("v1/templates/#{template_id}/versions/2/document-name-template",
                 { "id" => "v", "versionNumber" => 2, "templateJson" => "{}",
                   "sampleData" => "{}", "documentNameTemplate" => nil,
                   "publishedAt" => nil, "publishedBy" => nil,
                   "templateId" => template_id, "updatedAt" => nil })

      client.update_document_name_template(template_id, 2, nil)

      expect(
        a_request(:patch, "#{BASE_URL}/v1/templates/#{template_id}/versions/2/document-name-template")
          .with { |req| JSON.parse(req.body) == { "documentNameTemplate" => nil } }
      ).to have_been_made
    end
  end

  describe "#preview_image_url" do
    it "reads the url out of the response envelope" do
      stub_get("v1/templates/#{template_id}/versions/3/preview-image",
               { "url" => "https://cdn.pagr.test/previews/abc.png" })

      url = client.preview_image_url(template_id, 3)

      expect(url).to eq("https://cdn.pagr.test/previews/abc.png")
      expect(
        a_request(:get, "#{BASE_URL}/v1/templates/#{template_id}/versions/3/preview-image")
      ).to have_been_made
    end

    it "raises NotFoundError when the version has no preview image" do
      # The API answers "no preview image" with a 404 carrying code
      # "ImageNotFound" — not a 200 with an empty body — so this surfaces as
      # an exception, not as nil. Both sibling SDKs behave the same way.
      stub_get("v1/templates/#{template_id}/versions/3/preview-image",
               { "error" => { "code" => "ImageNotFound",
                              "message" => "No preview image exists for this template version." } },
               status: 404)

      expect { client.preview_image_url(template_id, 3) }
        .to raise_error(Pagr::NotFoundError) { |e| expect(e.code).to eq("ImageNotFound") }
    end
  end

  describe "#render" do
    it "renders a single document and sends the persist query param" do
      stub_post("v1/render/#{template_id}",
                { "documents" => [rendered_document], "status" => "ok",
                  "renderedCount" => 1, "requestedCount" => 1, "missingCount" => 0, "issues" => [] })

      result = client.render(template_id, { "customer" => "Acme" })

      expect(result).to be_ok
      expect(result.document.document_name).to eq("Invoice-001")
      expect(
        a_request(:post, "#{BASE_URL}/v1/render/#{template_id}")
          .with(query: hash_including("persist" => "true")) do |req|
            JSON.parse(req.body) == { "documents" => [{ "customer" => "Acme" }], "includeDocument" => false }
          end
      ).to have_been_made
    end

    it "accepts a JSON string as the document data" do
      stub_post("v1/render/#{template_id}",
                { "documents" => [rendered_document], "status" => "ok" })
      client.render(template_id, '{"customer":"Acme"}')
      expect(
        a_request(:post, "#{BASE_URL}/v1/render/#{template_id}")
          .with(query: hash_including({})) { |req| JSON.parse(req.body)["documents"] == [{ "customer" => "Acme" }] }
      ).to have_been_made
    end

    it "reads persist: false as the same JSON envelope, id/view_url nil and bytes forced inline" do
      stub_post("v1/render/#{template_id}", {
        "status" => "ok", "renderedCount" => 1, "requestedCount" => 1,
        "documents" => [rendered_document(
          "id" => nil, "viewUrl" => nil, "documentBase64" => ["%PDF-1.4 fake"].pack("m0")
        )]
      })

      result = client.render(template_id, {}, persist: false)

      expect(result).to be_ok
      expect(result.document.id).to be_nil
      expect(result.document.view_url).to be_nil
      # Every other field is real — no placeholders.
      expect(result.document.environment).to eq("test")
      expect(result.document.to_bytes).to eq("%PDF-1.4 fake")
    end

    it "never sniffs Content-Type: a raw PDF body on the JSON path is a decode error" do
      # #render negotiates Accept: application/json and the API never answers it
      # with a PDF. Sniffing one and fabricating a placeholder-filled document
      # (template_id: nil, environment: "") is what parity-contract.md §1
      # forbids, so an unexpected binary body surfaces as a decode failure.
      stub_post("v1/render/#{template_id}", "%PDF-1.4 fake", content_type: "application/pdf")

      expect { client.render(template_id, {}, persist: false) }
        .to raise_error(Pagr::PagrDecodeError)
    end

    it "targets a specific version path" do
      stub_post("v1/render/#{template_id}/versions/4", { "documents" => [rendered_document], "status" => "ok" })
      client.render(template_id, {}, version: 4)
      expect(
        a_request(:post, "#{BASE_URL}/v1/render/#{template_id}/versions/4").with(query: hash_including({}))
      ).to have_been_made
    end
  end

  describe "#render_batch" do
    it "correlates inputs to documents and issues by documentIndex" do
      stub_post("v1/render/#{template_id}", {
        "status" => "partial", "requestedCount" => 3, "renderedCount" => 2, "missingCount" => 1,
        "documents" => [rendered_document("documentName" => "A", "documentIndex" => 0),
                        rendered_document("documentName" => "C", "documentIndex" => 2)],
        "issues" => [issue("documentIndex" => 1, "severity" => "Error", "type" => "MissingBinding")],
      })

      result = client.render_batch(template_id, [{ "a" => 1 }, { "b" => 2 }, { "c" => 3 }])

      expect(result.size).to eq(3)
      expect(result[0]).to be_ok
      expect(result[0].document.document_name).to eq("A")
      expect(result[1]).not_to be_ok
      expect(result[1].issues.first.type).to eq(Pagr::RenderIssueType::MISSING_BINDING)
      expect(result[2].document.document_name).to eq("C")
      expect(result.succeeded.size).to eq(2)
      expect(result.failed.size).to eq(1)
      expect(result[0].input).to eq({ "a" => 1 })
    end
  end

  describe "#render_pdf" do
    it "requests Accept: application/pdf and parses X-Pagr-* metadata headers" do
      stub_request(:post, "#{BASE_URL}/v1/render/#{template_id}")
        .with(query: hash_including({}))
        .to_return(
          status: 200,
          body: "%PDF-1.4 fake",
          headers: {
            "Content-Type" => "application/pdf",
            "X-Pagr-Document-Id" => "11111111-1111-1111-1111-111111111111",
            "X-Pagr-Page-Count" => "2",
            "X-Pagr-Render-Duration-Ms" => "512.0",
            "X-Pagr-View-Url" => "https://app.pagr.test/documents/1",
            "X-Pagr-Issue-Count" => "0",
            "Content-Disposition" => 'attachment; filename="Invoice-001.pdf"',
          }
        )

      result = client.render_pdf(template_id, { "customer" => "Acme" })

      expect(result).to be_ok
      expect(result.document.document_name).to eq("Invoice-001")
      expect(result.document.document_id).to eq("11111111-1111-1111-1111-111111111111")
      expect(result.document.page_count).to eq(2)
      expect(result.document.to_bytes).to eq("%PDF-1.4 fake")
      expect(
        a_request(:post, "#{BASE_URL}/v1/render/#{template_id}")
          .with(query: hash_including({}), headers: { "Accept" => "application/pdf" })
      ).to have_been_made
    end

    it "returns a failed PdfRenderResult (not an exception) on HTTP 422" do
      stub_post("v1/render/#{template_id}",
                { "status" => "failed", "message" => "blocked",
                  "issues" => [issue("severity" => "Error")] },
                status: 422)

      result = client.render_pdf(template_id, { "customer" => "Acme" })

      expect(result).not_to be_ok
      expect(result.status).to eq("failed")
      expect(result.issues.first).to be_error
    end

    it "still raises ValidationFailedError from the plain #render path on the same 422" do
      stub_post("v1/render/#{template_id}", { "error" => { "code" => "X", "message" => "bad" } }, status: 422)
      expect { client.render(template_id, { "customer" => "Acme" }) }.to raise_error(Pagr::ValidationFailedError)
    end
  end

  describe "#enqueue_batch_render" do
    it "posts to the async path with a callback URL" do
      stub_post("v1/render/#{template_id}/async",
                { "jobId" => "job-1", "requestedCount" => 2, "state" => "queued" })

      job = client.enqueue_batch_render(template_id, [{ "a" => 1 }], "https://hooks.test/cb")

      expect(job.job_id).to eq("job-1")
      expect(job.requested_count).to eq(2)
      expect(job.state).to eq(Pagr::RenderJobState::QUEUED)
      expect(
        a_request(:post, "#{BASE_URL}/v1/render/#{template_id}/async")
          .with(query: hash_including({})) { |req| JSON.parse(req.body)["callbackUrl"] == "https://hooks.test/cb" }
      ).to have_been_made
    end
  end

  describe "#job_status" do
    it "returns the job's lifecycle state and outcome" do
      stub_get("v1/render/jobs/job-1",
               { "jobId" => "job-1", "state" => "completed", "status" => "ok",
                 "renderedCount" => 2, "requestedCount" => 2, "missingCount" => 0,
                 "startedAt" => "2026-01-01T00:00:00Z", "completedAt" => "2026-01-01T00:01:00Z" })
      status = client.job_status("job-1")
      expect(status).to be_done
      expect(status).to be_ok
      expect(status.state).to eq(Pagr::RenderJobState::COMPLETED)
      expect(status.status).to eq(Pagr::RenderOutcome::OK)
      expect(status.rendered_count).to eq(2)
    end
  end

  describe "#wait_for_job" do
    it "polls until the job is done, sleeping poll_interval between polls" do
      responses = [
        { "jobId" => "job-1", "state" => "pending", "startedAt" => "2026-01-01T00:00:00Z" },
        { "jobId" => "job-1", "state" => "completed", "status" => "ok",
          "startedAt" => "2026-01-01T00:00:00Z" },
      ]
      stub_request(:get, "#{BASE_URL}/v1/render/jobs/job-1")
        .to_return { { status: 200, body: JSON.generate(responses.shift) } }
      allow(client).to receive(:sleep)

      status = client.wait_for_job("job-1", poll_interval: 5)

      expect(status).to be_done
      expect(client).to have_received(:sleep).with(5).once
    end

    it "raises PagrTimeoutError once the deadline elapses" do
      stub_get("v1/render/jobs/job-1",
               { "jobId" => "job-1", "state" => "pending", "startedAt" => "2026-01-01T00:00:00Z" })
      allow(client).to receive(:sleep)
      allow(client).to receive(:monotonic_now).and_return(0, 0, 10)

      expect { client.wait_for_job("job-1", poll_interval: 1, timeout: 5) }
        .to raise_error(Pagr::PagrTimeoutError, /did not finish within 5s/)
    end

    it "defaults the deadline to 5 minutes and terminates rather than hanging when the job never finishes" do
      stub_get("v1/render/jobs/job-1",
               { "jobId" => "job-1", "state" => "pending", "startedAt" => "2026-01-01T00:00:00Z" })
      allow(client).to receive(:sleep)
      # Deadline calc, first remaining check, second remaining check that trips it —
      # a stubbed clock jump past DEFAULT_WAIT_FOR_JOB_TIMEOUT, not a real 5-minute wait.
      allow(client).to receive(:monotonic_now).and_return(0, 0, Pagr::Client::DEFAULT_WAIT_FOR_JOB_TIMEOUT + 1)

      expect { client.wait_for_job("job-1", poll_interval: 1) }
        .to raise_error(Pagr::PagrTimeoutError, /did not finish within #{Pagr::Client::DEFAULT_WAIT_FOR_JOB_TIMEOUT}s/)
    end

    it "treats an explicit timeout: nil as the default, not as arithmetic on nil" do
      # A caller passing through whatever their own config holds must not crash;
      # nil means "use the default", matching Python/C#/Java/TypeScript.
      stub_get("v1/render/jobs/job-1",
               { "jobId" => "job-1", "state" => "pending", "startedAt" => "2026-01-01T00:00:00Z" })
      allow(client).to receive(:sleep)
      allow(client).to receive(:monotonic_now).and_return(0, 0, Pagr::Client::DEFAULT_WAIT_FOR_JOB_TIMEOUT + 1)

      expect { client.wait_for_job("job-1", poll_interval: 1, timeout: nil) }
        .to raise_error(Pagr::PagrTimeoutError, /did not finish within #{Pagr::Client::DEFAULT_WAIT_FOR_JOB_TIMEOUT}s/)
    end

    it "opts out of the default deadline entirely with timeout: Float::INFINITY" do
      responses = [
        { "jobId" => "job-1", "state" => "pending", "startedAt" => "2026-01-01T00:00:00Z" },
        { "jobId" => "job-1", "state" => "completed", "status" => "ok",
          "startedAt" => "2026-01-01T00:00:00Z" },
      ]
      stub_request(:get, "#{BASE_URL}/v1/render/jobs/job-1")
        .to_return { { status: 200, body: JSON.generate(responses.shift) } }
      allow(client).to receive(:sleep)

      status = client.wait_for_job("job-1", poll_interval: 5, timeout: Float::INFINITY)

      expect(status).to be_done
      expect(client).to have_received(:sleep).with(5).once
    end

    it "returns the last polled (non-terminal) status promptly once cancelled fires, without waiting out poll_interval" do
      stub_get("v1/render/jobs/job-1",
               { "jobId" => "job-1", "state" => "pending", "startedAt" => "2026-01-01T00:00:00Z" })
      allow(client).to receive(:sleep)
      calls = 0
      cancelled = lambda do
        calls += 1
        calls > 3
      end

      status = client.wait_for_job("job-1", poll_interval: 2, cancelled: cancelled)

      expect(status).to be_a(Pagr::RenderJobStatus)
      expect(status).not_to be_done
      # Chunked into WAIT_FOR_JOB_CANCEL_CHECK_INTERVAL pieces, not a single
      # bare sleep(2) — cancellation is checked between chunks and cuts the
      # sleep short well before the full poll_interval elapses.
      expect(client).to have_received(:sleep)
        .with(Pagr::Client::WAIT_FOR_JOB_CANCEL_CHECK_INTERVAL).exactly(3).times
      expect(client).not_to have_received(:sleep).with(2)
      expect(a_request(:get, "#{BASE_URL}/v1/render/jobs/job-1")).to have_been_made.once
    end

    it "checks cancelled before sleeping at all, returning immediately if already cancelled" do
      stub_get("v1/render/jobs/job-1",
               { "jobId" => "job-1", "state" => "pending", "startedAt" => "2026-01-01T00:00:00Z" })
      allow(client).to receive(:sleep)

      status = client.wait_for_job("job-1", poll_interval: 2, cancelled: -> { true })

      expect(status).not_to be_done
      expect(client).not_to have_received(:sleep)
    end
  end

  describe "#validate" do
    it "expands an array into one document per element" do
      stub_post("v1/render/#{template_id}/validate", { "issues" => [] })
      client.validate(template_id, [{ "a" => 1 }, { "b" => 2 }])
      expect(
        a_request(:post, "#{BASE_URL}/v1/render/#{template_id}/validate")
          .with { |req| JSON.parse(req.body)["documents"].size == 2 }
      ).to have_been_made
    end

    it "treats a JSON string encoding an array as a batch" do
      stub_post("v1/render/#{template_id}/validate", { "issues" => [] })
      client.validate(template_id, "[{},{}]")
      expect(
        a_request(:post, "#{BASE_URL}/v1/render/#{template_id}/validate")
          .with { |req| JSON.parse(req.body)["documents"].size == 2 }
      ).to have_been_made
    end

    it "wraps a single document in a one-element list" do
      stub_post("v1/render/#{template_id}/validate",
                { "issues" => [issue("severity" => "Error")] })
      response = client.validate(template_id, { "a" => 1 })
      expect(response).not_to be_valid
      expect(response.errors.size).to eq(1)
      expect(
        a_request(:post, "#{BASE_URL}/v1/render/#{template_id}/validate")
          .with { |req| JSON.parse(req.body)["documents"].size == 1 }
      ).to have_been_made
    end
  end

  describe "#documents / #document / #download_document" do
    it "lists persisted documents" do
      stub_get("v1/documents", { "items" => [rendered_document.merge("isPdfDeleted" => false)], "total" => 1 })
      page = client.documents(sort_by: "renderedAt", sort_direction: "desc")
      expect(page.items.first).to be_a(Pagr::RenderDocument)
      expect(
        a_request(:get, "#{BASE_URL}/v1/documents")
          .with(query: hash_including("sortBy" => "renderedAt", "sortDirection" => "desc"))
      ).to have_been_made
    end

    it "downloads raw PDF bytes" do
      stub_get("v1/documents/abc/file", "PDFDATA", content_type: "application/pdf")
      expect(client.download_document("abc")).to eq("PDFDATA")
    end
  end

  describe "meta endpoints" do
    it "returns true from #status when healthy" do
      stub_get("v1/meta/status", "")
      expect(client.status).to be(true)
    end

    it "returns the deployed API version from #version" do
      stub_get("v1/meta/version", { "version" => "1.2.3" })
      expect(client.version).to eq("1.2.3")
    end

    it "lists font family names" do
      stub_get("v1/fonts", %w[Arial Helvetica])
      expect(client.fonts).to eq(%w[Arial Helvetica])
    end

    it "returns organisation stats" do
      stub_get("v1/organisation/stats",
               { "organisationName" => "Acme", "tier" => "pro", "pagesAvailable" => -1 })
      stats = client.org_stats
      expect(stats.organisation_name).to eq("Acme")
      expect(stats.pages_available).to eq(-1)
    end
  end
end
