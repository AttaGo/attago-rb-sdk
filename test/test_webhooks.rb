# frozen_string_literal: true

require "test_helper"

class TestWebhookHMAC < Minitest::Test
  SECRET = "whsec_test_secret_abc123"
  BODY = '{"event":"test","version":"2"}'

  def test_sign_payload_hex_digest
    sig = Attago::Webhooks.sign_payload(BODY, SECRET)
    # Must be a 64-char lowercase hex string (SHA-256)
    assert_match(/\A[0-9a-f]{64}\z/, sig)
    # Deterministic: same input always produces the same output
    assert_equal sig, Attago::Webhooks.sign_payload(BODY, SECRET)
  end

  def test_verify_signature_correct
    sig = Attago::Webhooks.sign_payload(BODY, SECRET)
    assert Attago::Webhooks.verify_signature(BODY, SECRET, sig)
  end

  def test_verify_signature_wrong_secret
    sig = Attago::Webhooks.sign_payload(BODY, SECRET)
    refute Attago::Webhooks.verify_signature(BODY, "wrong_secret", sig)
  end

  def test_verify_signature_tampered_body
    sig = Attago::Webhooks.sign_payload(BODY, SECRET)
    refute Attago::Webhooks.verify_signature('{"event":"alert"}', SECRET, sig)
  end

  def test_verify_signature_missing
    refute Attago::Webhooks.verify_signature(BODY, SECRET, "")
  end

  def test_verify_timing_safe
    # OpenSSL.fixed_length_secure_compare raises ArgumentError when lengths differ,
    # which our wrapper catches and returns false
    refute Attago::Webhooks.verify_signature(BODY, SECRET, "short")
    refute Attago::Webhooks.verify_signature(BODY, SECRET, "a" * 100)
  end

  def test_build_test_payload_structure
    payload = Attago::Webhooks.build_test_payload
    assert_equal "test", payload["event"]
    assert_equal "2", payload["version"]
    assert payload.key?("timestamp")
    assert payload.key?("alert")
    assert payload.key?("data")
    assert payload["alert"].key?("id")
    assert payload["alert"].key?("label")
    assert payload["alert"].key?("token")
    assert payload["alert"].key?("state")
    assert payload["data"].key?("url")
    assert payload["data"].key?("expiresAt")
    assert payload["data"].key?("fallbackUrl")
  end

  def test_build_test_payload_defaults
    payload = Attago::Webhooks.build_test_payload
    assert_equal "BTC", payload["alert"]["token"]
    assert_equal "triggered", payload["alert"]["state"]
    assert_equal "production", payload["environment"]
  end

  def test_build_test_payload_custom_token
    payload = Attago::Webhooks.build_test_payload(token: "ETH", state: "cleared", environment: "staging")
    assert_equal "ETH", payload["alert"]["token"]
    assert_equal "cleared", payload["alert"]["state"]
    assert_equal "staging", payload["environment"]
  end
end

class TestWebhookService < Minitest::Test
  CREATE_RESPONSE = {
    "webhookId" => "wh-1",
    "url" => "https://example.com/hook",
    "secret" => "whsec_abc123",
    "createdAt" => "2026-03-09T00:00:00Z"
  }.freeze

  LIST_RESPONSE = {
    "webhooks" => [{
      "webhookId" => "wh-1",
      "url" => "https://example.com/hook",
      "createdAt" => "2026-03-09T00:00:00Z"
    }]
  }.freeze

  TEST_RESPONSE = {
    "success" => true,
    "attempts" => 1,
    "statusCode" => 200
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      uri = req[:uri]
      if req[:method] == "DELETE"
        Attago::Testing::MockResponse.new(code: 204, body: nil)
      elsif uri.include?("/test")
        Attago::Testing::MockResponse.new(code: 200, body: TEST_RESPONSE)
      elsif req[:method] == "POST"
        Attago::Testing::MockResponse.new(code: 200, body: CREATE_RESPONSE)
      else
        Attago::Testing::MockResponse.new(code: 200, body: LIST_RESPONSE)
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @svc = Attago::WebhookService.new(@client)
  end

  def test_webhook_create
    result = @svc.create("https://example.com/hook")
    assert_includes @last_req[:uri], "/v1/user/webhooks"
    assert_equal "POST", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal "https://example.com/hook", sent["url"]
    assert_instance_of Attago::WebhookCreateResponse, result
    assert_equal "wh-1", result.webhook_id
    assert_equal "whsec_abc123", result.secret
  end

  def test_webhook_list
    result = @svc.list
    assert_includes @last_req[:uri], "/v1/user/webhooks"
    assert_equal "GET", @last_req[:method]
    assert_equal 1, result.size
    assert_instance_of Attago::WebhookListItem, result.first
    assert_equal "wh-1", result.first.webhook_id
  end

  def test_webhook_delete
    result = @svc.delete("wh-1")
    assert_includes @last_req[:uri], "/v1/user/webhooks/wh-1"
    assert_equal "DELETE", @last_req[:method]
    assert_nil result
  end

  def test_webhook_send_server_test
    result = @svc.send_server_test("wh-1")
    assert_includes @last_req[:uri], "/v1/user/webhooks/wh-1/test"
    assert_equal "POST", @last_req[:method]
    assert_instance_of Attago::WebhookTestResult, result
    assert_equal true, result.success
    assert_equal 1, result.attempts
  end

  def test_webhook_create_response_inspect_redacted
    result = @svc.create("https://example.com/hook")
    inspect_str = result.inspect
    assert_includes inspect_str, 'secret="***"'
    refute_includes inspect_str, "whsec_abc123"
  end

  def test_send_test_success
    # Start a tiny WEBrick server to receive the test delivery
    require "webrick"

    received_body = nil
    received_sig = nil

    server = WEBrick::HTTPServer.new(
      Port: 0,
      BindAddress: "127.0.0.1",
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: []
    )

    server.mount_proc("/hook") do |req, res|
      received_body = req.body
      received_sig = req["X-AttaGo-Signature"]
      res.status = 200
      res.body = '{"ok":true}'
    end

    thread = Thread.new { server.start }
    sleep 0.1

    port = server.config[:Port]
    secret = "test_secret_xyz"
    opts = Attago::SendTestOptions.new(
      url: "http://127.0.0.1:#{port}/hook",
      secret: secret,
      token: "BTC",
      backoff_ms: [10, 20, 40]  # fast backoffs for testing
    )

    result = @svc.send_test(opts)

    assert_equal true, result.success
    assert_equal 1, result.attempts
    assert_equal 200, result.status_code

    # Verify HMAC was correct
    assert Attago::Webhooks.verify_signature(received_body, secret, received_sig)
  ensure
    server&.shutdown
    thread&.join(2)
  end
end
