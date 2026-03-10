# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Attago
  class CognitoAuth
    # Allow injection of an HTTP client for testing.
    attr_writer :http_client

    def initialize(client_id:, region: DEFAULT_COGNITO_REGION, email: nil, password: nil)
      @client_id = client_id
      @region = region
      @email = email
      @password = password
      @tokens = nil
      @mu = Mutex.new  # Thread safety (GO-C1 audit lesson)
      @http_client = nil
    end

    # Sign in and return tokens. Raises MfaRequiredError if MFA challenge.
    def sign_in
      resp = cognito_request("AWSCognitoIdentityProviderService.InitiateAuth", {
        "AuthFlow" => "USER_PASSWORD_AUTH",
        "ClientId" => @client_id,
        "AuthParameters" => {
          "USERNAME" => @email,
          "PASSWORD" => @password
        }
      })

      if resp["ChallengeName"]
        raise MfaRequiredError.new(
          session: resp["Session"],
          challenge_name: resp["ChallengeName"]
        )
      end

      tokens = parse_auth_result(resp["AuthenticationResult"])
      @mu.synchronize { @tokens = tokens }
      tokens
    end

    def sign_out
      @mu.synchronize { @tokens = nil }
    end

    # Returns ID token, auto sign-in if needed.
    def get_id_token
      t = @mu.synchronize { @tokens }
      if t.nil?
        sign_in
        t = @mu.synchronize { @tokens }
      end
      t.id_token
    end

    def set_tokens(tokens)
      @mu.synchronize { @tokens = tokens }
    end

    def get_tokens
      @mu.synchronize { @tokens }
    end

    # Respond to MFA challenge.
    def respond_to_mfa(session, totp_code)
      resp = cognito_request("AWSCognitoIdentityProviderService.RespondToAuthChallenge", {
        "ChallengeName" => "SOFTWARE_TOKEN_MFA",
        "ClientId" => @client_id,
        "Session" => session,
        "ChallengeResponses" => {
          "USERNAME" => @email,
          "SOFTWARE_TOKEN_MFA_CODE" => totp_code
        }
      })

      tokens = parse_auth_result(resp["AuthenticationResult"])
      @mu.synchronize { @tokens = tokens }
      tokens
    end

    # Class-level methods (no instance needed)
    def self.sign_up(email:, password:, client_id:, region: DEFAULT_COGNITO_REGION, http_client: nil)
      auth = new(client_id: client_id, region: region)
      auth.http_client = http_client if http_client
      auth.send(:cognito_request, "AWSCognitoIdentityProviderService.SignUp", {
        "ClientId" => client_id,
        "Username" => email,
        "Password" => password
      })
    end

    def self.confirm_sign_up(email:, code:, client_id:, region: DEFAULT_COGNITO_REGION, http_client: nil)
      auth = new(client_id: client_id, region: region)
      auth.http_client = http_client if http_client
      auth.send(:cognito_request, "AWSCognitoIdentityProviderService.ConfirmSignUp", {
        "ClientId" => client_id,
        "Username" => email,
        "ConfirmationCode" => code
      })
    end

    def self.forgot_password(email:, client_id:, region: DEFAULT_COGNITO_REGION, http_client: nil)
      auth = new(client_id: client_id, region: region)
      auth.http_client = http_client if http_client
      auth.send(:cognito_request, "AWSCognitoIdentityProviderService.ForgotPassword", {
        "ClientId" => client_id,
        "Username" => email
      })
    end

    def self.confirm_forgot_password(email:, code:, new_password:, client_id:, region: DEFAULT_COGNITO_REGION, http_client: nil)
      auth = new(client_id: client_id, region: region)
      auth.http_client = http_client if http_client
      auth.send(:cognito_request, "AWSCognitoIdentityProviderService.ConfirmForgotPassword", {
        "ClientId" => client_id,
        "Username" => email,
        "ConfirmationCode" => code,
        "Password" => new_password
      })
    end

    private

    def parse_auth_result(result)
      CognitoTokens.new(
        id_token: result["IdToken"],
        access_token: result["AccessToken"],
        refresh_token: result["RefreshToken"]
      )
    end

    def cognito_request(target, body)
      if @http_client
        # Use injected HTTP client for testing
        resp = @http_client.call(target, body)
      else
        uri = URI.parse("https://cognito-idp.#{@region}.amazonaws.com/")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 15

        req = Net::HTTP::Post.new("/")
        req["Content-Type"] = "application/x-amz-json-1.1"
        req["X-Amz-Target"] = target
        req.body = JSON.generate(body)

        resp = http.request(req)
      end

      # Check HTTP status BEFORE JSON decode (GO audit I3 lesson)
      unless resp.code.to_i == 200
        begin
          err_body = JSON.parse(resp.body || "")
          err_type = err_body["__type"]&.split("#")&.last || "UnknownError"
          err_msg = err_body["message"] || err_body["Message"] || "Authentication failed"
        rescue JSON::ParserError
          err_type = "UnknownError"
          err_msg = "HTTP #{resp.code}"
        end
        raise AuthError.new(err_msg, code: err_type)
      end

      JSON.parse(resp.body)
    end
  end
end
