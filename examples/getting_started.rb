# frozen_string_literal: true

require_relative "_env"

# Connect, check health, and list a few templates.
client = Example.client

puts "API healthy: #{client.status}"
puts "API version: #{client.version}"

page = client.templates(take: 5)
puts "#{page.total} template(s) total; showing #{page.size}:"
page.each { |template| puts "  - #{template.name} (#{template.id})" }
