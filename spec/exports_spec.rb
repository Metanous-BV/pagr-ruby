# frozen_string_literal: true

# Guards that the documented public surface is actually reachable after a plain
# `require "pagr"`. Catches the case where a class is added or renamed without
# updating the matching `require_relative` in lib/pagr.rb — the whole file loads
# fine, and the constant is simply missing at runtime.
RSpec.describe "Pagr public exports" do
  client_and_errors = %i[
    Client
    Error ApiError AuthenticationError ForbiddenError NotFoundError
    PayloadTooLargeError RateLimitError ValidationFailedError
    PagrConnectionError PagrDecodeError PagrSignatureError PagrTimeoutError
    STATUS_ERRORS
  ]

  models = %i[
    Template TemplateVersion
    RenderResult RenderedDocument RenderIssue
    PdfRenderResult PdfDocument
    BatchRenderResult BatchItem
    RenderJob RenderCompletion RenderOutcome RenderProgress
    RenderDocument PagedResult
    ValidationResponse OrgStats
  ]

  enums = %i[RenderIssueSeverity RenderIssueType RenderJobState RenderJobStatus FilterOp]

  listing = %i[Filter Filters]

  webhook_constants = %i[
    SIGNATURE_HEADER EVENT_HEADER DELIVERY_HEADER DEFAULT_SIGNATURE_TOLERANCE
  ]

  module_functions = %i[verify_signature parse_signed_callback parse_callback build_list_query]

  (client_and_errors + models + enums + listing + webhook_constants).each do |name|
    it "exports Pagr::#{name}" do
      expect(Pagr.const_defined?(name, false)).to be(true),
                                                  "Pagr::#{name} is documented but not defined — " \
                                                  "is a require_relative missing from lib/pagr.rb?"
    end
  end

  module_functions.each do |name|
    it "exports Pagr.#{name}" do
      expect(Pagr).to respond_to(name)
    end
  end

  it "reports the gem version" do
    expect(Pagr::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "defaults to the hosted Pagr API" do
    expect(Pagr::Client::DEFAULT_BASE_URL).to eq("https://api.pagr.eu")
  end

  it "every error class is a Pagr::Error, so rescue Pagr::Error is a complete net" do
    error_classes = (client_and_errors - %i[Client STATUS_ERRORS Error]).map { |n| Pagr.const_get(n) }
    expect(error_classes).to all(be < Pagr::Error)
  end

  it "maps every status in STATUS_ERRORS to a Pagr::Error subclass" do
    expect(Pagr::STATUS_ERRORS.values).to all(be < Pagr::Error)
  end
end
