# frozen_string_literal: true

require "test_helper"

class TestMcpService < Minitest::Test
  INIT_RESPONSE = {
    "result" => {
      "protocolVersion" => "2025-03-26",
      "capabilities" => { "tools" => { "listChanged" => false } },
      "serverInfo" => { "name" => "attago-mcp", "version" => "1.0.0" },
      "instructions" => "Use tools to query crypto data"
    }
  }.freeze

  LIST_TOOLS_RESPONSE = {
    "result" => {
      "tools" => [
        {
          "name" => "get_score",
          "description" => "Get composite score for a token",
          "inputSchema" => { "type" => "object", "properties" => { "symbol" => { "type" => "string" } } },
          "annotations" => { "x402" => { "maxAmountRequired" => "100000" } }
        },
        {
          "name" => "get_data",
          "description" => "Get full market data",
          "inputSchema" => { "type" => "object" },
          "annotations" => nil
        }
      ]
    }
  }.freeze

  CALL_TOOL_RESPONSE = {
    "result" => {
      "content" => [{ "type" => "text", "text" => '{"score":85}', "data" => nil, "mimeType" => nil }],
      "isError" => false
    }
  }.freeze

  CALL_TOOL_ERROR_RESPONSE = {
    "result" => {
      "content" => [{ "type" => "text", "text" => "Token not found", "data" => nil, "mimeType" => nil }],
      "isError" => true
    }
  }.freeze

  PING_RESPONSE = {
    "result" => {}
  }.freeze

  JSON_RPC_ERROR_RESPONSE = {
    "error" => {
      "code" => -32601,
      "message" => "Method not found",
      "data" => nil
    }
  }.freeze

  def build_transport(response_data)
    Attago::Testing::MockTransport.new do |_req|
      Attago::Testing::MockResponse.new(code: 200, body: response_data)
    end
  end

  def test_initialize_session
    transport = build_transport(INIT_RESPONSE)
    client = Attago::Client.new(api_key: "ak_test", transport: transport)
    svc = Attago::McpService.new(client)

    result = svc.initialize_session
    assert_instance_of Attago::McpServerInfo, result
    assert_equal "2025-03-26", result.protocol_version
    assert_equal "attago-mcp", result.server_info.name
    assert_equal "1.0.0", result.server_info.version
    assert_equal "Use tools to query crypto data", result.instructions

    # Verify envelope shape
    req = transport.last_request
    assert_includes req[:uri], "/v1/mcp"
    assert_equal "POST", req[:method]
    envelope = JSON.parse(req[:body])
    assert_equal "2.0", envelope["jsonrpc"]
    assert_equal "initialize", envelope["method"]
    assert_equal 1, envelope["id"]
    assert_equal "attago-ruby", envelope["params"]["clientInfo"]["name"]
  end

  def test_list_tools
    transport = build_transport(LIST_TOOLS_RESPONSE)
    client = Attago::Client.new(api_key: "ak_test", transport: transport)
    svc = Attago::McpService.new(client)

    result = svc.list_tools
    assert_equal 2, result.size
    assert_instance_of Attago::McpTool, result[0]
    assert_equal "get_score", result[0].name
    assert_equal "Get composite score for a token", result[0].description
    assert_equal "string", result[0].input_schema["properties"]["symbol"]["type"]
    assert_equal "get_data", result[1].name
  end

  def test_call_tool
    transport = build_transport(CALL_TOOL_RESPONSE)
    client = Attago::Client.new(api_key: "ak_test", transport: transport)
    svc = Attago::McpService.new(client)

    result = svc.call_tool("get_score", { "symbol" => "BTC" })
    assert_instance_of Attago::McpToolCallResult, result
    assert_equal false, result.is_error
    assert_equal 1, result.content.size
    assert_equal "text", result.content[0].type
    assert_equal '{"score":85}', result.content[0].text

    # Verify envelope
    envelope = JSON.parse(transport.last_request[:body])
    assert_equal "tools/call", envelope["method"]
    assert_equal "get_score", envelope["params"]["name"]
    assert_equal "BTC", envelope["params"]["arguments"]["symbol"]
  end

  def test_call_tool_no_arguments
    transport = build_transport(CALL_TOOL_RESPONSE)
    client = Attago::Client.new(api_key: "ak_test", transport: transport)
    svc = Attago::McpService.new(client)

    svc.call_tool("get_data")
    envelope = JSON.parse(transport.last_request[:body])
    assert_equal "tools/call", envelope["method"]
    assert_equal({}, envelope["params"]["arguments"])
  end

  def test_ping_returns_nil
    transport = build_transport(PING_RESPONSE)
    client = Attago::Client.new(api_key: "ak_test", transport: transport)
    svc = Attago::McpService.new(client)

    result = svc.ping
    assert_nil result

    envelope = JSON.parse(transport.last_request[:body])
    assert_equal "ping", envelope["method"]
    refute envelope.key?("params")
  end

  def test_json_rpc_error_raises_mcp_error
    transport = build_transport(JSON_RPC_ERROR_RESPONSE)
    client = Attago::Client.new(api_key: "ak_test", transport: transport)
    svc = Attago::McpService.new(client)

    err = assert_raises(Attago::McpError) { svc.list_tools }
    assert_equal(-32601, err.mcp_code)
    assert_equal "Method not found", err.mcp_message
    assert_includes err.message, "MCP error -32601"
  end

  def test_auto_increment_ids
    transport = build_transport(PING_RESPONSE)
    client = Attago::Client.new(api_key: "ak_test", transport: transport)
    svc = Attago::McpService.new(client)

    svc.ping
    first_id = JSON.parse(transport.requests[0][:body])["id"]

    svc.ping
    second_id = JSON.parse(transport.requests[1][:body])["id"]

    svc.ping
    third_id = JSON.parse(transport.requests[2][:body])["id"]

    assert_equal 1, first_id
    assert_equal 2, second_id
    assert_equal 3, third_id
  end

  def test_api_key_header_sent
    transport = build_transport(PING_RESPONSE)
    client = Attago::Client.new(api_key: "ak_my_key", transport: transport)
    svc = Attago::McpService.new(client)

    svc.ping
    req = transport.last_request
    assert_equal "ak_my_key", req[:headers]["X-API-Key"]
  end

  def test_url_targets_mcp
    transport = build_transport(PING_RESPONSE)
    client = Attago::Client.new(api_key: "ak_test", transport: transport)
    svc = Attago::McpService.new(client)

    svc.ping
    assert_includes transport.last_request[:uri], "/v1/mcp"
  end

  def test_call_tool_with_is_error
    transport = build_transport(CALL_TOOL_ERROR_RESPONSE)
    client = Attago::Client.new(api_key: "ak_test", transport: transport)
    svc = Attago::McpService.new(client)

    result = svc.call_tool("get_score", { "symbol" => "INVALID" })
    assert_instance_of Attago::McpToolCallResult, result
    assert_equal true, result.is_error
    assert_equal "Token not found", result.content[0].text
  end
end
