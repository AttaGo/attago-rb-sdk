# frozen_string_literal: true

module Attago
  class BundleService
    def initialize(client)
      @client = client
    end

    # GET /api/bundles
    def list
      data = @client.request("GET", "/api/bundles")
      BundleListResponse.from_hash(data)
    end

    # POST /api/bundles
    def purchase(input)
      body = { "bundleIndex" => input.bundle_index, "walletAddress" => input.wallet_address }
      data = @client.request("POST", "/api/bundles", body: body)
      BundlePurchaseResponse.from_hash(data)
    end
  end
end
