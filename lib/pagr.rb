# frozen_string_literal: true

# Pagr — a Ruby client for the Pagr Public API (+/v1+): templates and versions,
# document rendering (synchronous, or fire-and-forget jobs with
# webhook callbacks or polling), data validation, document browsing,
# organisation statistics, and webhook payload parsing and signature
# verification.
#
#   require "pagr"
#
#   client = Pagr::Client.new("pagr_test_...")   # or (key, base_url: "https://api.pagr.example")
#   result = client.render(template_id, { "customer" => "Acme" }, include_document: true)
#   result.document.save("invoice.pdf") if result.ok?
module Pagr
end

require_relative "pagr/version"
require_relative "pagr/errors"
require_relative "pagr/list_options"
require_relative "pagr/models/common"
require_relative "pagr/models/template"
require_relative "pagr/models/render"
require_relative "pagr/models/document"
require_relative "pagr/models/validation"
require_relative "pagr/models/organisation"
require_relative "pagr/webhook"
require_relative "pagr/http_transport"
require_relative "pagr/client"
