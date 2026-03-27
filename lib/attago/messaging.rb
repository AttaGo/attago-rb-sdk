# frozen_string_literal: true

require "uri"

module Attago
  class MessagingService
    def initialize(client)
      @client = client
    end

    # GET /user/messaging
    def list
      data = @client.request("GET", "/user/messaging")
      (data["links"] || []).map { |l| MessagingLink.from_hash(l) }
    end

    # POST /user/messaging/telegram/link
    def link_telegram(code:)
      data = @client.request("POST", "/user/messaging/telegram/link", body: { "code" => code })
      MessagingLinkResult.new(linked: data["linked"], username: data["username"])
    end

    # DELETE /user/messaging/telegram
    def unlink_telegram
      data = @client.request("DELETE", "/user/messaging/telegram")
      MessagingUnlinkResult.new(unlinked: data["unlinked"])
    end

    # POST /user/messaging/test
    def test_delivery
      data = @client.request("POST", "/user/messaging/test")
      MessagingTestResult.from_hash(data)
    end
  end
end
