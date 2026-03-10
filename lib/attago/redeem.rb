# frozen_string_literal: true

module Attago
  class RedeemService
    def initialize(client)
      @client = client
    end

    # POST /redeem
    def redeem(code)
      data = @client.request("POST", "/redeem", body: { "code" => code })
      RedeemResponse.from_hash(data)
    end
  end
end
