# frozen_string_literal: true

module Attago
  class BundleService
    def initialize(client)
      @client = client
    end

    # GET /bundles
    def list
      data = @client.request("GET", "/bundles")
      BundleListResponse.from_hash(data)
    end

    # POST /bundles/purchase
    def purchase(input)
      body = { "bundleIndex" => input.bundle_index, "walletAddress" => input.wallet_address }
      data = @client.request("POST", "/bundles/purchase", body: body)
      BundlePurchaseResponse.from_hash(data)
    end
  end
end
