# frozen_string_literal: true

require_relative "_env"

# Render one document and get the raw PDF bytes back, instead of the JSON
# envelope render() returns. The API streams application/pdf directly and
# carries the document metadata in X-Pagr-* response headers, so there is no
# base64 field to decode.
#
# Raw-PDF rendering is single-document only — a batch is rejected before any
# credit is charged.
client = Example.client

result = client.render_pdf(
  Example.template_id,
  { "customer" => "Acme Corp", "total" => 1234.56 }
)

# A blocked or failed render has no PDF to stream, so it comes back as a
# business outcome (ok? == false) rather than an exception.
if result.ok?
  doc = result.document
  path = doc.save("render_pdf.pdf")
  puts "Saved #{doc.page_count}-page PDF (#{doc.to_bytes.bytesize} bytes) to #{path}"
  puts "Rendered in #{doc.render_duration} ms; view at #{doc.view_url}" if doc.view_url
else
  puts "Render failed (#{result.status}): #{result.message}"
  result.issues.each { |issue| puts "  #{issue}" }
end
