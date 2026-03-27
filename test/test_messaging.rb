# frozen_string_literal: true

require "test_helper"

class TestMessagingService < Minitest::Test
  LIST_RESPONSE = {
    "links" => [{
      "platform" => "telegram",
      "username" => "alice_bot",
      "linkedAt" => "2026-03-20T00:00:00Z"
    }]
  }.freeze

  LINK_RESPONSE = {
    "linked" => true,
    "username" => "alice_bot"
  }.freeze

  UNLINK_RESPONSE = {
    "unlinked" => true
  }.freeze

  TEST_RESPONSE = {
    "success" => true,
    "platforms" => ["telegram"],
    "errors" => []
  }.freeze

  def setup
    @last_req = nil
    @transport = Attago::Testing::MockTransport.new do |req|
      @last_req = req
      uri = req[:uri]
      if uri.include?("/messaging/test")
        Attago::Testing::MockResponse.new(code: 200, body: TEST_RESPONSE)
      elsif uri.include?("/messaging/telegram/link")
        Attago::Testing::MockResponse.new(code: 200, body: LINK_RESPONSE)
      elsif uri.include?("/messaging/telegram") && req[:method] == "DELETE"
        Attago::Testing::MockResponse.new(code: 200, body: UNLINK_RESPONSE)
      else
        Attago::Testing::MockResponse.new(code: 200, body: LIST_RESPONSE)
      end
    end
    @client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    @svc = Attago::MessagingService.new(@client)
  end

  def test_list
    result = @svc.list
    assert_includes @last_req[:uri], "/v1/user/messaging"
    assert_equal "GET", @last_req[:method]
    assert_equal 1, result.size
    assert_instance_of Attago::MessagingLink, result.first
    assert_equal "telegram", result.first.platform
    assert_equal "alice_bot", result.first.username
    assert_equal "2026-03-20T00:00:00Z", result.first.linked_at
  end

  def test_link_telegram
    result = @svc.link_telegram(code: "abc123")
    assert_includes @last_req[:uri], "/v1/user/messaging/telegram/link"
    assert_equal "POST", @last_req[:method]
    sent = JSON.parse(@last_req[:body])
    assert_equal "abc123", sent["code"]
    assert_instance_of Attago::MessagingLinkResult, result
    assert_equal true, result.linked
    assert_equal "alice_bot", result.username
  end

  def test_unlink_telegram
    result = @svc.unlink_telegram
    assert_includes @last_req[:uri], "/v1/user/messaging/telegram"
    assert_equal "DELETE", @last_req[:method]
    assert_instance_of Attago::MessagingUnlinkResult, result
    assert_equal true, result.unlinked
  end

  def test_delivery
    result = @svc.test_delivery
    assert_includes @last_req[:uri], "/v1/user/messaging/test"
    assert_equal "POST", @last_req[:method]
    assert_instance_of Attago::MessagingTestResult, result
    assert_equal true, result.success
    assert_equal ["telegram"], result.platforms
    assert_equal [], result.errors
  end

  def test_client_exposes_messaging
    client = Attago::Client.new(api_key: "ak_test", transport: @transport)
    assert_instance_of Attago::MessagingService, client.messaging
  end
end
