# frozen_string_literal: true

require "uri"

module Attago
  class DataService
    def initialize(client)
      @client = client
    end

    # GET /data/latest
    def get_latest
      data = @client.request("GET", "/data/latest")
      DataLatestResponse.from_hash(data)
    end

    # GET /api/data/{token}
    def get_token_data(token)
      data = @client.request("GET", "/api/data/#{URI.encode_www_form_component(token)}")
      DataTokenResponse.from_hash(data)
    end

    # GET /data/push/{request_id}
    def get_data_push(request_id)
      data = @client.request("GET", "/data/push/#{URI.encode_www_form_component(request_id)}")
      DataPushResponse.from_hash(data)
    end
  end
end
