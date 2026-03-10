# frozen_string_literal: true

require "test_helper"

class TestSubscriptionService < Minitest::Test
  CATALOG_RESPONSE = {
    "tokens" => ["BTC", "ETH"],
    "metrics" => {
      "price" => { "label" => "Price", "type" => "number", "operators" => ["gt", "lt"], "unit" => "USD", "min" => 0, "max" => nil, "values" => nil }
    },
    "tier" => "pro",
    "maxSubscriptions" => 50,
    "mode" => "live"
  }.freeze

  SUB_RESPONSE = {
    "userId" => "u-1",
    "subId" => "sub-1",
    "tokenId" => "BTC",
    "label" => "BTC price alert",
    "groups" => [[{ "metricName" => "price", "thresholdOp" => "gt", "thresholdVal" => 70000 }]],
    "cooldownMinutes" => 10,
    "bucketHash" => "abc123",
    "isActive" => true,
    "createdAt" => "2026-03-09T00:00:00Z",
    "updatedAt" => "2026-03-09T00:00:00Z",
    "activeTokenShard" => "BTC#3"
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      uri = req[:uri]
      if uri.include?("/subscriptions/catalog")
        Attago::Testing::MockResponse.new(code: 200, body: CATALOG_RESPONSE)
      elsif req[:method] == "DELETE"
        Attago::Testing::MockResponse.new(code: 204, body: nil)
      elsif uri.include?("/subscriptions")
        if req[:method] == "GET"
          Attago::Testing::MockResponse.new(code: 200, body: { "subscriptions" => [SUB_RESPONSE] })
        else
          Attago::Testing::MockResponse.new(code: 200, body: SUB_RESPONSE)
        end
      else
        Attago::Testing::MockResponse.new(code: 200, body: {})
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @svc = Attago::SubscriptionService.new(@client)
  end

  def test_catalog
    result = @svc.catalog
    assert_instance_of Attago::CatalogResponse, result
    assert_includes @last_req[:uri], "/v1/subscriptions/catalog"
    assert_equal "GET", @last_req[:method]
    assert_equal ["BTC", "ETH"], result.tokens
    assert_equal "pro", result.tier
    assert_instance_of Attago::CatalogMetric, result.metrics["price"]
    assert_equal "Price", result.metrics["price"].label
  end

  def test_list
    result = @svc.list
    assert_includes @last_req[:uri], "/v1/user/subscriptions"
    assert_equal "GET", @last_req[:method]
    assert_equal 1, result.size
    assert_instance_of Attago::Subscription, result.first
    assert_equal "sub-1", result.first.sub_id
  end

  def test_create
    input = Attago::CreateSubscriptionInput.new(
      token_id: "BTC",
      label: "My alert",
      groups: [[Attago::SubscriptionCondition.new(metric_name: "price", threshold_op: "gt", threshold_val: 70000)]],
      cooldown_minutes: 15
    )
    result = @svc.create(input)
    assert_includes @last_req[:uri], "/v1/user/subscriptions"
    assert_equal "POST", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal "BTC", sent["tokenId"]
    assert_equal "My alert", sent["label"]
    assert_equal 15, sent["cooldownMinutes"]
    assert_equal "price", sent["groups"][0][0]["metricName"]
    assert_instance_of Attago::Subscription, result
  end

  def test_update
    input = Attago::UpdateSubscriptionInput.new(label: "Updated", is_active: false)
    result = @svc.update("sub-1", input)
    assert_includes @last_req[:uri], "/v1/user/subscriptions/sub-1"
    assert_equal "PUT", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal "Updated", sent["label"]
    assert_equal false, sent["isActive"]
    assert_instance_of Attago::Subscription, result
  end

  def test_delete
    result = @svc.delete("sub-1")
    assert_includes @last_req[:uri], "/v1/user/subscriptions/sub-1"
    assert_equal "DELETE", @last_req[:method]
    assert_nil result
  end
end

class TestPaymentService < Minitest::Test
  SUBSCRIBE_RESPONSE = {
    "tier" => "pro",
    "billingCycle" => "monthly",
    "price" => 29.99,
    "currency" => "USDC",
    "expiresAt" => "2026-04-09T00:00:00Z",
    "payer" => "0xabc",
    "mode" => "testnet",
    "message" => "Subscribed"
  }.freeze

  STATUS_RESPONSE = {
    "tier" => "pro",
    "tierName" => "Pro",
    "billingCycle" => "monthly",
    "maxSubs" => 50,
    "apiAccess" => true,
    "freeDataPushes" => 100,
    "mode" => "testnet",
    "expiresAt" => "2026-04-09T00:00:00Z",
    "includedPushes" => { "total" => 100, "used" => 5, "remaining" => 95, "periodStart" => "2026-03-09", "periodEnd" => "2026-04-09" }
  }.freeze

  QUOTE_RESPONSE = {
    "currentTier" => "basic",
    "currentCycle" => "monthly",
    "currentExpiresAt" => "2026-04-01",
    "targetTier" => "pro",
    "targetCycle" => "monthly",
    "basePrice" => 29.99,
    "prorationCredit" => 5.0,
    "finalPrice" => 24.99,
    "currency" => "USDC",
    "expiresAt" => "2026-04-09"
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      uri = req[:uri]
      if uri.include?("/payments/subscribe")
        Attago::Testing::MockResponse.new(code: 200, body: SUBSCRIBE_RESPONSE)
      elsif uri.include?("/payments/upgrade-quote")
        Attago::Testing::MockResponse.new(code: 200, body: QUOTE_RESPONSE)
      else
        Attago::Testing::MockResponse.new(code: 200, body: STATUS_RESPONSE)
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @svc = Attago::PaymentService.new(@client)
  end

  def test_subscribe
    input = Attago::SubscribeInput.new(tier: "pro", billing_cycle: "monthly", renew: false)
    result = @svc.subscribe(input)
    assert_includes @last_req[:uri], "/v1/payments/subscribe"
    assert_equal "POST", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal "pro", sent["tier"]
    assert_equal "monthly", sent["billingCycle"]
    assert_equal false, sent["renew"]
    assert_instance_of Attago::SubscribeResponse, result
    assert_in_delta 29.99, result.price, 0.01
  end

  def test_status
    result = @svc.status
    assert_includes @last_req[:uri], "/v1/payments/status"
    assert_equal "GET", @last_req[:method]
    assert_instance_of Attago::BillingStatus, result
    assert_equal "pro", result.tier
    assert_equal true, result.api_access
    assert_instance_of Attago::IncludedPushes, result.included_pushes
    assert_equal 95, result.included_pushes.remaining
  end

  def test_upgrade_quote
    result = @svc.upgrade_quote("pro", "monthly")
    assert_includes @last_req[:uri], "/v1/payments/upgrade-quote"
    assert_includes @last_req[:uri], "tier=pro"
    assert_includes @last_req[:uri], "cycle=monthly"
    assert_equal "GET", @last_req[:method]
    assert_instance_of Attago::UpgradeQuote, result
    assert_in_delta 24.99, result.final_price, 0.01
    assert_in_delta 5.0, result.proration_credit, 0.01
  end
end

class TestWalletService < Minitest::Test
  WALLET_RESPONSE = {
    "userId" => "u-1",
    "walletAddress" => "0xabc123",
    "chain" => "eip155:8453",
    "verifiedAt" => "2026-03-09T00:00:00Z"
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      if req[:method] == "DELETE"
        Attago::Testing::MockResponse.new(code: 204, body: nil)
      elsif req[:method] == "GET"
        Attago::Testing::MockResponse.new(code: 200, body: { "wallets" => [WALLET_RESPONSE] })
      else
        Attago::Testing::MockResponse.new(code: 200, body: WALLET_RESPONSE)
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @svc = Attago::WalletService.new(@client)
  end

  def test_register
    input = Attago::RegisterWalletInput.new(
      wallet_address: "0xabc123",
      chain: "eip155:8453",
      signature: "0xsig",
      timestamp: 1_710_000_000
    )
    result = @svc.register(input)
    assert_includes @last_req[:uri], "/v1/payments/wallet"
    assert_equal "POST", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal "0xabc123", sent["walletAddress"]
    assert_equal "eip155:8453", sent["chain"]
    assert_equal "0xsig", sent["signature"]
    assert_instance_of Attago::Wallet, result
    assert_equal "0xabc123", result.wallet_address
  end

  def test_list
    result = @svc.list
    assert_includes @last_req[:uri], "/v1/payments/wallets"
    assert_equal "GET", @last_req[:method]
    assert_equal 1, result.size
    assert_instance_of Attago::Wallet, result.first
  end

  def test_remove
    result = @svc.remove("0xabc123")
    assert_includes @last_req[:uri], "/v1/payments/wallet/0xabc123"
    assert_equal "DELETE", @last_req[:method]
    assert_nil result
  end
end

class TestApiKeyService < Minitest::Test
  CREATE_RESPONSE = {
    "keyId" => "key-1",
    "name" => "My Key",
    "prefix" => "ak_",
    "key" => "ak_test_secret_full",
    "createdAt" => "2026-03-09T00:00:00Z"
  }.freeze

  LIST_RESPONSE = {
    "keys" => [{
      "keyId" => "key-1",
      "name" => "My Key",
      "prefix" => "ak_",
      "createdAt" => "2026-03-09T00:00:00Z",
      "lastUsedAt" => nil,
      "revokedAt" => nil
    }]
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      if req[:method] == "DELETE"
        Attago::Testing::MockResponse.new(code: 204, body: nil)
      elsif req[:method] == "POST"
        Attago::Testing::MockResponse.new(code: 200, body: CREATE_RESPONSE)
      else
        Attago::Testing::MockResponse.new(code: 200, body: LIST_RESPONSE)
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @svc = Attago::ApiKeyService.new(@client)
  end

  def test_create
    result = @svc.create("My Key")
    assert_includes @last_req[:uri], "/v1/user/api-keys"
    assert_equal "POST", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal "My Key", sent["name"]
    assert_instance_of Attago::ApiKeyCreateResponse, result
    assert_equal "key-1", result.key_id
    assert_equal "ak_test_secret_full", result.key
  end

  def test_list
    result = @svc.list
    assert_includes @last_req[:uri], "/v1/user/api-keys"
    assert_equal "GET", @last_req[:method]
    assert_equal 1, result.size
    assert_instance_of Attago::ApiKeyListItem, result.first
    assert_equal "key-1", result.first.key_id
  end

  def test_revoke
    result = @svc.revoke("key-1")
    assert_includes @last_req[:uri], "/v1/user/api-keys/key-1"
    assert_equal "DELETE", @last_req[:method]
    assert_nil result
  end

  def test_api_key_create_response_inspect_redacted
    resp = Attago::ApiKeyCreateResponse.new(
      key_id: "kid_123", name: "test", prefix: "ak_live",
      key: "ak_live_secret_value_here", created_at: "2026-01-01T00:00:00Z"
    )
    refute_includes resp.inspect, "ak_live_secret_value_here"
    assert_includes resp.inspect, "***"
  end
end

class TestBundleService < Minitest::Test
  LIST_RESPONSE = {
    "bundles" => [{
      "bundleId" => "b-1",
      "userId" => "u-1",
      "walletAddress" => "0xabc",
      "bundleSize" => 60,
      "remaining" => 42,
      "purchasedAt" => "2026-03-09T00:00:00Z",
      "expiresAt" => nil
    }],
    "catalog" => [{ "name" => "Starter", "pushes" => 60, "price" => 5.0 }],
    "perRequestPrice" => 0.10
  }.freeze

  PURCHASE_RESPONSE = {
    "bundleId" => "b-2",
    "userId" => "u-1",
    "walletAddress" => "0xabc",
    "bundleName" => "Starter",
    "totalPushes" => 60,
    "remaining" => 60,
    "price" => 5.0,
    "purchasedAt" => "2026-03-09T00:00:00Z",
    "payer" => "0xabc",
    "transactionId" => "tx-1"
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      if req[:method] == "POST"
        Attago::Testing::MockResponse.new(code: 200, body: PURCHASE_RESPONSE)
      else
        Attago::Testing::MockResponse.new(code: 200, body: LIST_RESPONSE)
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @svc = Attago::BundleService.new(@client)
  end

  def test_list
    result = @svc.list
    assert_includes @last_req[:uri], "/v1/api/bundles"
    assert_equal "GET", @last_req[:method]
    assert_instance_of Attago::BundleListResponse, result
    assert_equal 1, result.bundles.size
    assert_instance_of Attago::Bundle, result.bundles.first
    assert_equal 42, result.bundles.first.remaining
    assert_equal 1, result.catalog.size
    assert_in_delta 0.10, result.per_request_price, 0.01
  end

  def test_purchase
    input = Attago::PurchaseBundleInput.new(bundle_index: 0, wallet_address: "0xabc")
    result = @svc.purchase(input)
    assert_includes @last_req[:uri], "/v1/api/bundles"
    assert_equal "POST", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal 0, sent["bundleIndex"]
    assert_equal "0xabc", sent["walletAddress"]
    assert_instance_of Attago::BundlePurchaseResponse, result
    assert_equal "b-2", result.bundle_id
    assert_equal 60, result.total_pushes
  end
end

class TestPushService < Minitest::Test
  PUSH_SUB_RESPONSE = {
    "subscriptionId" => "ps-1",
    "endpoint" => "https://push.example.com/sub1",
    "createdAt" => "2026-03-09T00:00:00Z"
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      if req[:method] == "DELETE"
        Attago::Testing::MockResponse.new(code: 204, body: nil)
      elsif req[:method] == "POST"
        Attago::Testing::MockResponse.new(code: 200, body: PUSH_SUB_RESPONSE)
      else
        Attago::Testing::MockResponse.new(code: 200, body: { "subscriptions" => [PUSH_SUB_RESPONSE] })
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @svc = Attago::PushService.new(@client)
  end

  def test_list
    result = @svc.list
    assert_includes @last_req[:uri], "/v1/user/push-subscriptions"
    assert_equal "GET", @last_req[:method]
    assert_equal 1, result.size
    assert_instance_of Attago::PushSubscriptionResponse, result.first
    assert_equal "ps-1", result.first.subscription_id
  end

  def test_create
    keys = Attago::PushKeys.new(p256dh: "p256dh_value", auth: "auth_value")
    input = Attago::CreatePushInput.new(endpoint: "https://push.example.com/sub1", keys: keys)
    result = @svc.create(input)
    assert_includes @last_req[:uri], "/v1/user/push-subscriptions"
    assert_equal "POST", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal "https://push.example.com/sub1", sent["endpoint"]
    assert_equal "p256dh_value", sent["keys"]["p256dh"]
    assert_equal "auth_value", sent["keys"]["auth"]
    assert_instance_of Attago::PushSubscriptionResponse, result
  end

  def test_delete
    result = @svc.delete("ps-1")
    assert_includes @last_req[:uri], "/v1/user/push-subscriptions/ps-1"
    assert_equal "DELETE", @last_req[:method]
    assert_nil result
  end
end

class TestRedeemService < Minitest::Test
  REDEEM_RESPONSE = {
    "tier" => "pro",
    "expiresAt" => "2026-06-09T00:00:00Z",
    "message" => "Code redeemed successfully"
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      Attago::Testing::MockResponse.new(code: 200, body: REDEEM_RESPONSE)
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @svc = Attago::RedeemService.new(@client)
  end

  def test_redeem
    result = @svc.redeem("PROMO-2026")
    assert_includes @last_req[:uri], "/v1/user/redeem"
    assert_equal "POST", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal "PROMO-2026", sent["code"]
    assert_instance_of Attago::RedeemResponse, result
    assert_equal "pro", result.tier
    assert_equal "Code redeemed successfully", result.message
  end
end
