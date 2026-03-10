# frozen_string_literal: true

require "uri"

module Attago
  class WalletService
    def initialize(client)
      @client = client
    end

    # POST /wallets/register
    def register(input)
      body = {
        "walletAddress" => input.wallet_address,
        "chain" => input.chain,
        "signature" => input.signature,
        "timestamp" => input.timestamp
      }
      data = @client.request("POST", "/wallets/register", body: body)
      Wallet.from_hash(data)
    end

    # GET /wallets
    def list
      data = @client.request("GET", "/wallets")
      (data["wallets"] || []).map { |w| Wallet.from_hash(w) }
    end

    # DELETE /wallets/{address}
    def remove(address)
      @client.request("DELETE", "/wallets/#{URI.encode_www_form_component(address)}")
      nil
    end
  end
end
