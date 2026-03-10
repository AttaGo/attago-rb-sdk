# frozen_string_literal: true

require "test_helper"

class TestAgentService < Minitest::Test
  SCORE_RESPONSE = {
    "token" => "BTC",
    "composite" => { "score" => 72.5, "signal" => "bullish", "confidence" => 0.85 },
    "spot" => { "price" => 65000 },
    "perps" => nil,
    "context" => { "volatility" => "low" },
    "market" => { "cap" => "1.2T" },
    "derivSymbols" => ["BTCUSDT"],
    "hasDerivatives" => true,
    "sources" => ["coinglass"],
    "meta" => { "ts" => "2026-03-09" },
    "requestId" => "req-abc"
  }.freeze

  DATA_RESPONSE = {
    "assets" => { "BTC" => { "price" => 65000 }, "ETH" => { "price" => 3500 } },
    "assetOrder" => ["BTC", "ETH"],
    "market" => { "totalCap" => "2.5T" },
    "sources" => ["coinglass"],
    "meta" => { "ts" => "2026-03-09" },
    "requestId" => "req-xyz"
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      uri = req[:uri]
      if uri.include?("/agent/score")
        Attago::Testing::MockResponse.new(code: 200, body: SCORE_RESPONSE)
      else
        Attago::Testing::MockResponse.new(code: 200, body: DATA_RESPONSE)
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @agent = Attago::AgentService.new(@client)
  end

  def test_get_score_url_and_params
    @agent.get_score("BTC")
    assert_includes @last_req[:uri], "/v1/agent/score"
    assert_includes @last_req[:uri], "symbol=BTC"
    assert_equal "GET", @last_req[:method]
  end

  def test_get_score_hydration
    result = @agent.get_score("BTC")
    assert_instance_of Attago::AgentScoreResponse, result
    assert_equal "BTC", result.token
    assert_instance_of Attago::CompositeScore, result.composite
    assert_in_delta 72.5, result.composite.score, 0.01
    assert_equal "bullish", result.composite.signal
    assert_in_delta 0.85, result.composite.confidence, 0.01
    assert_equal true, result.has_derivatives
    assert_equal ["BTCUSDT"], result.deriv_symbols
    assert_equal "req-abc", result.request_id
  end

  def test_get_data_no_symbols
    @agent.get_data
    assert_includes @last_req[:uri], "/v1/agent/data"
    refute_includes @last_req[:uri], "symbols="
    assert_equal "GET", @last_req[:method]
  end

  def test_get_data_with_symbols
    @agent.get_data("BTC", "ETH")
    assert_includes @last_req[:uri], "/v1/agent/data"
    assert_includes @last_req[:uri], "symbols=BTC%2CETH"
    assert_equal "GET", @last_req[:method]
  end

  def test_get_data_hydration
    result = @agent.get_data("BTC", "ETH")
    assert_instance_of Attago::AgentDataResponse, result
    assert_equal({ "BTC" => { "price" => 65000 }, "ETH" => { "price" => 3500 } }, result.assets)
    assert_equal ["BTC", "ETH"], result.asset_order
    assert_equal "req-xyz", result.request_id
  end
end
