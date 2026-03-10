# frozen_string_literal: true

require "uri"

module Attago
  class PushService
    def initialize(client)
      @client = client
    end

    # GET /push/subscriptions
    def list
      data = @client.request("GET", "/user/push-subscriptions")
      (data["subscriptions"] || []).map { |s| PushSubscriptionResponse.from_hash(s) }
    end

    # POST /push/subscriptions
    def create(input)
      body = {
        "endpoint" => input.endpoint,
        "keys" => { "p256dh" => input.keys.p256dh, "auth" => input.keys.auth }
      }
      data = @client.request("POST", "/user/push-subscriptions", body: body)
      PushSubscriptionResponse.from_hash(data)
    end

    # DELETE /push/subscriptions/{subscription_id}
    def delete(subscription_id)
      @client.request("DELETE", "/user/push-subscriptions/#{URI.encode_www_form_component(subscription_id)}")
      nil
    end
  end
end
