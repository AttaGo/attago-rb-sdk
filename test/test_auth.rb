# frozen_string_literal: true

require "test_helper"

class TestAuth < Minitest::Test
  # ── Test helpers ────────────────────────────────────────────────────

  # Returns a proc that acts as a mock HTTP client.
  # The proc receives (target, body) and returns a MockResponse.
  def mock_http(&handler)
    proc { |target, body| handler.call(target, body) }
  end

  def success_auth_result
    {
      "AuthenticationResult" => {
        "IdToken" => "id-token-abc",
        "AccessToken" => "access-token-def",
        "RefreshToken" => "refresh-token-ghi"
      }
    }
  end

  def make_auth(http_client: nil)
    auth = Attago::CognitoAuth.new(
      client_id: "test-client-id",
      region: "us-east-1",
      email: "test@example.com",
      password: "testpass123"
    )
    auth.http_client = http_client if http_client
    auth
  end

  # ── sign_in success ────────────────────────────────────────────────

  def test_sign_in_success
    http = mock_http do |_target, _body|
      Attago::Testing::MockResponse.new(code: 200, body: success_auth_result)
    end

    auth = make_auth(http_client: http)
    tokens = auth.sign_in

    assert_kind_of Attago::CognitoTokens, tokens
    assert_equal "id-token-abc", tokens.id_token
    assert_equal "access-token-def", tokens.access_token
    assert_equal "refresh-token-ghi", tokens.refresh_token
  end

  # ── sign_in MFA challenge ──────────────────────────────────────────

  def test_sign_in_mfa_challenge
    http = mock_http do |_target, _body|
      Attago::Testing::MockResponse.new(code: 200, body: {
        "ChallengeName" => "SOFTWARE_TOKEN_MFA",
        "Session" => "mfa-session-xyz"
      })
    end

    auth = make_auth(http_client: http)
    err = assert_raises(Attago::MfaRequiredError) { auth.sign_in }
    assert_equal "mfa-session-xyz", err.session
    assert_equal "SOFTWARE_TOKEN_MFA", err.challenge_name
  end

  # ── sign_in auth error ─────────────────────────────────────────────

  def test_sign_in_auth_error
    http = mock_http do |_target, _body|
      Attago::Testing::MockResponse.new(code: 400, body: {
        "__type" => "com.amazonaws.cognito#NotAuthorizedException",
        "message" => "Incorrect username or password."
      })
    end

    auth = make_auth(http_client: http)
    err = assert_raises(Attago::AuthError) { auth.sign_in }
    assert_equal "NotAuthorizedException", err.code
    assert_includes err.message, "Incorrect username or password"
  end

  # ── set_tokens / get_id_token ──────────────────────────────────────

  def test_set_tokens_get_id_token
    auth = make_auth
    tokens = Attago::CognitoTokens.new(
      id_token: "manual-id-token",
      access_token: "manual-access",
      refresh_token: "manual-refresh"
    )
    auth.set_tokens(tokens)
    assert_equal "manual-id-token", auth.get_id_token
  end

  # ── get_id_token auto sign-in ──────────────────────────────────────

  def test_get_id_token_auto_signin
    http = mock_http do |_target, _body|
      Attago::Testing::MockResponse.new(code: 200, body: success_auth_result)
    end

    auth = make_auth(http_client: http)
    # No tokens set, should auto-sign-in
    token = auth.get_id_token
    assert_equal "id-token-abc", token
  end

  # ── sign_out ────────────────────────────────────────────────────────

  def test_sign_out_clears_tokens
    auth = make_auth
    auth.set_tokens(Attago::CognitoTokens.new(
      id_token: "id", access_token: "acc", refresh_token: "ref"
    ))
    auth.sign_out
    assert_nil auth.get_tokens
  end

  # ── respond_to_mfa ─────────────────────────────────────────────────

  def test_respond_to_mfa_success
    http = mock_http do |target, _body|
      if target.include?("RespondToAuthChallenge")
        Attago::Testing::MockResponse.new(code: 200, body: success_auth_result)
      else
        Attago::Testing::MockResponse.new(code: 200, body: success_auth_result)
      end
    end

    auth = make_auth(http_client: http)
    tokens = auth.respond_to_mfa("session-abc", "123456")

    assert_kind_of Attago::CognitoTokens, tokens
    assert_equal "id-token-abc", tokens.id_token
  end

  # ── CognitoTokens inspect redacts secrets ──────────────────────────

  def test_tokens_inspect_redacted
    tokens = Attago::CognitoTokens.new(
      id_token: "secret-id-token",
      access_token: "secret-access-token",
      refresh_token: "secret-refresh-token"
    )
    inspect_str = tokens.inspect
    refute_includes inspect_str, "secret-id-token"
    refute_includes inspect_str, "secret-access-token"
    refute_includes inspect_str, "secret-refresh-token"
    assert_includes inspect_str, "***"
  end

  # ── Cognito header verification ────────────────────────────────────

  def test_cognito_header_verification
    captured_target = nil
    http = mock_http do |target, _body|
      captured_target = target
      Attago::Testing::MockResponse.new(code: 200, body: success_auth_result)
    end

    auth = make_auth(http_client: http)
    auth.sign_in

    assert_equal "AWSCognitoIdentityProviderService.InitiateAuth", captured_target
  end

  # ── HTTP error before JSON decode ──────────────────────────────────

  def test_http_error_before_json_decode
    http = mock_http do |_target, _body|
      Attago::Testing::MockResponse.new(code: 503, body: "Service Unavailable")
    end

    auth = make_auth(http_client: http)
    err = assert_raises(Attago::AuthError) { auth.sign_in }
    assert_equal "UnknownError", err.code
    assert_includes err.message, "HTTP 503"
  end

  # ── Class-level sign_up ─────────────────────────────────────────────

  def test_class_sign_up
    captured_target = nil
    http = mock_http do |target, _body|
      captured_target = target
      Attago::Testing::MockResponse.new(code: 200, body: { "UserConfirmed" => false })
    end

    result = Attago::CognitoAuth.sign_up(
      email: "new@example.com",
      password: "Pass123!",
      client_id: "cid",
      http_client: http
    )

    assert_equal "AWSCognitoIdentityProviderService.SignUp", captured_target
    assert_equal false, result["UserConfirmed"]
  end

  # ── get_tokens returns set tokens ──────────────────────────────────

  def test_get_tokens_returns_nil_initially
    auth = make_auth
    assert_nil auth.get_tokens
  end
end
