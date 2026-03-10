# frozen_string_literal: true

module Attago
  # Base error for all AttaGo SDK errors.
  class Error < StandardError; end

  # Client misconfiguration (e.g. multiple auth modes).
  class ConfigError < Error; end

  # HTTP API error returned by the AttaGo API.
  class ApiError < Error
    attr_reader :status_code, :body, :headers

    def initialize(status_code:, message:, body: {}, headers: {})
      @status_code = status_code
      @body = body
      @headers = headers
      super("attago: HTTP #{status_code}: #{message}")
    end
  end

  # 402 Payment Required -- x402 payment needed.
  class PaymentRequiredError < ApiError
    attr_reader :payment_requirements

    def initialize(message:, body: {}, headers: {}, payment_requirements: nil)
      @payment_requirements = payment_requirements
      super(status_code: 402, message: message, body: body, headers: headers)
    end
  end

  # 429 Too Many Requests -- rate limit or abuse ban.
  class RateLimitError < ApiError
    attr_reader :retry_after

    def initialize(message:, body: {}, headers: {}, retry_after: nil)
      @retry_after = retry_after
      super(status_code: 429, message: message, body: body, headers: headers)
    end
  end

  # Cognito authentication error.
  class AuthError < Error
    attr_reader :code

    def initialize(message, code: nil)
      @code = code
      prefix = code ? "attago: auth error [#{code}]" : "attago: auth error"
      super("#{prefix}: #{message}")
    end
  end

  # MFA is required to complete sign-in.
  class MfaRequiredError < AuthError
    attr_reader :session, :challenge_name

    def initialize(session:, challenge_name:)
      @session = session
      @challenge_name = challenge_name
      super("MFA required (#{challenge_name})")
    end
  end

  # JSON-RPC 2.0 error from the MCP server.
  # Inherits from Error, NOT ApiError -- separate branch.
  class McpError < Error
    attr_reader :mcp_code, :mcp_message, :data

    def initialize(code:, message:, data: nil)
      @mcp_code = code
      @mcp_message = message
      @data = data
      super("attago: MCP error #{code}: #{message}")
    end
  end
end
