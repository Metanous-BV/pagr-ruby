# frozen_string_literal: true

require_relative "_env"

# Render several documents in one request and save the successes.
client = Example.client

data_sets = [
  { "customer" => "Acme Corp", "total" => 100 },
  { "customer" => "Globex", "total" => 200 },
  { "customer" => "Initech", "total" => 300 },
]

batch = client.render_batch(Example.template_id, data_sets, include_document: true)

puts "Status: #{batch.status} (#{batch.succeeded.size}/#{batch.size} rendered)"
paths = batch.save_all("batch_out")
puts "Saved #{paths.size} PDF(s) to batch_out/"

batch.failed.each { |item| puts "Input #{item.index} failed: #{item}" }
