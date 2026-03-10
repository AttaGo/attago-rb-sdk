# frozen_string_literal: true

require "json"

module Attago
  class McpService
    def initialize(client)
      @client = client
      @next_id = 0
      @mu = Mutex.new
    end

    # Renamed from `initialize` to avoid Ruby conflict
    def initialize_session
      result = rpc("initialize", {
        "protocolVersion" => "2025-03-26",
        "capabilities" => {},
        "clientInfo" => { "name" => "attago-ruby", "version" => VERSION }
      })
      McpServerInfo.from_hash(result)
    end

    def list_tools
      result = rpc("tools/list")
      (result["tools"] || []).map { |t| McpTool.from_hash(t) }
    end

    def call_tool(name, arguments = {})
      result = rpc("tools/call", { "name" => name, "arguments" => arguments })
      McpToolCallResult.from_hash(result)
    end

    def ping
      rpc("ping")
      nil
    end

    private

    def next_request_id
      @mu.synchronize do
        @next_id += 1
        @next_id
      end
    end

    def rpc(method, params = nil)
      envelope = {
        "jsonrpc" => "2.0",
        "id" => next_request_id,
        "method" => method
      }
      envelope["params"] = params if params

      # Delegate to client.request for auth headers (audit lesson!)
      data = @client.request("POST", "/mcp", body: envelope)

      # Check for JSON-RPC error
      if data.is_a?(Hash) && data["error"]
        err = data["error"]
        raise McpError.new(
          code: err["code"] || -1,
          message: err["message"] || "Unknown MCP error",
          data: err["data"]
        )
      end

      data.is_a?(Hash) ? data["result"] : data
    end
  end
end
