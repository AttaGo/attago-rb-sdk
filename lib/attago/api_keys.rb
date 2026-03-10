# frozen_string_literal: true

module Attago
  class ApiKeyService
    def initialize(client)
      @client = client
    end

    # POST /api-keys
    def create(name)
      data = @client.request("POST", "/api-keys", body: { "name" => name })
      ApiKeyCreateResponse.from_hash(data)
    end

    # GET /api-keys
    def list
      data = @client.request("GET", "/api-keys")
      (data["keys"] || []).map { |k| ApiKeyListItem.from_hash(k) }
    end

    # DELETE /api-keys/{key_id}
    def revoke(key_id)
      @client.request("DELETE", "/api-keys/#{key_id}")
      nil
    end
  end
end
