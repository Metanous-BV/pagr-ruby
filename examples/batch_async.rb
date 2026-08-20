# frozen_string_literal: true

require_relative "_env"

# Enqueue a fire-and-forget batch render and poll it to completion. (A webhook
# callback is the push-based alternative — see Pagr.parse_signed_callback,
# which verifies the X-Pagr-Signature header before parsing the body.)
client = Example.client

data_sets = Array.new(5) { |i| { "customer" => "Customer #{i}" } }

# The callback URL must be reachable by the Pagr server. Polling below does not
# depend on it being delivered.
job = client.enqueue_batch_render(
  Example.template_id, data_sets, "https://example.test/pagr/callback"
)
puts "Enqueued job #{job.job_id} (#{job.requested_count} documents, state=#{job.state})"

# wait_for_job is a convenience wrapper over polling job_status yourself.
status = client.wait_for_job(job.job_id, poll_interval: 1, timeout: 120)
puts status.ok? ? "Completed." : "Failed: #{status.failure_reason}"
