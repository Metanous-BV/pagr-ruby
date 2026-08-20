# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Pagr.parse_callback" do
  it "returns a RenderProgress when the payload carries a document" do
    payload = {
      "jobId" => "job-1",
      "processed" => 1,
      "requestedCount" => 4,
      "documentIndex" => 2,
      "document" => Fixtures.rendered_document,
    }

    callback = Pagr.parse_callback(payload)

    expect(callback).to be_a(Pagr::RenderProgress)
    expect(callback.processed).to eq(1)
    expect(callback.requested_count).to eq(4)
    expect(callback.document_index).to eq(2)
    expect(callback.progress_pct).to eq(25.0)
    expect(callback.document.document_name).to eq("Invoice-001")
  end

  it "returns a RenderCompletion when there is no document" do
    payload = {
      "jobId" => "job-1",
      "state" => "completed",
      "status" => "ok",
      "renderedCount" => 4,
      "requestedCount" => 4,
      "missingCount" => 0,
    }

    callback = Pagr.parse_callback(payload)

    expect(callback).to be_a(Pagr::RenderCompletion)
    expect(callback.state).to eq(Pagr::RenderJobState::COMPLETED)
    expect(callback).to be_ok
    expect(callback.rendered_count).to eq(4)
    expect(callback.missing_count).to eq(0)
  end

  it "flags an insufficient-credit completion" do
    callback = Pagr.parse_callback("jobId" => "job-1", "state" => "completed", "status" => "insufficient_credit")
    expect(callback).to be_insufficient_credit
    expect(callback).not_to be_ok
  end

  it "raises PagrDecodeError when the payload is not a JSON object" do
    expect { Pagr.parse_callback([1, 2, 3]) }.to raise_error(Pagr::PagrDecodeError, /must be a JSON object/)
  end

  it "raises PagrDecodeError when a progress-shaped payload is missing a required field" do
    payload = { "jobId" => "job-1", "document" => Fixtures.rendered_document }
    expect { Pagr.parse_callback(payload) }.to raise_error(Pagr::PagrDecodeError, /progress callback/)
  end

  it "raises PagrDecodeError when a completion-shaped payload is missing a required field" do
    expect { Pagr.parse_callback("jobId" => "job-1") }.to raise_error(Pagr::PagrDecodeError, /completion callback/)
  end
end
