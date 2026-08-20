# frozen_string_literal: true

require_relative "_env"

# Validate data against a template without rendering (consumes no credit).
client = Example.client

response = client.validate(Example.template_id, [
  { "customer" => "Acme" },     # possibly missing bindings
  { "customer" => "Globex", "total" => 200 },
])

if response.valid?
  puts "All documents are valid."
else
  puts "#{response.errors.size} blocking error(s):"
  response.each { |issue| puts "  [doc #{issue.document_index}] #{issue}" }
end
