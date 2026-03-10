# frozen_string_literal: true

module Attago
  class PaymentService
    def initialize(client)
      @client = client
    end

    # POST /payments/subscribe
    def subscribe(input)
      body = { "tier" => input.tier, "billingCycle" => input.billing_cycle, "renew" => input.renew }
      data = @client.request("POST", "/payments/subscribe", body: body)
      SubscribeResponse.from_hash(data)
    end

    # GET /payments/status
    def status
      data = @client.request("GET", "/payments/status")
      BillingStatus.from_hash(data)
    end

    # GET /payments/upgrade-quote?tier=X&cycle=Y
    def upgrade_quote(tier, cycle)
      data = @client.request("GET", "/payments/upgrade-quote", params: { "tier" => tier, "cycle" => cycle })
      UpgradeQuote.from_hash(data)
    end
  end
end
