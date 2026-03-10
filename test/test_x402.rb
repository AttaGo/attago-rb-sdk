# frozen_string_literal: true

require "test_helper"
require "base64"

class TestX402 < Minitest::Test
  def valid_payment_data
    {
      "x402Version" => 1,
      "resource" => {
        "url" => "https://api.attago.bid/v1/agent/score",
        "description" => "Score endpoint",
        "mimeType" => "application/json"
      },
      "accepts" => [
        {
          "scheme" => "exact",
          "network" => "eip155:8453",
          "amount" => "100000",
          "asset" => "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
          "payTo" => "0xabc123",
          "maxTimeoutSeconds" => 60,
          "extra" => { "name" => "USD Coin" }
        }
      ]
    }
  end

  def encoded_header
    Base64.strict_encode64(JSON.generate(valid_payment_data))
  end

  # ── parse_payment_required ──────────────────────────────────────────

  def test_parse_payment_required_valid
    resp = Attago::Testing::MockResponse.new(
      code: 402,
      body: "",
      headers: { "X-Payment" => encoded_header }
    )
    reqs = Attago::X402.parse_payment_required(resp)
    refute_nil reqs
    assert_equal 1, reqs.x402_version
    assert_equal "https://api.attago.bid/v1/agent/score", reqs.resource.url
    assert_equal 1, reqs.accepts.length
    assert_equal "eip155:8453", reqs.accepts[0].network
    assert_equal "100000", reqs.accepts[0].amount
  end

  def test_parse_payment_required_missing_header
    resp = Attago::Testing::MockResponse.new(code: 402, body: "", headers: {})
    reqs = Attago::X402.parse_payment_required(resp)
    assert_nil reqs
  end

  def test_parse_payment_required_invalid_base64
    resp = Attago::Testing::MockResponse.new(
      code: 402,
      body: "",
      headers: { "X-Payment" => "!!!not-base64!!!" }
    )
    reqs = Attago::X402.parse_payment_required(resp)
    assert_nil reqs
  end

  def test_parse_payment_required_urlsafe_base64
    urlsafe = Base64.urlsafe_encode64(JSON.generate(valid_payment_data))
    resp = Attago::Testing::MockResponse.new(
      code: 402,
      body: "",
      headers: { "X-Payment" => urlsafe }
    )
    reqs = Attago::X402.parse_payment_required(resp)
    refute_nil reqs
    assert_equal 1, reqs.x402_version
  end

  def test_parse_payment_required_invalid_json
    resp = Attago::Testing::MockResponse.new(
      code: 402,
      body: "",
      headers: { "X-Payment" => Base64.strict_encode64("not json") }
    )
    reqs = Attago::X402.parse_payment_required(resp)
    assert_nil reqs
  end

  def test_parse_payment_required_from_hash
    headers = { "x-payment" => encoded_header }
    reqs = Attago::X402.parse_payment_required(headers)
    refute_nil reqs
    assert_equal 1, reqs.x402_version
  end

  # ── filter_accepts_by_network ───────────────────────────────────────

  def test_filter_accepts_by_network_found
    accepts = valid_payment_data["accepts"].map { |a| Attago::X402AcceptedPayment.from_hash(a) }
    result = Attago::X402.filter_accepts_by_network(accepts, "eip155:8453")
    refute_nil result
    assert_equal "eip155:8453", result.network
  end

  def test_filter_accepts_by_network_not_found
    accepts = valid_payment_data["accepts"].map { |a| Attago::X402AcceptedPayment.from_hash(a) }
    result = Attago::X402.filter_accepts_by_network(accepts, "solana:devnet")
    assert_nil result
  end

  # ── do_with_x402 ───────────────────────────────────────────────────

  def test_do_with_x402_non_402_passes_through
    transport = Attago::Testing::MockTransport.new do |_req|
      Attago::Testing::MockResponse.new(code: 200, body: { "ok" => true })
    end

    signer = Struct.new(:address, :network).new("0xabc", "eip155:8453")

    resp = Attago::X402.do_with_x402(
      transport, signer, "GET", "https://api.attago.bid/v1/agent/score",
      headers: {}
    )
    assert_equal "200", resp.code
    assert_equal 1, transport.requests.length
  end

  def test_do_with_x402_auto_retry_on_402
    call_count = 0
    transport = Attago::Testing::MockTransport.new do |req|
      call_count += 1
      if call_count == 1
        Attago::Testing::MockResponse.new(
          code: 402,
          body: "",
          headers: { "X-Payment" => encoded_header }
        )
      else
        Attago::Testing::MockResponse.new(code: 200, body: { "ok" => true })
      end
    end

    signer = Struct.new(:address, :network) do
      define_method(:sign) { |_reqs| "signed-payment-token" }
    end.new("0xabc", "eip155:8453")

    resp = Attago::X402.do_with_x402(
      transport, signer, "GET", "https://api.attago.bid/v1/agent/score",
      headers: { "Accept" => "application/json" }
    )
    assert_equal "200", resp.code
    assert_equal 2, transport.requests.length
    # Verify the retry included the payment header
    assert_equal "signed-payment-token", transport.requests[1][:headers]["X-Payment"]
  end

  def test_do_with_x402_no_matching_network_raises
    transport = Attago::Testing::MockTransport.new do |_req|
      Attago::Testing::MockResponse.new(
        code: 402,
        body: "",
        headers: { "X-Payment" => encoded_header }
      )
    end

    signer = Struct.new(:address, :network).new("0xabc", "solana:devnet")

    assert_raises(Attago::PaymentRequiredError) do
      Attago::X402.do_with_x402(
        transport, signer, "GET", "https://api.attago.bid/v1/agent/score",
        headers: {}
      )
    end
  end
end
