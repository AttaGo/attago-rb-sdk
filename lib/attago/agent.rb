# frozen_string_literal: true

module Attago
  class AgentService
    def initialize(client)
      @client = client
    end

    # GET /agent/score?symbol=SYM
    def get_score(symbol)
      data = @client.request("GET", "/agent/score", params: { "symbol" => symbol })
      AgentScoreResponse.from_hash(data)
    end

    # GET /agent/data?symbols=SYM1,SYM2 (omit for all)
    def get_data(*symbols)
      params = symbols.empty? ? {} : { "symbols" => symbols.join(",") }
      data = @client.request("GET", "/agent/data", params: params)
      AgentDataResponse.from_hash(data)
    end
  end
end
