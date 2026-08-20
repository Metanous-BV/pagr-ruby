# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "models" do
  describe Pagr::Common do
    it "parses a Z-suffixed timestamp to UTC" do
      time = Pagr::Common.parse_time("2026-01-15T10:30:00Z")
      expect(time).to be_utc
      expect([time.year, time.hour, time.min]).to eq([2026, 10, 30])
    end

    it "interprets an offset-less timestamp as UTC" do
      time = Pagr::Common.parse_time("2026-01-15T10:30:00")
      expect(time).to be_utc
      expect(time.hour).to eq(10)
    end

    it "converts a zoned timestamp to UTC" do
      time = Pagr::Common.parse_time("2026-01-15T12:30:00+02:00")
      expect(time).to be_utc
      expect(time.hour).to eq(10)
    end

    it "returns nil for missing or blank values" do
      expect(Pagr::Common.parse_time(nil)).to be_nil
      expect(Pagr::Common.parse_time("")).to be_nil
    end

    it "raises PagrDecodeError from parse_time! when the value is missing" do
      expect { Pagr::Common.parse_time!(nil) }.to raise_error(Pagr::PagrDecodeError)
    end

    it "raises PagrDecodeError from require when the key is absent" do
      expect { Pagr::Common.require({}, "jobId") }.to raise_error(Pagr::PagrDecodeError, /jobId/)
    end

    describe ".safe_filename" do
      {
        "../../etc/passwd" => "passwd",
        "..\\..\\Windows\\evil.exe" => "evil.exe",
        "C:\\evil" => "evil",
        "C:evil" => "evil",
        "/etc/passwd" => "passwd",
        "" => "document",
        "." => "document",
        ".." => "document",
        "foo/" => "document",
        "invoice.pdf" => "invoice.pdf",
      }.each do |input, expected|
        it "reduces #{input.inspect} to #{expected.inspect}" do
          expect(Pagr::Common.safe_filename(input)).to eq(expected)
        end
      end
    end
  end

  describe Pagr::RenderIssueSeverity do
    it "parses known values case-insensitively" do
      expect(described_class.from_api("Warning")).to eq(:warning)
      expect(described_class.from_api("error")).to eq(:error)
    end

    it "fails closed to :error on unknown or missing values" do
      expect(described_class.from_api("NewSeverity")).to eq(:error)
      expect(described_class.from_api(nil)).to eq(:error)
    end

    it "#at_least? orders :information < :warning < :error by explicit rank" do
      expect(described_class.at_least?(:error, :warning)).to be(true)
      expect(described_class.at_least?(:warning, :warning)).to be(true)
      expect(described_class.at_least?(:information, :warning)).to be(false)
      expect(described_class.at_least?(:warning, :error)).to be(false)
    end

    it "#blocking_production? is true for :warning/:error, false for :information" do
      expect(described_class.blocking_production?(:warning)).to be(true)
      expect(described_class.blocking_production?(:error)).to be(true)
      expect(described_class.blocking_production?(:information)).to be(false)
    end
  end

  describe Pagr::RenderIssueType do
    it "parses known values case-insensitively" do
      expect(described_class.from_api("RenderTimeout")).to eq(:render_timeout)
      expect(described_class.from_api("missingbinding")).to eq(:missing_binding)
    end

    it "fails open to :unknown on unknown or missing values" do
      expect(described_class.from_api("BrandNewIssue")).to eq(:unknown)
      expect(described_class.from_api(nil)).to eq(:unknown)
    end
  end

  describe Pagr::RenderJobState do
    it "parses known values case-insensitively" do
      expect(described_class.from_api("Completed")).to eq(:completed)
      expect(described_class.from_api("pending")).to eq(:pending)
    end

    it "fails open to :unknown on unknown or missing values" do
      expect(described_class.from_api("BrandNewState")).to eq(:unknown)
      expect(described_class.from_api(nil)).to eq(:unknown)
    end

    it "treats queued/pending as non-terminal and everything else (including :unknown) as terminal" do
      expect(described_class.terminal?(:queued)).to be(false)
      expect(described_class.terminal?(:pending)).to be(false)
      expect(described_class.terminal?(:completed)).to be(true)
      expect(described_class.terminal?(:failed)).to be(true)
      expect(described_class.terminal?(:unknown)).to be(true)
    end
  end

  describe Pagr::RenderOutcome do
    it "parses known values case-insensitively" do
      expect(described_class.from_api("Insufficient_Credit")).to eq(:insufficient_credit)
      expect(described_class.from_api("ok")).to eq(:ok)
    end

    it "fails open to :unknown on unknown or missing values" do
      expect(described_class.from_api("BrandNewOutcome")).to eq(:unknown)
      expect(described_class.from_api(nil)).to eq(:unknown)
    end
  end

  describe Pagr::Template do
    it "maps camelCase wire fields to snake_case attributes" do
      model = described_class.from_api(Fixtures.template)
      expect(model.name).to eq("Invoice")
      expect(model.document_name_template).to eq("Invoice-{{number}}")
      expect(model.latest_version_number).to eq(3)
      expect(model.version_count).to eq(5)
      expect(model.updated_at).to be_utc
    end
  end

  describe Pagr::TemplateVersion do
    it "parses the sampleData JSON string into a Hash" do
      model = described_class.from_api(
        "id" => "v", "versionNumber" => 1, "templateJson" => '{"root":1}',
        "sampleData" => '{"customer":"Acme"}', "documentNameTemplate" => nil,
        "publishedAt" => nil, "publishedBy" => nil, "templateId" => "t", "updatedAt" => nil
      )
      expect(model.template_json).to eq('{"root":1}')
      expect(model.sample_data).to eq({ "customer" => "Acme" })
    end

    it "defaults sampleData to an empty Hash when blank" do
      model = described_class.from_api(
        "id" => "v", "versionNumber" => 1, "templateJson" => "{}",
        "sampleData" => nil, "documentNameTemplate" => nil, "publishedAt" => nil,
        "publishedBy" => nil, "templateId" => "t", "updatedAt" => nil
      )
      expect(model.sample_data).to eq({})
    end

    # Parsing is lenient: sample data is authored content on the template, and a
    # broken one must not raise a non-Pagr::Error out of Client#template_version.
    [
      ["blank", "   "],
      ["malformed", "{not json"],
      ["a JSON array", "[1, 2]"],
      ["a JSON scalar", "42"],
      ["JSON null", "null"]
    ].each do |label, raw|
      it "decodes #{label} sampleData to an empty Hash" do
        model = described_class.from_api(
          "id" => "v", "versionNumber" => 1, "templateJson" => "{}",
          "sampleData" => raw, "documentNameTemplate" => nil, "publishedAt" => nil,
          "publishedBy" => nil, "templateId" => "t", "updatedAt" => nil
        )
        expect(model.sample_data).to eq({})
      end
    end
  end

  describe Pagr::RenderedDocument do
    it "has no raw-bytes factory — there is no way to fabricate a document" do
      # .from_pdf_bytes existed only to back #render's Content-Type sniff, and
      # filled template_id/view_url/environment with placeholders to do it,
      # which parity-contract.md §1 forbids. Both it and the sniff are gone.
      expect(described_class).not_to respond_to(:from_pdf_bytes)
    end

    it "carries the language variant the document was rendered in" do
      doc = described_class.from_api(Fixtures.rendered_document("language" => "nl-BE"))
      expect(doc.language).to eq("nl-BE")
    end

    it "leaves language nil when the template has no translations" do
      expect(described_class.from_api(Fixtures.rendered_document).language).to be_nil
    end

    it "raises when there is no inline content" do
      doc = described_class.from_api(Fixtures.rendered_document)
      expect { doc.to_bytes }.to raise_error(Pagr::Error, /no inline content/)
    end

    it "saves to a directory using document_name with a .pdf extension" do
      doc = described_class.from_api(Fixtures.rendered_document("documentBase64" => ["%PDF"].pack("m0")))
      Dir.mktmpdir do |dir|
        path = doc.save(dir)
        expect(File.basename(path)).to eq("Invoice-001.pdf")
        expect(File.binread(path)).to eq("%PDF")
      end
    end

    it "appends .pdf even when document_name already carries a different extension" do
      doc = described_class.from_api(
        Fixtures.rendered_document("documentName" => "invoice.docx", "documentBase64" => ["%PDF"].pack("m0"))
      )
      Dir.mktmpdir do |dir|
        path = doc.save(dir)
        expect(File.basename(path)).to eq("invoice.docx.pdf")
      end
    end

    it "sanitises a path-traversal document_name instead of writing outside the target directory" do
      doc = described_class.from_api(
        Fixtures.rendered_document("documentName" => "../../../../etc/passwd", "documentBase64" => ["%PDF"].pack("m0"))
      )
      Dir.mktmpdir do |dir|
        path = doc.save(dir)
        expect(File.dirname(path)).to eq(dir)
        expect(File.basename(path)).to eq("passwd.pdf")
      end
    end

    it "reads document_index, leaving it nil when the API omits it" do
      expect(described_class.from_api(Fixtures.rendered_document("documentIndex" => 3)).document_index).to eq(3)
      # Absent outside a render response (e.g. the document-listing endpoints).
      expect(described_class.from_api(Fixtures.rendered_document).document_index).to be_nil
    end
  end

  describe Pagr::BatchRenderResult do
    def doc(name, index)
      Fixtures.rendered_document("documentName" => name, "documentIndex" => index)
    end

    let(:inputs) { [{ "a" => 1 }, { "b" => 2 }, { "c" => 3 }] }

    it "places each document at the slot it reports via documentIndex" do
      # The documents arrive out of request order; each still lands on its own slot.
      result = described_class.from_api(
        { "status" => "ok", "requestedCount" => 3, "renderedCount" => 3, "missingCount" => 0,
          "documents" => [doc("Doc 2", 2), doc("Doc 0", 0), doc("Doc 1", 1)] },
        inputs: inputs
      )

      expect(result.map { |item| item.document.document_name }).to eq(["Doc 0", "Doc 1", "Doc 2"])
      expect(result.map { |item| item.document.document_index }).to eq([0, 1, 2])
      expect(result[0].input).to eq({ "a" => 1 })
    end

    it "keeps a document on its own slot when a warning-blocked input leaves a gap" do
      # Regression: a Warning-blocked document at index 1 renders nothing yet carries no
      # Error-severity issue, so nothing marks its slot failed. Positional filling slid
      # Doc 2 up into slot 1; index-based placement must keep it at slot 2.
      result = described_class.from_api(
        { "status" => "partial", "requestedCount" => 3, "renderedCount" => 2, "missingCount" => 1,
          "documents" => [doc("Doc 0", 0), doc("Doc 2", 2)],
          "issues" => [Fixtures.issue("severity" => "Warning", "documentIndex" => 1,
                                      "description" => "missing binding")] },
        inputs: inputs
      )

      expect(result[0].document.document_name).to eq("Doc 0")
      expect(result[1].document).to be_nil
      expect(result[1].issues.map(&:description)).to eq(["missing binding"])
      expect(result[2].document.document_name).to eq("Doc 2")
    end

    it "drops a document that carries no documentIndex" do
      # document_index is the only correlation: a document that omits it is dropped
      # rather than guessed onto a slot by position.
      result = described_class.from_api(
        { "status" => "ok", "requestedCount" => 2, "renderedCount" => 2, "missingCount" => 0,
          "documents" => [doc("Doc 0", 0), Fixtures.rendered_document("documentName" => "Doc 1")] },
        inputs: inputs.first(2)
      )

      expect(result[0].document.document_name).to eq("Doc 0")
      expect(result[1].document).to be_nil
      expect(result[1].issues.map(&:description)).to eq(["not rendered"])
    end

    it "drops rather than raising on an out-of-range documentIndex" do
      result = described_class.from_api(
        { "status" => "ok", "requestedCount" => 1, "renderedCount" => 1, "missingCount" => 0,
          "documents" => [doc("Doc 0", 7)] },
        inputs: [{ "a" => 1 }]
      )

      expect(result.size).to eq(1)
      expect(result[0].document).to be_nil
      expect(result[0].issues.map(&:description)).to eq(["not rendered"])
    end

    it "synthesises a 'not rendered' issue for a slot with neither a document nor a reason" do
      result = described_class.from_api(
        { "status" => "insufficient_credit", "message" => "out of credit",
          "requestedCount" => 3, "renderedCount" => 2, "missingCount" => 1,
          "documents" => [doc("Doc 0", 0), doc("Doc 1", 1)] },
        inputs: inputs
      )

      expect(result).to be_insufficient_credit
      expect(result).not_to be_ok
      expect(result[2]).not_to be_ok
      expect(result[2].issues.map(&:description)).to eq(["not rendered"])
      expect(result[2].issues.first.type).to eq(Pagr::RenderIssueType::UNKNOWN)
    end

    it "computes missing_count from the counts rather than trusting the response field" do
      # missingCount is by definition requestedCount - renderedCount, so a response that
      # disagrees with itself cannot report a short batch as ok.
      result = described_class.from_api(
        { "status" => "ok", "requestedCount" => 3, "renderedCount" => 2, "missingCount" => 0,
          "documents" => [doc("Doc 0", 0), doc("Doc 1", 1)] },
        inputs: inputs
      )

      expect(result.missing_count).to eq(1)
      expect(result).not_to be_ok
    end

    it "derives ok? from the counts, not from the items" do
      result = described_class.from_api(
        { "status" => "ok", "requestedCount" => 2, "renderedCount" => 2,
          "documents" => [doc("Doc 0", 0)] },
        inputs: inputs.first(2)
      )

      expect(result.missing_count).to eq(0)
      expect(result).to be_ok
      # the per-item view stays honest about the slot that carries no document
      expect(result.failed.map(&:index)).to eq([1])
    end
  end

  describe Pagr::PdfDocument do
    let(:headers) do
      {
        "X-Pagr-Document-Id" => "11111111-1111-1111-1111-111111111111",
        "X-Pagr-Page-Count" => "3",
        "X-Pagr-Render-Duration-Ms" => "128.5",
        "X-Pagr-View-Url" => "https://app.pagr.test/documents/1",
        "X-Pagr-Issue-Count" => "1",
        "Content-Disposition" => 'attachment; filename="Invoice-001.pdf"',
      }
    end

    it "builds from response headers plus the raw body" do
      doc = described_class.from_response(headers, "%PDF-bytes")
      expect(doc.document_name).to eq("Invoice-001")
      expect(doc.document_id).to eq("11111111-1111-1111-1111-111111111111")
      expect(doc.page_count).to eq(3)
      expect(doc.render_duration).to eq(128.5)
      expect(doc.issue_count).to eq(1)
      expect(doc.to_bytes).to eq("%PDF-bytes")
    end

    it "defaults document_id to nil and the name to 'document' when headers are absent" do
      doc = described_class.from_response({}, "%PDF-bytes")
      expect(doc.document_id).to be_nil
      expect(doc.document_name).to eq("document")
    end

    it "strips a trailing .pdf from the Content-Disposition filename, case-insensitively" do
      doc = described_class.from_response(headers.merge("Content-Disposition" => 'attachment; filename="Invoice-001.PDF"'), "%PDF-bytes")
      expect(doc.document_name).to eq("Invoice-001")
    end

    it "matches the filename marker case-insensitively (RFC 6266 parameter names)" do
      %w[filename Filename FILENAME fileName].each do |marker|
        doc = described_class.from_response(
          headers.merge("Content-Disposition" => %(attachment; #{marker}="Invoice-001.pdf")),
          "%PDF-bytes"
        )
        expect(doc.document_name).to eq("Invoice-001")
      end
    end

    it "falls back to 'document' when the filename is just '.pdf'" do
      doc = described_class.from_response(headers.merge("Content-Disposition" => 'attachment; filename=".pdf"'), "%PDF-bytes")
      expect(doc.document_name).to eq("document")
    end

    it "does not match the RFC 6266 extended filename*= form, matching Python's literal filename= search" do
      doc = described_class.from_response(headers.merge("Content-Disposition" => "attachment; filename*=UTF-8''Invoice-001.pdf"), "%PDF-bytes")
      expect(doc.document_name).to eq("document")
    end

    it "prefers the plain filename= parameter when both forms are present" do
      doc = described_class.from_response(headers.merge("Content-Disposition" => "attachment; filename=\"Invoice-001.pdf\"; filename*=UTF-8''Extended-Name.pdf"), "%PDF-bytes")
      expect(doc.document_name).to eq("Invoice-001")
    end

    it "sanitises a path-traversal filename on #save, like RenderedDocument" do
      doc = described_class.from_response(headers.merge("Content-Disposition" => 'attachment; filename="../evil.pdf"'), "%PDF")
      Dir.mktmpdir do |dir|
        path = doc.save(dir)
        expect(File.dirname(path)).to eq(dir)
        expect(File.basename(path)).to eq("evil.pdf")
      end
    end
  end

  describe Pagr::PdfRenderResult do
    it "builds a failed result from the 422 error envelope, as data not an exception" do
      result = described_class.from_error_envelope(
        "status" => "insufficient_credit", "message" => "out of credit", "issues" => []
      )
      expect(result).not_to be_ok
      expect(result).to be_insufficient_credit
      expect(result.message).to eq("out of credit")
    end
  end

  describe Pagr::PagedResult do
    it "reports #more? from skip + page size vs total" do
      page = described_class.from_api({ "items" => [1, 2], "total" => 10, "skip" => 0, "take" => 2 }) { |x| x }
      expect(page).to be_more
      expect(page.size).to eq(2)
    end

    it "is not #more? on the last page" do
      page = described_class.from_api({ "items" => [1], "total" => 3, "skip" => 2, "take" => 2 }) { |x| x }
      expect(page).not_to be_more
    end
  end

  describe Pagr::ValidationResponse do
    let(:response) do
      described_class.from_api(
        "issues" => [
          Fixtures.issue("severity" => "Error", "documentIndex" => 0),
          Fixtures.issue("severity" => "Warning", "documentIndex" => 1),
          Fixtures.issue("severity" => "Information", "documentIndex" => nil),
        ]
      )
    end

    it "is invalid when any issue is an error" do
      expect(response).not_to be_valid
      expect(response.errors.size).to eq(1)
      expect(response.warnings.size).to eq(1)
    end

    it "includes batch-wide issues for every document via #issues_for" do
      # document 1 gets its own Warning plus the nil-index Information issue
      expect(response.issues_for(1).size).to eq(2)
    end

    it "is valid when there are no issues" do
      empty = described_class.from_api("issues" => [])
      expect(empty).to be_valid
    end

    it "#to_s appends the indented issue list after the header, like the other SDKs" do
      text = response.to_s
      expect(text.lines.first).to eq("ValidationResponse (1 error(s), 1 warning(s))\n")
      expect(text.lines.length).to eq(4)  # header + one line per issue
      expect(text.lines[1..]).to all(start_with("  "))
    end

    it "#to_s is header-only when there are no issues" do
      expect(described_class.from_api("issues" => []).to_s).to eq("ValidationResponse (valid)")
    end

    it "is invalid when the only issue is Warning severity (the production gate)" do
      warning_only = described_class.from_api(
        "issues" => [Fixtures.issue("severity" => "Warning", "documentIndex" => 0)]
      )
      expect(warning_only).not_to be_valid
      expect(warning_only.errors).to be_empty
      expect(warning_only.warnings.size).to eq(1)
    end
  end

  describe Pagr::OrgStats do
    it "parses the full stats payload" do
      stats = described_class.from_api(
        "organisationName" => "Acme", "tier" => "pro",
        "periodStart" => "2026-01-01T00:00:00Z", "periodEnd" => "2026-02-01T00:00:00Z",
        "includedRendersPerMonth" => 1000, "pagesUsedThisPeriod" => 250,
        "pagesAvailable" => 750, "includedTokensPerMonth" => 5000,
        "tokensUsedThisPeriod" => 100, "tokensAvailable" => 4900, "userCount" => 4
      )
      expect(stats.organisation_name).to eq("Acme")
      expect(stats.pages_available).to eq(750)
      expect(stats.period_start).to eq(Time.utc(2026, 1, 1))
    end

    it "leaves every absent count nil rather than defaulting it to 0" do
      # An omitted field has to stay distinguishable from a genuine zero.
      stats = described_class.from_api({})
      expect(stats.included_renders_per_month).to be_nil
      expect(stats.pages_used_this_period).to be_nil
      expect(stats.pages_available).to be_nil
      expect(stats.included_tokens_per_month).to be_nil
      expect(stats.tokens_used_this_period).to be_nil
      expect(stats.tokens_available).to be_nil
      expect(stats.user_count).to be_nil
    end

    it "keeps a genuine zero distinct from an absent count" do
      stats = described_class.from_api("pagesUsedThisPeriod" => 0)
      expect(stats.pages_used_this_period).to eq(0)
      expect(stats.pages_available).to be_nil
    end
  end

  describe Pagr::RenderResult do
    it "reports insufficient credit as data, not an exception" do
      result = described_class.from_api("status" => "insufficient_credit", "documents" => [])
      expect(result).not_to be_ok
      expect(result).to be_insufficient_credit
    end
  end

  describe Pagr::RenderJob do
    it "reads requestedCount and state from the wire (not totalDocuments/status)" do
      job = described_class.from_api("jobId" => "job-1", "requestedCount" => 5, "state" => "queued")
      expect(job.requested_count).to eq(5)
      expect(job.state).to eq(Pagr::RenderJobState::QUEUED)
    end
  end

  describe Pagr::RenderJobStatus do
    def status_data(overrides = {})
      { "jobId" => "job-1", "state" => "pending", "startedAt" => "2026-01-01T00:00:00Z" }.merge(overrides)
    end

    it "keeps state (lifecycle) and status (outcome) separate" do
      status = described_class.from_api(status_data("state" => "completed", "status" => "ok"))
      expect(status.state).to eq(Pagr::RenderJobState::COMPLETED)
      expect(status.status).to eq(Pagr::RenderOutcome::OK)
    end

    it "leaves status nil while the job is pending and the API sends no status" do
      status = described_class.from_api(status_data)
      expect(status.status).to be_nil
    end

    it "raises PagrDecodeError when startedAt is missing" do
      expect { described_class.from_api("jobId" => "job-1", "state" => "pending") }
        .to raise_error(Pagr::PagrDecodeError)
    end

    it "is #done? (fail-open) for an unrecognised state, so a poll loop can never spin forever" do
      status = described_class.from_api(status_data("state" => "some_future_state"))
      expect(status.state).to eq(Pagr::RenderJobState::UNKNOWN)
      expect(status).to be_done
    end

    it "is not #done? while pending" do
      status = described_class.from_api(status_data)
      expect(status).not_to be_done
    end
  end
end
