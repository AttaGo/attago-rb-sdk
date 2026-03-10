# frozen_string_literal: true

require "uri"

module Attago
  class WalletService
    def initialize(client)
      @client = client
    end

    # POST /payments/wallet
    def register(input)
      body = {
        "walletAddress" => input.wallet_address,
        "chain" => input.chain,
        "signature" => input.signature,
        "timestamp" => input.timestamp
      }
      data = @client.request("POST", "/payments/wallet", body: body)
      Wallet.from_hash(data)
    end

    # GET /payments/wallets
    def list
      data = @client.request("GET", "/payments/wallets")
      (data["wallets"] || []).map { |w| Wallet.from_hash(w) }
    end

    # DELETE /payments/wallet/{address}
    def remove(address)
      @client.request("DELETE", "/payments/wallet/#{URI.encode_www_form_component(address)}")
      nil
    end
  end
end
