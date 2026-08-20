# frozen_string_literal: true

require_relative "_env"

# Render one document and save the PDF.
client = Example.client

result = client.render(
  Example.template_id,
  { "customer" => "Acme Corp", "total" => 1234.56 },
  include_document: true
)

if result.ok?
  path = result.document.save("render_single.pdf")
  puts "Saved #{result.document.page_count}-page PDF to #{path}"
else
  puts "Render failed (#{result.status}):"
  result.issues.each { |issue| puts "  #{issue}" }
end
