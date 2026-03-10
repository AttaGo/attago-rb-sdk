# frozen_string_literal: true

require "test_helper"
require "webrick"

class TestWebhookListener < Minitest::Test
  SECRET = "listener_test_secret_abc"
  # Use a port range unlikely to conflict
  TEST_PORT_BASE = 19870

  def build_alert_payload
    {
      "event" => "alert",
      "version" => "2",
      "environment" => "production",
      "timestamp" => Time.now.utc.iso8601(3),
      "alert" => {
        "id" => "sub_abc123",
        "label" => "BTC Price Alert",
        "token" => "BTC",
        "state" => "triggered"
      },
      "data" => {
        "url" => "https://attago.bid/v1/data/push/test_1234",
        "expiresAt" => Time.now.utc.iso8601(3),
        "fallbackUrl" => nil
      }
    }
  end

  def build_test_payload
    payload = build_alert_payload
    payload["event"] = "test"
    payload
  end

  def post_to_listener(listener, path: "/webhook", body: nil, signature: nil, method: :post)
    uri = URI.parse("http://#{listener.addr}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 3
    http.read_timeout = 3

    case method
    when :post
      req = Net::HTTP::Post.new(uri.request_uri)
    when :get
      req = Net::HTTP::Get.new(uri.request_uri)
    end

    req["Content-Type"] = "application/json"
    req["X-AttaGo-Signature"] = signature if signature
    req.body = body if body

    http.request(req)
  end

  def next_port
    @port_counter ||= 0
    @port_counter += 1
    TEST_PORT_BASE + @port_counter
  end

  def test_start_stop
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.start

    assert listener.listening?

    listener.stop

    refute listener.listening?
  end

  def test_valid_signature_200
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.start

    payload = build_alert_payload
    body = JSON.generate(payload)
    sig = Attago::Webhooks.sign_payload(body, SECRET)

    resp = post_to_listener(listener, body: body, signature: sig)
    assert_equal "200", resp.code
    parsed = JSON.parse(resp.body)
    assert_equal true, parsed["ok"]
  ensure
    listener&.stop
  end

  def test_invalid_signature_401
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.start

    payload = build_alert_payload
    body = JSON.generate(payload)

    resp = post_to_listener(listener, body: body, signature: "bad_signature")
    assert_equal "401", resp.code
    parsed = JSON.parse(resp.body)
    assert_equal "Invalid signature", parsed["error"]
  ensure
    listener&.stop
  end

  def test_missing_signature_401
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.start

    payload = build_alert_payload
    body = JSON.generate(payload)

    resp = post_to_listener(listener, body: body) # no signature header
    assert_equal "401", resp.code
  ensure
    listener&.stop
  end

  def test_wrong_path_404
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.start

    payload = build_alert_payload
    body = JSON.generate(payload)
    sig = Attago::Webhooks.sign_payload(body, SECRET)

    resp = post_to_listener(listener, path: "/other", body: body, signature: sig)
    assert_equal "404", resp.code
  ensure
    listener&.stop
  end

  def test_wrong_method_405
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.start

    resp = post_to_listener(listener, method: :get)
    assert_equal "405", resp.code
    assert_equal "POST", resp["Allow"]
  ensure
    listener&.stop
  end

  def test_test_event_routes_to_on_test
    received = nil
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.on_test { |payload| received = payload }
    listener.start

    payload = build_test_payload
    body = JSON.generate(payload)
    sig = Attago::Webhooks.sign_payload(body, SECRET)

    resp = post_to_listener(listener, body: body, signature: sig)
    assert_equal "200", resp.code

    # Give the handler a moment to process
    sleep 0.05
    assert_instance_of Attago::WebhookPayload, received
    assert_equal "test", received.event
  ensure
    listener&.stop
  end

  def test_alert_event_routes_to_on_alert
    received = nil
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.on_alert { |payload| received = payload }
    listener.start

    payload = build_alert_payload
    body = JSON.generate(payload)
    sig = Attago::Webhooks.sign_payload(body, SECRET)

    resp = post_to_listener(listener, body: body, signature: sig)
    assert_equal "200", resp.code

    sleep 0.05
    assert_instance_of Attago::WebhookPayload, received
    assert_equal "alert", received.event
    assert_equal "BTC", received.alert.token
    assert_equal "triggered", received.alert.state
  ensure
    listener&.stop
  end

  def test_handler_exception_captured
    captured_error = nil
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.on_alert { |_| raise "boom" }
    listener.on_error { |e| captured_error = e }
    listener.start

    payload = build_alert_payload
    body = JSON.generate(payload)
    sig = Attago::Webhooks.sign_payload(body, SECRET)

    resp = post_to_listener(listener, body: body, signature: sig)
    assert_equal "500", resp.code

    sleep 0.05
    assert_instance_of RuntimeError, captured_error
    assert_equal "boom", captured_error.message
  ensure
    listener&.stop
  end

  def test_body_too_large_413
    listener = Attago::WebhookListener.new(secret: SECRET, port: next_port)
    listener.start

    # Build a body larger than 1 MB
    big_body = "x" * (Attago::WebhookListener::MAX_BODY_SIZE + 1)
    sig = Attago::Webhooks.sign_payload(big_body, SECRET)

    resp = post_to_listener(listener, body: big_body, signature: sig)
    assert_equal "413", resp.code
  ensure
    listener&.stop
  end
end
