# frozen_string_literal: true

require "test_helper"

class TestErrors < Minitest::Test
  # ── Error base ──────────────────────────────────────────────────────

  def test_error_is_standard_error
    assert Attago::Error < StandardError
  end

  # ── ConfigError ─────────────────────────────────────────────────────

  def test_config_error_is_error
    err = Attago::ConfigError.new("bad config")
    assert_kind_of Attago::Error, err
    assert_equal "bad config", err.message
  end

  def test_config_error_is_not_api_error
    err = Attago::ConfigError.new("bad config")
    refute_kind_of Attago::ApiError, err
  end

  # ── ApiError ────────────────────────────────────────────────────────

  def test_api_error_message_format
    err = Attago::ApiError.new(status_code: 500, message: "Internal Server Error")
    assert_equal "attago: HTTP 500: Internal Server Error", err.message
  end

  def test_api_error_attributes
    err = Attago::ApiError.new(
      status_code: 404,
      message: "Not Found",
      body: { "error" => "missing" },
      headers: { "x-request-id" => "abc" }
    )
    assert_equal 404, err.status_code
    assert_equal({ "error" => "missing" }, err.body)
    assert_equal({ "x-request-id" => "abc" }, err.headers)
  end

  def test_api_error_is_error
    err = Attago::ApiError.new(status_code: 500, message: "fail")
    assert_kind_of Attago::Error, err
  end

  def test_api_error_default_body_and_headers
    err = Attago::ApiError.new(status_code: 500, message: "fail")
    assert_equal({}, err.body)
    assert_equal({}, err.headers)
  end

  # ── PaymentRequiredError ────────────────────────────────────────────

  def test_payment_required_status_code
    err = Attago::PaymentRequiredError.new(message: "pay up")
    assert_equal 402, err.status_code
  end

  def test_payment_required_message_format
    err = Attago::PaymentRequiredError.new(message: "pay up")
    assert_equal "attago: HTTP 402: pay up", err.message
  end

  def test_payment_required_is_api_error
    err = Attago::PaymentRequiredError.new(message: "pay up")
    assert_kind_of Attago::ApiError, err
    assert_kind_of Attago::Error, err
  end

  def test_payment_required_payment_requirements
    reqs = { "x402Version" => 1 }
    err = Attago::PaymentRequiredError.new(
      message: "pay up",
      payment_requirements: reqs
    )
    assert_equal reqs, err.payment_requirements
  end

  def test_payment_required_catchable_as_api_error
    caught = false
    begin
      raise Attago::PaymentRequiredError.new(message: "pay up")
    rescue Attago::ApiError
      caught = true
    end
    assert caught, "PaymentRequiredError should be catchable as ApiError"
  end

  # ── RateLimitError ──────────────────────────────────────────────────

  def test_rate_limit_status_code
    err = Attago::RateLimitError.new(message: "slow down")
    assert_equal 429, err.status_code
  end

  def test_rate_limit_retry_after
    err = Attago::RateLimitError.new(message: "slow down", retry_after: 30)
    assert_equal 30, err.retry_after
  end

  def test_rate_limit_is_api_error
    err = Attago::RateLimitError.new(message: "slow down")
    assert_kind_of Attago::ApiError, err
    assert_kind_of Attago::Error, err
  end

  def test_rate_limit_catchable_as_api_error
    caught = false
    begin
      raise Attago::RateLimitError.new(message: "slow down")
    rescue Attago::ApiError
      caught = true
    end
    assert caught, "RateLimitError should be catchable as ApiError"
  end

  # ── AuthError ───────────────────────────────────────────────────────

  def test_auth_error_message_without_code
    err = Attago::AuthError.new("invalid credentials")
    assert_equal "attago: auth error: invalid credentials", err.message
  end

  def test_auth_error_message_with_code
    err = Attago::AuthError.new("bad password", code: "NotAuthorizedException")
    assert_equal "attago: auth error [NotAuthorizedException]: bad password", err.message
    assert_equal "NotAuthorizedException", err.code
  end

  def test_auth_error_is_error_not_api_error
    err = Attago::AuthError.new("fail")
    assert_kind_of Attago::Error, err
    refute_kind_of Attago::ApiError, err
  end

  # ── MfaRequiredError ────────────────────────────────────────────────

  def test_mfa_required_attributes
    err = Attago::MfaRequiredError.new(
      session: "sess-123",
      challenge_name: "SOFTWARE_TOKEN_MFA"
    )
    assert_equal "sess-123", err.session
    assert_equal "SOFTWARE_TOKEN_MFA", err.challenge_name
  end

  def test_mfa_required_is_auth_error
    err = Attago::MfaRequiredError.new(session: "s", challenge_name: "MFA")
    assert_kind_of Attago::AuthError, err
    assert_kind_of Attago::Error, err
    refute_kind_of Attago::ApiError, err
  end

  def test_mfa_required_message
    err = Attago::MfaRequiredError.new(
      session: "s",
      challenge_name: "SOFTWARE_TOKEN_MFA"
    )
    assert_includes err.message, "MFA required (SOFTWARE_TOKEN_MFA)"
  end

  # ── McpError ────────────────────────────────────────────────────────

  def test_mcp_error_message_format
    err = Attago::McpError.new(code: -32601, message: "Method not found")
    assert_equal "attago: MCP error -32601: Method not found", err.message
  end

  def test_mcp_error_attributes
    err = Attago::McpError.new(code: -32600, message: "Invalid", data: { "detail" => "bad" })
    assert_equal(-32600, err.mcp_code)
    assert_equal "Invalid", err.mcp_message
    assert_equal({ "detail" => "bad" }, err.data)
  end

  def test_mcp_error_is_error_not_api_error
    err = Attago::McpError.new(code: -32601, message: "fail")
    assert_kind_of Attago::Error, err
    refute_kind_of Attago::ApiError, err
  end

  def test_mcp_error_default_data
    err = Attago::McpError.new(code: -32601, message: "fail")
    assert_nil err.data
  end
end
