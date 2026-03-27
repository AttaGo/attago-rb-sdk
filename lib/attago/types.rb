# frozen_string_literal: true

module Attago
  # ── Constants ───────────────────────────────────────────────────────

  DEFAULT_BASE_URL = "https://api.attago.bid"
  DEFAULT_COGNITO_REGION = "us-east-1"

  # ── x402 types ──────────────────────────────────────────────────────

  X402Resource = Struct.new(:url, :description, :mime_type, keyword_init: true) do
    def self.from_hash(data)
      new(
        url: data["url"],
        description: data["description"],
        mime_type: data["mimeType"] || ""
      )
    end
  end

  X402AcceptedPayment = Struct.new(:scheme, :network, :amount, :asset, :pay_to,
                                   :max_timeout_seconds, :extra, keyword_init: true) do
    def self.from_hash(data)
      new(
        scheme: data["scheme"],
        network: data["network"],
        amount: data["amount"],
        asset: data["asset"],
        pay_to: data["payTo"],
        max_timeout_seconds: data["maxTimeoutSeconds"] || 0,
        extra: data["extra"] || {}
      )
    end
  end

  X402PaymentRequirements = Struct.new(:x402_version, :resource, :accepts, keyword_init: true) do
    def self.from_hash(data)
      new(
        x402_version: data["x402Version"],
        resource: X402Resource.from_hash(data["resource"]),
        accepts: (data["accepts"] || []).map { |a| X402AcceptedPayment.from_hash(a) }
      )
    end
  end

  # ── Auth types ──────────────────────────────────────────────────────

  CognitoTokens = Struct.new(:id_token, :access_token, :refresh_token, keyword_init: true) do
    def self.from_hash(data)
      new(
        id_token: data["idToken"],
        access_token: data["accessToken"],
        refresh_token: data["refreshToken"]
      )
    end

    def inspect
      "#<struct Attago::CognitoTokens id_token=\"***\", access_token=\"***\", refresh_token=\"***\">"
    end

    alias_method :to_s, :inspect
  end

  SignUpInput = Struct.new(:email, :password, :cognito_client_id,
                           :cognito_region, keyword_init: true)

  ConfirmSignUpInput = Struct.new(:email, :code, :cognito_client_id,
                                  :cognito_region, keyword_init: true)

  ForgotPasswordInput = Struct.new(:email, :cognito_client_id,
                                   :cognito_region, keyword_init: true)

  ConfirmForgotPasswordInput = Struct.new(:email, :code, :new_password,
                                          :cognito_client_id, :cognito_region,
                                          keyword_init: true)

  # ── Agent types ─────────────────────────────────────────────────────

  CompositeScore = Struct.new(:score, :signal, :confidence, keyword_init: true) do
    def self.from_hash(data)
      new(
        score: data["score"].to_f,
        signal: data["signal"],
        confidence: data["confidence"].to_f
      )
    end
  end

  AgentScoreResponse = Struct.new(:token, :composite, :spot, :perps, :context,
                                   :market, :deriv_symbols, :has_derivatives,
                                   :sources, :meta, :request_id,
                                   keyword_init: true) do
    def self.from_hash(data)
      new(
        token: data["token"],
        composite: CompositeScore.from_hash(data["composite"]),
        spot: data["spot"] || {},
        perps: data["perps"],
        context: data["context"] || {},
        market: data["market"] || {},
        deriv_symbols: data["derivSymbols"] || [],
        has_derivatives: data["hasDerivatives"] || false,
        sources: data["sources"] || [],
        meta: data["meta"] || {},
        request_id: data["requestId"]
      )
    end
  end

  AgentDataResponse = Struct.new(:assets, :asset_order, :market, :sources,
                                  :meta, :request_id, keyword_init: true) do
    def self.from_hash(data)
      new(
        assets: data["assets"] || {},
        asset_order: data["assetOrder"] || [],
        market: data["market"] || {},
        sources: data["sources"] || [],
        meta: data["meta"] || {},
        request_id: data["requestId"]
      )
    end
  end

  # ── Data types ──────────────────────────────────────────────────────

  BundleUsage = Struct.new(:bundle_id, :remaining, keyword_init: true) do
    def self.from_hash(data)
      new(
        bundle_id: data["bundleId"],
        remaining: data["remaining"].to_i
      )
    end
  end

  PushUsage = Struct.new(:used, :total, :remaining, keyword_init: true) do
    def self.from_hash(data)
      new(
        used: data["used"].to_i,
        total: data["total"].to_i,
        remaining: data["remaining"].to_i
      )
    end
  end

  DataLatestResponse = Struct.new(:assets, :asset_order, :market, :sources,
                                   :meta, keyword_init: true) do
    def self.from_hash(data)
      new(
        assets: data["assets"] || {},
        asset_order: data["assetOrder"] || [],
        market: data["market"] || {},
        sources: data["sources"] || [],
        meta: data["meta"] || {}
      )
    end
  end

  DataTokenResponse = Struct.new(:token, :composite, :spot, :perps, :context,
                                  :market, :deriv_symbols, :has_derivatives,
                                  :sources, :meta, :request_id, :mode,
                                  :bundle, :included_push,
                                  keyword_init: true) do
    def self.from_hash(data)
      bundle_raw = data["bundle"]
      push_raw = data["includedPush"]
      new(
        token: data["token"],
        composite: data["composite"] || {},
        spot: data["spot"] || {},
        perps: data["perps"],
        context: data["context"] || {},
        market: data["market"] || {},
        deriv_symbols: data["derivSymbols"] || [],
        has_derivatives: data["hasDerivatives"] || false,
        sources: data["sources"] || [],
        meta: data["meta"] || {},
        request_id: data["requestId"],
        mode: data["mode"] || "",
        bundle: bundle_raw ? BundleUsage.from_hash(bundle_raw) : nil,
        included_push: push_raw ? PushUsage.from_hash(push_raw) : nil
      )
    end
  end

  DataPushResponse = Struct.new(:request_id, :token_id, :created_at, :data,
                                 keyword_init: true) do
    def self.from_hash(data)
      new(
        request_id: data["requestId"],
        token_id: data["tokenId"],
        created_at: data["createdAt"],
        data: data["data"] || {}
      )
    end
  end

  # ── Subscription types ──────────────────────────────────────────────

  SubscriptionCondition = Struct.new(:metric_name, :threshold_op, :threshold_val,
                                     keyword_init: true) do
    def self.from_hash(data)
      new(
        metric_name: data["metricName"],
        threshold_op: data["thresholdOp"],
        threshold_val: data["thresholdVal"]
      )
    end
  end

  Subscription = Struct.new(:user_id, :sub_id, :token_id, :label, :groups,
                             :cooldown_minutes, :bucket_hash, :is_active,
                             :created_at, :updated_at, :active_token_shard,
                             keyword_init: true) do
    def self.from_hash(data)
      groups = (data["groups"] || []).map do |group|
        group.map { |c| SubscriptionCondition.from_hash(c) }
      end
      new(
        user_id: data["userId"],
        sub_id: data["subId"],
        token_id: data["tokenId"],
        label: data["label"] || "",
        groups: groups,
        cooldown_minutes: data["cooldownMinutes"] || 5,
        bucket_hash: data["bucketHash"] || "",
        is_active: data.fetch("isActive", true),
        created_at: data["createdAt"] || "",
        updated_at: data["updatedAt"] || "",
        active_token_shard: data["activeTokenShard"]
      )
    end
  end

  CatalogMetric = Struct.new(:label, :type, :operators, :unit, :min, :max,
                              :values, keyword_init: true) do
    def self.from_hash(data)
      new(
        label: data["label"],
        type: data["type"],
        operators: data["operators"] || [],
        unit: data["unit"],
        min: data["min"],
        max: data["max"],
        values: data["values"]
      )
    end
  end

  CatalogResponse = Struct.new(:tokens, :metrics, :tier, :max_subscriptions,
                                :mode, keyword_init: true) do
    def self.from_hash(data)
      metrics = (data["metrics"] || {}).transform_values do |v|
        CatalogMetric.from_hash(v)
      end
      new(
        tokens: data["tokens"] || [],
        metrics: metrics,
        tier: data["tier"] || "",
        max_subscriptions: data["maxSubscriptions"] || 0,
        mode: data["mode"] || ""
      )
    end
  end

  CreateSubscriptionInput = Struct.new(:token_id, :label, :groups,
                                       :cooldown_minutes, keyword_init: true)

  UpdateSubscriptionInput = Struct.new(:label, :groups, :cooldown_minutes,
                                       :is_active, keyword_init: true)

  # ── Payment types ───────────────────────────────────────────────────

  SubscribeInput = Struct.new(:tier, :billing_cycle, :renew, keyword_init: true)

  SubscribeResponse = Struct.new(:tier, :billing_cycle, :price, :currency,
                                  :expires_at, :payer, :mode, :message,
                                  keyword_init: true) do
    def self.from_hash(data)
      new(
        tier: data["tier"],
        billing_cycle: data["billingCycle"],
        price: data["price"].to_f,
        currency: data["currency"],
        expires_at: data["expiresAt"],
        payer: data["payer"],
        mode: data["mode"] || "",
        message: data["message"] || ""
      )
    end
  end

  IncludedPushes = Struct.new(:total, :used, :remaining, :period_start,
                               :period_end, keyword_init: true) do
    def self.from_hash(data)
      new(
        total: data["total"].to_i,
        used: data["used"].to_i,
        remaining: data["remaining"].to_i,
        period_start: data["periodStart"],
        period_end: data["periodEnd"]
      )
    end
  end

  BillingStatus = Struct.new(:tier, :tier_name, :billing_cycle, :max_subs,
                              :api_access, :free_data_pushes, :mode,
                              :expires_at, :included_pushes,
                              keyword_init: true) do
    def self.from_hash(data)
      pushes_raw = data["includedPushes"]
      new(
        tier: data["tier"],
        tier_name: data["tierName"],
        billing_cycle: data["billingCycle"] || "",
        max_subs: data["maxSubs"] || 0,
        api_access: data.fetch("apiAccess", false),
        free_data_pushes: data["freeDataPushes"] || 0,
        mode: data["mode"] || "",
        expires_at: data["expiresAt"],
        included_pushes: pushes_raw ? IncludedPushes.from_hash(pushes_raw) : nil
      )
    end
  end

  UpgradeQuote = Struct.new(:current_tier, :current_cycle, :current_expires_at,
                             :target_tier, :target_cycle, :base_price,
                             :proration_credit, :final_price, :currency,
                             :expires_at, keyword_init: true) do
    def self.from_hash(data)
      new(
        current_tier: data["currentTier"],
        current_cycle: data["currentCycle"],
        current_expires_at: data["currentExpiresAt"],
        target_tier: data["targetTier"],
        target_cycle: data["targetCycle"],
        base_price: data["basePrice"].to_f,
        proration_credit: data["prorationCredit"].to_f,
        final_price: data["finalPrice"].to_f,
        currency: data["currency"],
        expires_at: data["expiresAt"]
      )
    end
  end

  # ── Wallet types ────────────────────────────────────────────────────

  RegisterWalletInput = Struct.new(:wallet_address, :chain, :signature,
                                   :timestamp, keyword_init: true)

  Wallet = Struct.new(:user_id, :wallet_address, :chain, :verified_at,
                       keyword_init: true) do
    def self.from_hash(data)
      new(
        user_id: data["userId"],
        wallet_address: data["walletAddress"],
        chain: data["chain"],
        verified_at: data["verifiedAt"]
      )
    end
  end

  # ── Webhook types ───────────────────────────────────────────────────

  WebhookCreateResponse = Struct.new(:webhook_id, :url, :secret, :created_at,
                                      keyword_init: true) do
    def self.from_hash(data)
      new(
        webhook_id: data["webhookId"],
        url: data["url"],
        secret: data["secret"],
        created_at: data["createdAt"]
      )
    end

    def inspect
      "#<struct Attago::WebhookCreateResponse webhook_id=#{webhook_id.inspect}, " \
        "url=#{url.inspect}, secret=\"***\", created_at=#{created_at.inspect}>"
    end

    alias_method :to_s, :inspect
  end

  WebhookListItem = Struct.new(:webhook_id, :url, :created_at,
                                keyword_init: true) do
    def self.from_hash(data)
      new(
        webhook_id: data["webhookId"],
        url: data["url"],
        created_at: data["createdAt"]
      )
    end
  end

  WebhookTestResult = Struct.new(:success, :attempts, :status_code, :error,
                                  keyword_init: true) do
    def self.from_hash(data)
      new(
        success: data["success"],
        attempts: data["attempts"] || 0,
        status_code: data["statusCode"],
        error: data["error"]
      )
    end
  end

  SendTestOptions = Struct.new(:url, :secret, :token, :state, :environment,
                                :backoff_ms, keyword_init: true)

  WebhookPayloadAlert = Struct.new(:id, :label, :token, :state,
                                    keyword_init: true) do
    def self.from_hash(data)
      new(
        id: data["id"],
        label: data["label"],
        token: data["token"],
        state: data["state"]
      )
    end
  end

  WebhookPayloadData = Struct.new(:url, :expires_at, :fallback_url,
                                   keyword_init: true) do
    def self.from_hash(data)
      new(
        url: data["url"],
        expires_at: data["expiresAt"],
        fallback_url: data["fallbackUrl"]
      )
    end
  end

  WebhookPayload = Struct.new(:event, :version, :environment, :alert, :data,
                               :timestamp, keyword_init: true) do
    def self.from_hash(data)
      new(
        event: data["event"],
        version: data["version"],
        environment: data["environment"],
        alert: WebhookPayloadAlert.from_hash(data["alert"]),
        data: WebhookPayloadData.from_hash(data["data"]),
        timestamp: data["timestamp"]
      )
    end
  end

  # ── API Key types ───────────────────────────────────────────────────

  ApiKeyCreateResponse = Struct.new(:key_id, :name, :prefix, :key, :created_at,
                                     keyword_init: true) do
    def self.from_hash(data)
      new(
        key_id: data["keyId"],
        name: data["name"],
        prefix: data["prefix"],
        key: data["key"],
        created_at: data["createdAt"]
      )
    end

    def inspect
      "#<struct Attago::ApiKeyCreateResponse key_id=#{key_id.inspect}, " \
        "name=#{name.inspect}, prefix=#{prefix.inspect}, key=\"***\", " \
        "created_at=#{created_at.inspect}>"
    end

    alias_method :to_s, :inspect
  end

  ApiKeyListItem = Struct.new(:key_id, :name, :prefix, :created_at,
                               :last_used_at, :revoked_at,
                               keyword_init: true) do
    def self.from_hash(data)
      new(
        key_id: data["keyId"],
        name: data["name"],
        prefix: data["prefix"],
        created_at: data["createdAt"],
        last_used_at: data["lastUsedAt"],
        revoked_at: data["revokedAt"]
      )
    end
  end

  # ── Bundle types ────────────────────────────────────────────────────

  Bundle = Struct.new(:bundle_id, :user_id, :wallet_address, :bundle_size,
                       :remaining, :purchased_at, :expires_at,
                       keyword_init: true) do
    def self.from_hash(data)
      new(
        bundle_id: data["bundleId"],
        user_id: data["userId"],
        wallet_address: data["walletAddress"],
        bundle_size: data["bundleSize"].to_i,
        remaining: data["remaining"].to_i,
        purchased_at: data["purchasedAt"],
        expires_at: data["expiresAt"]
      )
    end
  end

  BundleCatalogEntry = Struct.new(:name, :pushes, :price, keyword_init: true) do
    def self.from_hash(data)
      new(
        name: data["name"],
        pushes: data["pushes"].to_i,
        price: data["price"].to_f
      )
    end
  end

  BundleListResponse = Struct.new(:bundles, :catalog, :per_request_price,
                                   keyword_init: true) do
    def self.from_hash(data)
      new(
        bundles: (data["bundles"] || []).map { |b| Bundle.from_hash(b) },
        catalog: (data["catalog"] || []).map { |c| BundleCatalogEntry.from_hash(c) },
        per_request_price: (data["perRequestPrice"] || 0).to_f
      )
    end
  end

  PurchaseBundleInput = Struct.new(:bundle_index, :wallet_address,
                                   keyword_init: true)

  BundlePurchaseResponse = Struct.new(:bundle_id, :user_id, :wallet_address,
                                      :bundle_name, :total_pushes, :remaining,
                                      :price, :purchased_at, :payer,
                                      :transaction_id, keyword_init: true) do
    def self.from_hash(data)
      new(
        bundle_id: data["bundleId"],
        user_id: data["userId"],
        wallet_address: data["walletAddress"],
        bundle_name: data["bundleName"],
        total_pushes: data["totalPushes"].to_i,
        remaining: data["remaining"].to_i,
        price: data["price"].to_f,
        purchased_at: data["purchasedAt"],
        payer: data["payer"],
        transaction_id: data["transactionId"]
      )
    end
  end

  # ── Push types ──────────────────────────────────────────────────────

  PushKeys = Struct.new(:p256dh, :auth, keyword_init: true) do
    def self.from_hash(data)
      new(
        p256dh: data["p256dh"],
        auth: data["auth"]
      )
    end
  end

  CreatePushInput = Struct.new(:endpoint, :keys, keyword_init: true)

  PushSubscriptionResponse = Struct.new(:subscription_id, :endpoint, :created_at,
                                        keyword_init: true) do
    def self.from_hash(data)
      new(
        subscription_id: data["subscriptionId"],
        endpoint: data["endpoint"],
        created_at: data["createdAt"]
      )
    end
  end

  # ── Messaging types ─────────────────────────────────────────────────

  MessagingLink = Struct.new(:platform, :username, :linked_at, keyword_init: true) do
    def self.from_hash(data)
      new(
        platform: data["platform"],
        username: data["username"],
        linked_at: data["linkedAt"]
      )
    end
  end

  MessagingLinkResult = Struct.new(:linked, :username, keyword_init: true)

  MessagingUnlinkResult = Struct.new(:unlinked, keyword_init: true)

  MessagingTestResult = Struct.new(:success, :platforms, :errors, keyword_init: true) do
    def self.from_hash(data)
      new(
        success: data["success"],
        platforms: data["platforms"] || [],
        errors: data["errors"] || []
      )
    end
  end

  # ── Redeem types ────────────────────────────────────────────────────

  RedeemResponse = Struct.new(:tier, :expires_at, :message, keyword_init: true) do
    def self.from_hash(data)
      new(
        tier: data["tier"],
        expires_at: data["expiresAt"],
        message: data["message"]
      )
    end
  end

  # ── MCP types ───────────────────────────────────────────────────────

  McpToolsCapability = Struct.new(:list_changed, keyword_init: true) do
    def self.from_hash(data)
      new(list_changed: data.fetch("listChanged", false))
    end
  end

  McpCapabilities = Struct.new(:tools, keyword_init: true) do
    def self.from_hash(data)
      tools_raw = data["tools"]
      new(
        tools: tools_raw ? McpToolsCapability.from_hash(tools_raw) : nil
      )
    end
  end

  McpServerMetadata = Struct.new(:name, :version, keyword_init: true) do
    def self.from_hash(data)
      new(name: data["name"], version: data["version"])
    end
  end

  McpServerInfo = Struct.new(:protocol_version, :capabilities, :server_info,
                              :instructions, keyword_init: true) do
    def self.from_hash(data)
      new(
        protocol_version: data["protocolVersion"],
        capabilities: McpCapabilities.from_hash(data["capabilities"] || {}),
        server_info: McpServerMetadata.from_hash(data["serverInfo"]),
        instructions: data["instructions"]
      )
    end
  end

  McpTool = Struct.new(:name, :description, :input_schema, :annotations,
                        keyword_init: true) do
    def self.from_hash(data)
      new(
        name: data["name"],
        description: data["description"],
        input_schema: data["inputSchema"] || {},
        annotations: data["annotations"]
      )
    end
  end

  McpToolContent = Struct.new(:type, :text, :data, :mime_type,
                               keyword_init: true) do
    def self.from_hash(data)
      new(
        type: data["type"],
        text: data["text"],
        data: data["data"],
        mime_type: data["mimeType"]
      )
    end
  end

  McpToolCallResult = Struct.new(:content, :is_error, keyword_init: true) do
    def self.from_hash(data)
      new(
        content: (data["content"] || []).map { |c| McpToolContent.from_hash(c) },
        is_error: data.fetch("isError", false)
      )
    end
  end

  # ── User profile types ──────────────────────────────────────────────

  UserProfile = Struct.new(:user_id, :email, :plan_tier, :role, :effective_tier,
                            :delivery_preference, :created_at, :updated_at,
                            :tier_override, :arena_username,
                            keyword_init: true) do
    def self.from_hash(data)
      new(
        user_id: data["userId"],
        email: data["email"],
        plan_tier: data["planTier"] || "free",
        role: data["role"] || "user",
        effective_tier: data["effectiveTier"] || "free",
        delivery_preference: data["deliveryPreference"] || "email",
        created_at: data["createdAt"] || "",
        updated_at: data["updatedAt"] || "",
        tier_override: data["tierOverride"],
        arena_username: data["arenaUsername"]
      )
    end
  end
end
