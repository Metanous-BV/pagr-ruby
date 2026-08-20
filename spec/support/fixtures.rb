# frozen_string_literal: true

# Wire-shaped fixture builders (camelCase, as the API sends). Mirrors the
# reference SDK's conftest `make_doc` helper.
module Fixtures
  module_function

  # A RenderedDocument wire Hash. Pass overrides to change individual fields.
  def rendered_document(overrides = {})
    {
      "id" => "11111111-1111-1111-1111-111111111111",
      "documentName" => "Invoice-001",
      "templateId" => "22222222-2222-2222-2222-222222222222",
      "versionNumber" => 3,
      "environment" => "test",
      "fileSizeBytes" => 2048,
      "pageCount" => 2,
      "renderedAt" => "2026-01-15T10:30:00Z",
      "renderDuration" => 512.0,
      "viewUrl" => "https://app.pagr.test/documents/1",
      "documentType" => "Template",
    }.merge(overrides)
  end

  # A RenderIssue wire Hash.
  def issue(overrides = {})
    {
      "type" => "MissingBinding",
      "severity" => "Error",
      "description" => "Missing binding for field 'total'.",
      "elementId" => "field-total",
      "documentIndex" => 0,
    }.merge(overrides)
  end

  # A Template wire Hash.
  def template(overrides = {})
    {
      "id" => "22222222-2222-2222-2222-222222222222",
      "name" => "Invoice",
      "documentNameTemplate" => "Invoice-{{number}}",
      "projectId" => "33333333-3333-3333-3333-333333333333",
      "projectName" => "Billing",
      "latestVersionNumber" => 3,
      "versionCount" => 5,
      "updatedAt" => "2026-01-10T09:00:00Z",
      "updatedBy" => "alice@example.com",
    }.merge(overrides)
  end
end
