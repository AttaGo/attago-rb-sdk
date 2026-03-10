# frozen_string_literal: true

require "test_helper"
require "base64"

class TestClient < Minitest::Test
  def make_transport(code: 200, body: {}, headers: {})
    Attago::Testing::MockTransport.new do |_req|
      Attago::Testing::MockResponse.new(code: code, body: body, headers: headers)
    end
  end

  def make_client(transport:, **opts)
    Attago::Client.new(transport: transport, **opts)
  end

  # ── Constructor ─────────────────────────────────────────────────────

  def test_default_base_url
    t = make_transport
    client = make_client(transport: t)
    assert_equal "https://api.attago.bid", client.base_url
  end

  def test_custom_base_url
    t = make_transport
    client = make_client(transport: t, base_url: "https://custom.example.com/")
    assert_equal "https://custom.example.com", client.base_url
  end

  def test_multiple_auth_modes_raises_config_error
    t = make_transport
    assert_raises(Attago::ConfigError) do
      Attago::Client.new(api_key: "key", signer: Object.new, transport: t)
    end
  end

  def test_cognito_without_client_id_raises
    t = make_transport
    assert_raises(Attago::ConfigError) do
      Attago::Client.new(email: "a@b.com", password: "pass", transport: t)
    end
  end

  # ── Request path handling ───────────────────────────────────────────

  def test_v1_prefix_added
    t = make_transport
    client = make_client(transport: t)
    client.request("GET", "/agent/score")
    assert_includes t.last_request[:uri], "/v1/agent/score"
  end

  def test_v1_prefix_preserved
    t = make_transport
    client = make_client(transport: t)
    client.request("GET", "/v1/agent/score")
    assert_includes t.last_request[:uri], "/v1/agent/score"
    # Should NOT double-prefix
    refute_includes t.last_request[:uri], "/v1/v1/"
  end

  # ── Headers ─────────────────────────────────────────────────────────

  def test_api_key_header_sent
    t = make_transport
    client = make_client(transport: t, api_key: "test-key-123")
    client.request("GET", "/agent/score")
    assert_equal "test-key-123", t.last_request[:headers]["X-API-Key"]
  end

  def test_user_agent_header
    t = make_transport
    client = make_client(transport: t)
    client.request("GET", "/agent/score")
    assert_equal "attago-ruby/#{Attago::VERSION}", t.last_request[:headers]["User-Agent"]
  end

  def test_auth_headers_api_key
    t = make_transport
    client = make_client(transport: t, api_key: "mykey")
    headers = client.auth_headers
    assert_equal "mykey", headers["X-API-Key"]
  end

  def test_auth_headers_empty_when_no_auth
    t = make_transport
    client = make_client(transport: t)
    headers = client.auth_headers
    assert_empty headers
  end

  # ── Body & params ───────────────────────────────────────────────────

  def test_json_body_sent
    t = make_transport
    client = make_client(transport: t)
    client.request("POST", "/subscriptions", body: { "token_id" => "BTC" })
    sent_body = JSON.parse(t.last_request[:body])
    assert_equal "BTC", sent_body["token_id"]
  end

  def test_query_params
    t = make_transport
    client = make_client(transport: t)
    client.request("GET", "/agent/score", params: { "token" => "ETH" })
    assert_includes t.last_request[:uri], "token=ETH"
  end

  # ── Response handling ───────────────────────────────────────────────

  def test_204_returns_nil
    t = make_transport(code: 204, body: nil)
    client = make_client(transport: t)
    result = client.request("DELETE", "/webhooks/wh-1")
    assert_nil result
  end

  def test_200_returns_parsed_json
    t = make_transport(code: 200, body: { "token" => "BTC", "score" => 75 })
    client = make_client(transport: t)
    result = client.request("GET", "/agent/score")
    assert_equal "BTC", result["token"]
    assert_equal 75, result["score"]
  end

  # ── Error handling ──────────────────────────────────────────────────

  def test_404_raises_api_error
    t = make_transport(code: 404, body: { "message" => "Not Found" })
    client = make_client(transport: t)
    err = assert_raises(Attago::ApiError) { client.request("GET", "/missing") }
    assert_equal 404, err.status_code
    assert_includes err.message, "Not Found"
  end

  def test_500_raises_api_error
    t = make_transport(code: 500, body: { "error" => "Internal Server Error" })
    client = make_client(transport: t)
    err = assert_raises(Attago::ApiError) { client.request("GET", "/broken") }
    assert_equal 500, err.status_code
  end

  def test_429_raises_rate_limit_error
    t = make_transport(
      code: 429,
      body: { "message" => "Too Many Requests" },
      headers: { "Retry-After" => "30" }
    )
    client = make_client(transport: t)
    err = assert_raises(Attago::RateLimitError) { client.request("GET", "/score") }
    assert_equal 429, err.status_code
    assert_equal 30, err.retry_after
  end

  def test_402_raises_payment_required_error
    payment_data = {
      "x402Version" => 1,
      "resource" => { "url" => "/score", "description" => "Score", "mimeType" => "application/json" },
      "accepts" => [{ "scheme" => "exact", "network" => "eip155:8453", "amount" => "100000",
                       "asset" => "0xUSDC", "payTo" => "0xpay", "maxTimeoutSeconds" => 60 }]
    }
    encoded = Base64.strict_encode64(JSON.generate(payment_data))
    t = make_transport(
      code: 402,
      body: { "message" => "Payment Required" },
      headers: { "X-Payment" => encoded }
    )
    client = make_client(transport: t)
    err = assert_raises(Attago::PaymentRequiredError) { client.request("GET", "/score") }
    assert_equal 402, err.status_code
    refute_nil err.payment_requirements
  end

  def test_error_with_unparseable_body
    t = Attago::Testing::MockTransport.new do |_req|
      Attago::Testing::MockResponse.new(code: 500, body: "not json", headers: {})
    end
    client = make_client(transport: t)
    err = assert_raises(Attago::ApiError) { client.request("GET", "/fail") }
    assert_equal 500, err.status_code
    assert_includes err.message, "Request failed"
  end

  # ── close ───────────────────────────────────────────────────────────

  def test_close_no_crash
    t = make_transport
    client = make_client(transport: t)
    client.close  # Should not raise
  end
end
