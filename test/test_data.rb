# frozen_string_literal: true

require "test_helper"

class TestDataService < Minitest::Test
  LATEST_RESPONSE = {
    "assets" => { "BTC" => { "price" => 65000 } },
    "assetOrder" => ["BTC"],
    "market" => { "totalCap" => "2.5T" },
    "sources" => ["coinglass"],
    "meta" => { "ts" => "2026-03-09" }
  }.freeze

  TOKEN_RESPONSE = {
    "token" => "BTC",
    "composite" => { "score" => 72.5 },
    "spot" => { "price" => 65000 },
    "perps" => nil,
    "context" => {},
    "market" => {},
    "derivSymbols" => [],
    "hasDerivatives" => false,
    "sources" => ["coinglass"],
    "meta" => {},
    "requestId" => "req-tok-1",
    "mode" => "x402",
    "bundle" => { "bundleId" => "b-1", "remaining" => 42 },
    "includedPush" => { "used" => 5, "total" => 100, "remaining" => 95 }
  }.freeze

  PUSH_RESPONSE = {
    "requestId" => "req-push-1",
    "tokenId" => "ETH",
    "createdAt" => "2026-03-09T00:00:00Z",
    "data" => { "price" => 3500 }
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      uri = req[:uri]
      if uri.include?("/data/latest")
        Attago::Testing::MockResponse.new(code: 200, body: LATEST_RESPONSE)
      elsif uri.include?("/data/push/")
        Attago::Testing::MockResponse.new(code: 200, body: PUSH_RESPONSE)
      else
        Attago::Testing::MockResponse.new(code: 200, body: TOKEN_RESPONSE)
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @data = Attago::DataService.new(@client)
  end

  def test_get_latest_url
    @data.get_latest
    assert_includes @last_req[:uri], "/v1/data/latest"
    assert_equal "GET", @last_req[:method]
  end

  def test_get_latest_hydration
    result = @data.get_latest
    assert_instance_of Attago::DataLatestResponse, result
    assert_equal({ "BTC" => { "price" => 65000 } }, result.assets)
    assert_equal ["BTC"], result.asset_order
    assert_equal ["coinglass"], result.sources
  end

  def test_get_token_data_url
    @data.get_token_data("BTC/USDT")
    assert_includes @last_req[:uri], "/v1/api/data/BTC%2FUSDT"
    assert_equal "GET", @last_req[:method]
  end

  def test_get_token_data_hydration
    result = @data.get_token_data("BTC")
    assert_instance_of Attago::DataTokenResponse, result
    assert_equal "BTC", result.token
    assert_equal "x402", result.mode
    assert_instance_of Attago::BundleUsage, result.bundle
    assert_equal "b-1", result.bundle.bundle_id
    assert_equal 42, result.bundle.remaining
    assert_instance_of Attago::PushUsage, result.included_push
    assert_equal 95, result.included_push.remaining
  end

  def test_get_data_push_url
    @data.get_data_push("req-push-1")
    assert_includes @last_req[:uri], "/v1/data/push/req-push-1"
    assert_equal "GET", @last_req[:method]
  end

  def test_get_data_push_hydration
    result = @data.get_data_push("req-push-1")
    assert_instance_of Attago::DataPushResponse, result
    assert_equal "req-push-1", result.request_id
    assert_equal "ETH", result.token_id
    assert_equal "2026-03-09T00:00:00Z", result.created_at
    assert_equal({ "price" => 3500 }, result.data)
  end
end
