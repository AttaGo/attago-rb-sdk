# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Attago
  class Client
    USER_AGENT = "attago-ruby/#{VERSION}"
    MAX_ERROR_BODY = 1_048_576   # 1 MB
    MAX_SUCCESS_BODY = 10_485_760 # 10 MB

    attr_reader :base_url,
                :agent, :data, :subscriptions, :payments, :wallets,
                :webhooks, :mcp, :api_keys, :bundles, :push, :messaging,
                :redeem

    def initialize(api_key: nil, signer: nil, email: nil, password: nil,
                   cognito_client_id: nil, cognito_region: DEFAULT_COGNITO_REGION,
                   base_url: DEFAULT_BASE_URL, transport: nil)
      # Auth mode validation -- exactly 0 or 1
      modes = [api_key, signer, (email && password) ? true : nil].compact
      raise ConfigError, "Provide at most one auth mode: api_key, signer, or email+password" if modes.size > 1

      # Cognito needs client_id
      if email && password && !cognito_client_id
        raise ConfigError, "cognito_client_id is required when using email+password auth"
      end

      @api_key = api_key
      @signer = signer
      @base_url = base_url.chomp("/")
      @transport = transport
      @mu = Mutex.new
      @http = nil
      @cognito = nil

      # Cognito auth (wired in auth.rb)
      if email && password
        @cognito = CognitoAuth.new(
          client_id: cognito_client_id,
          region: cognito_region,
          email: email,
          password: password
        )
      end

      # Wire service namespaces
      @agent = AgentService.new(self)
      @data = DataService.new(self)
      @subscriptions = SubscriptionService.new(self)
      @payments = PaymentService.new(self)
      @wallets = WalletService.new(self)
      @webhooks = WebhookService.new(self)
      @mcp = McpService.new(self)
      @api_keys = ApiKeyService.new(self)
      @bundles = BundleService.new(self)
      @push = PushService.new(self)
      @messaging = MessagingService.new(self)
      @redeem = RedeemService.new(self)
    end

    # Core request method -- all services call this.
    # Returns parsed JSON body (Hash) or nil for 204.
    def request(method, path, body: nil, params: nil, headers: nil)
      # Ensure /v1 prefix
      path = "/v1#{path}" unless path.start_with?("/v1")

      uri = URI.parse("#{@base_url}#{path}")
      if params && !params.empty?
        uri.query = URI.encode_www_form(params)
      end

      req_headers = build_headers(headers)
      serialized_body = body.is_a?(Hash) ? JSON.generate(body) : body

      if @signer
        transport = @transport || raw_transport_adapter
        resp = X402.do_with_x402(transport, @signer, method, uri.to_s,
                                  headers: req_headers, body: serialized_body)
      elsif @transport
        resp = @transport.request(method, uri.to_s, headers: req_headers,
                                  body: serialized_body)
      else
        resp = request_raw(method, uri, headers: req_headers, body: serialized_body)
      end

      handle_response(resp)
    end

    # Auth headers (shared method -- MCP uses this, lesson from JS audit)
    def auth_headers
      h = {}
      if @api_key
        h["X-API-Key"] = @api_key
      elsif @cognito
        h["Authorization"] = "Bearer #{@cognito.get_id_token}"
      end
      h
    end

    def close
      @mu.synchronize do
        @http&.finish if @http&.started?
        @http = nil
      end
    end

    private

    # Adapter that wraps request_raw with the transport interface expected by X402.
    # Prevents infinite recursion: Client#request -> x402 -> transport.request -> request_raw
    # instead of looping back through Client#request.
    def raw_transport_adapter
      owner = self
      adapter = Object.new
      adapter.define_singleton_method(:request) do |m, u, headers:, body: nil|
        owner.send(:request_raw, m, u, headers: headers, body: body)
      end
      adapter
    end

    # Internal: raw HTTP request without x402 or routing logic.
    # Used by the raw_transport_adapter and the non-signer/non-transport path.
    def request_raw(method, uri, headers: {}, body: nil)
      parsed = uri.is_a?(URI) ? uri : URI.parse(uri)
      http_request(method, parsed, headers, body)
    end

    def build_headers(extra)
      h = {
        "User-Agent" => USER_AGENT,
        "Accept" => "application/json",
        "Content-Type" => "application/json",
      }
      h.merge!(auth_headers)
      h.merge!(extra) if extra
      h
    end

    def http_request(method, uri, headers, body)
      @mu.synchronize do
        ensure_http(uri)

        req = case method.to_s.upcase
              when "GET"    then Net::HTTP::Get.new(uri)
              when "POST"   then Net::HTTP::Post.new(uri)
              when "PUT"    then Net::HTTP::Put.new(uri)
              when "PATCH"  then Net::HTTP::Patch.new(uri)
              when "DELETE" then Net::HTTP::Delete.new(uri)
              else raise ArgumentError, "Unsupported HTTP method: #{method}"
              end

        headers.each { |k, v| req[k] = v }
        req.body = body if body

        @http.request(req)
      end
    end

    def ensure_http(uri)
      return if @http&.started?

      @http = Net::HTTP.new(uri.host, uri.port)
      @http.use_ssl = (uri.scheme == "https")
      @http.open_timeout = 10
      @http.read_timeout = 30
      @http.start
    end

    def handle_response(resp)
      code = resp.code.to_i

      return nil if code == 204

      # Read body with size cap
      body_str = resp.body || ""
      if code >= 400
        body_str = body_str.byteslice(0, MAX_ERROR_BODY) if body_str.bytesize > MAX_ERROR_BODY
      else
        body_str = body_str.byteslice(0, MAX_SUCCESS_BODY) if body_str.bytesize > MAX_SUCCESS_BODY
      end

      if code >= 400
        handle_error(code, body_str, resp)
      else
        body_str.empty? ? {} : JSON.parse(body_str)
      end
    end

    def handle_error(code, body_str, resp)
      parsed = begin
        JSON.parse(body_str)
      rescue JSON::ParserError
        {}
      end

      msg = parsed["message"] || parsed["error"] || "Request failed"
      resp_headers = {}
      resp.each_header { |k, v| resp_headers[k] = v } if resp.respond_to?(:each_header)

      case code
      when 402
        reqs = X402.parse_payment_required(resp)
        raise PaymentRequiredError.new(
          message: msg,
          body: parsed,
          headers: resp_headers,
          payment_requirements: reqs
        )
      when 429
        retry_after = resp_headers["retry-after"]&.to_i
        raise RateLimitError.new(
          message: msg,
          body: parsed,
          headers: resp_headers,
          retry_after: retry_after
        )
      else
        raise ApiError.new(
          status_code: code,
          message: msg,
          body: parsed,
          headers: resp_headers
        )
      end
    end
  end
end
