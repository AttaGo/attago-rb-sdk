# frozen_string_literal: true

require "openssl"
require "json"
require "securerandom"
require "time"
require "net/http"
require "uri"

module Attago
  class WebhookService
    def initialize(client)
      @client = client
    end

    # POST /webhooks
    def create(url)
      data = @client.request("POST", "/webhooks", body: { "url" => url })
      WebhookCreateResponse.from_hash(data)
    end

    # GET /webhooks
    def list
      data = @client.request("GET", "/webhooks")
      (data["webhooks"] || []).map { |w| WebhookListItem.from_hash(w) }
    end

    # DELETE /webhooks/{webhook_id}
    def delete(webhook_id)
      @client.request("DELETE", "/webhooks/#{webhook_id}")
      nil
    end

    # POST /webhooks/{webhook_id}/test (server-side)
    def send_server_test(webhook_id)
      data = @client.request("POST", "/webhooks/#{webhook_id}/test")
      WebhookTestResult.from_hash(data)
    end

    # SDK-side test delivery with retry backoff [1s, 4s, 16s]
    def send_test(opts)
      payload = Webhooks.build_test_payload(
        token: opts.token || "BTC",
        state: opts.state || "triggered",
        environment: opts.environment || "production"
      )
      body_str = JSON.generate(payload)
      signature = Webhooks.sign_payload(body_str, opts.secret)

      backoffs = opts.backoff_ms || [1000, 4000, 16000]
      max_attempts = backoffs.size + 1

      last_error = nil
      last_status = nil

      max_attempts.times do |attempt|
        begin
          uri = URI.parse(opts.url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          http.open_timeout = 5
          http.read_timeout = 10

          req = Net::HTTP::Post.new(uri.request_uri)
          req["Content-Type"] = "application/json"
          req["X-AttaGo-Signature"] = signature
          req.body = body_str

          resp = http.request(req)
          last_status = resp.code.to_i

          if last_status >= 200 && last_status < 300
            return WebhookTestResult.new(
              success: true,
              attempts: attempt + 1,
              status_code: last_status
            )
          end
          last_error = "HTTP #{last_status}"
        rescue StandardError => e
          last_error = e.message
        end

        # Wait before retry (skip after last attempt)
        sleep(backoffs[attempt] / 1000.0) if attempt < backoffs.size
      end

      WebhookTestResult.new(
        success: false,
        attempts: max_attempts,
        status_code: last_status,
        error: last_error
      )
    end
  end

  # Exported helper methods for webhook signing/verification
  module Webhooks
    module_function

    def build_test_payload(token: "BTC", state: "triggered", environment: "production", domain: "attago.bid")
      now = Time.now.utc.iso8601(3)
      sub_id = "sub_#{SecureRandom.hex(6)}"
      {
        "event" => "test",
        "version" => "2",
        "environment" => environment,
        "timestamp" => now,
        "alert" => {
          "id" => sub_id,
          "label" => "SDK Test \u2013 #{token}",
          "token" => token,
          "state" => state
        },
        "data" => {
          "url" => "https://#{domain}/v1/data/push/test_#{SecureRandom.hex(4)}",
          "expiresAt" => now,
          "fallbackUrl" => nil
        }
      }
    end

    def sign_payload(body, secret)
      body_bytes = body.is_a?(String) ? body : body.to_s
      OpenSSL::HMAC.hexdigest("SHA256", secret, body_bytes)
    end

    def verify_signature(body, secret, signature)
      expected = sign_payload(body, secret)
      # Timing-safe comparison (lesson from security audits)
      OpenSSL.fixed_length_secure_compare(expected, signature)
    rescue ArgumentError
      # fixed_length_secure_compare raises if lengths differ
      false
    end
  end
end
