# frozen_string_literal: true

require "uri"

module Attago
  class SubscriptionService
    def initialize(client)
      @client = client
    end

    # GET /subscriptions/catalog
    def catalog
      data = @client.request("GET", "/subscriptions/catalog")
      CatalogResponse.from_hash(data)
    end

    # GET /subscriptions
    def list
      data = @client.request("GET", "/subscriptions")
      (data["subscriptions"] || []).map { |s| Subscription.from_hash(s) }
    end

    # POST /subscriptions
    def create(input)
      body = {
        "tokenId" => input.token_id,
        "label" => input.label,
        "groups" => input.groups.map { |group|
          group.map { |c|
            { "metricName" => c.metric_name, "thresholdOp" => c.threshold_op, "thresholdVal" => c.threshold_val }
          }
        }
      }
      body["cooldownMinutes"] = input.cooldown_minutes if input.cooldown_minutes
      data = @client.request("POST", "/subscriptions", body: body)
      Subscription.from_hash(data)
    end

    # PUT /subscriptions/{sub_id}
    def update(sub_id, input)
      body = {}
      body["label"] = input.label if input.label
      body["cooldownMinutes"] = input.cooldown_minutes if input.cooldown_minutes
      body["isActive"] = input.is_active unless input.is_active.nil?
      if input.groups
        body["groups"] = input.groups.map { |group|
          group.map { |c|
            { "metricName" => c.metric_name, "thresholdOp" => c.threshold_op, "thresholdVal" => c.threshold_val }
          }
        }
      end
      data = @client.request("PUT", "/subscriptions/#{URI.encode_www_form_component(sub_id)}", body: body)
      Subscription.from_hash(data)
    end

    # DELETE /subscriptions/{sub_id}
    def delete(sub_id)
      @client.request("DELETE", "/subscriptions/#{URI.encode_www_form_component(sub_id)}")
      nil
    end
  end
end
