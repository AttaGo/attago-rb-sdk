# frozen_string_literal: true

require "uri"

module Attago
  class ApiKeyService
    def initialize(client)
      @client = client
    end

    # POST /api-keys
    def create(name)
      data = @client.request("POST", "/user/api-keys", body: { "name" => name })
      ApiKeyCreateResponse.from_hash(data)
    end

    # GET /api-keys
    def list
      data = @client.request("GET", "/user/api-keys")
      (data["keys"] || []).map { |k| ApiKeyListItem.from_hash(k) }
    end

    # DELETE /api-keys/{key_id}
    def revoke(key_id)
      @client.request("DELETE", "/user/api-keys/#{URI.encode_www_form_component(key_id)}")
      nil
    end
  end
end
