# frozen_string_literal: true

module Attago
  class WebhookListener
    MAX_BODY_SIZE = 1_048_576  # 1 MB

    def initialize(secret:, port: 4000, host: "127.0.0.1", path: "/webhook")
      require "webrick"  # Lazy load -- optional dependency

      @secret = secret
      @port = port
      @host = host
      @path = path
      @alert_handler = nil
      @test_handler = nil
      @error_handler = nil
      @server = nil
      @thread = nil
    end

    def on_alert(&block)
      @alert_handler = block
      self
    end

    def on_test(&block)
      @test_handler = block
      self
    end

    def on_error(&block)
      @error_handler = block
      self
    end

    def start
      @server = WEBrick::HTTPServer.new(
        Port: @port,
        BindAddress: @host,
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )

      listener = self
      @server.mount_proc(@path) do |req, res|
        listener.send(:handle_request, req, res)
      end

      # Return 404 for other paths (default WEBrick behavior is fine)

      @thread = Thread.new { @server.start }

      # Wait briefly for server to bind
      sleep 0.1

      self
    end

    def stop
      @server&.shutdown
      @thread&.join(5)
      @server = nil
      @thread = nil
    end

    def addr
      "#{@host}:#{actual_port}"
    end

    def actual_port
      @server&.config&.[](:Port) || @port
    end

    def listening?
      !@server.nil? && @thread&.alive?
    end

    private

    def handle_request(req, res)
      # 405 for non-POST (with Allow header)
      unless req.request_method == "POST"
        res.status = 405
        res["Allow"] = "POST"
        res.body = '{"error":"Method not allowed"}'
        return
      end

      # Body size cap (1 MB)
      body = req.body || ""
      if body.bytesize > MAX_BODY_SIZE
        res.status = 413
        res.body = '{"error":"Payload too large"}'
        return
      end

      # HMAC verification
      signature = req["X-AttaGo-Signature"]
      unless signature && Webhooks.verify_signature(body, @secret, signature)
        res.status = 401
        res.body = '{"error":"Invalid signature"}'
        return
      end

      # Parse and dispatch
      payload = JSON.parse(body)
      event = payload["event"]

      case event
      when "alert"
        @alert_handler&.call(WebhookPayload.from_hash(payload))
      when "test"
        @test_handler&.call(WebhookPayload.from_hash(payload))
      end

      res.status = 200
      res.body = '{"ok":true}'
    rescue StandardError => e
      @error_handler&.call(e) if @error_handler
      res.status = 500
      res.body = '{"error":"Internal error"}'
    end
  end
end
