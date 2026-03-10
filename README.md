# attago

[![CI](https://github.com/AttaGo/attago-rb-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/AttaGo/attago-rb-sdk/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/attago.svg)](https://badge.fury.io/rb/attago)

Ruby SDK for the [AttaGo](https://attago.bid) crypto trading dashboard API.

Go/No-Go crypto trading signals, alert subscriptions, x402 payments, webhook
HMAC verification, and MCP JSON-RPC 2.0 -- **zero runtime dependencies**
(stdlib only).

## Install

```ruby
# Gemfile
gem "attago"
```

Or:

```bash
gem install attago
```

Requires **Ruby 3.1+**.

## Quick Start

### API Key (agent endpoints)

```ruby
require "attago"

client = Attago::Client.new(api_key: "ak_live_...")

score = client.agent.get_score("BTC")
puts score.composite.signal      # "GO", "NO-GO", or "NEUTRAL"
puts score.composite.score       # 0-100
puts score.composite.confidence  # 0.0-1.0

client.close
```

### x402 Signer (pay-per-request)

```ruby
client = Attago::Client.new(signer: my_signer)

# x402 payment handled transparently
score = client.agent.get_score("ETH")
data = client.agent.get_data("BTC", "ETH", "SOL")
```

### Cognito (account management)

```ruby
client = Attago::Client.new(
  email: "user@example.com",
  password: "...",
  cognito_client_id: "abc123"
)

subs = client.subscriptions.list
status = client.payments.status

client.close
```

## Auth Modes

Exactly one auth mode per client. Mix-and-match raises `ConfigError`.

| Mode | Use Case | Endpoints |
|------|----------|-----------|
| `api_key:` | Scripts, bots, CI | Agent (score, data) |
| `signer:` | Pay-per-request (x402) | Agent (score, data) |
| `email: + password:` | Account management | Subscriptions, wallets, payments, webhooks, API keys, bundles, push, redeem |

No auth is also valid -- public data endpoints only.

## API Reference

| Service | Methods |
|---------|---------|
| `client.agent` | `get_score(symbol)`, `get_data(*symbols)` |
| `client.data` | `get_latest`, `get_token_data(token)`, `get_data_push(id)` |
| `client.subscriptions` | `catalog`, `list`, `create(input)`, `update(id, input)`, `delete(id)` |
| `client.payments` | `subscribe(input)`, `status`, `upgrade_quote(tier, cycle)` |
| `client.wallets` | `register(input)`, `list`, `remove(address)` |
| `client.webhooks` | `create(url)`, `list`, `delete(id)`, `send_test(opts)`, `send_server_test(id)` |
| `client.mcp` | `initialize_session`, `list_tools`, `call_tool(name, args)`, `ping` |
| `client.api_keys` | `create(name)`, `list`, `revoke(id)` |
| `client.bundles` | `list`, `purchase(input)` |
| `client.push` | `list`, `create(input)`, `delete(id)` |
| `client.redeem` | `redeem(code)` |

## Typed Inputs

Service methods that accept structured input use typed structs:

```ruby
# Create a subscription
input = Attago::SubscriptionCreateInput.new(
  token_id: "BTC",
  label: "BTC Price Alert",
  groups: [
    [Attago::Condition.new(
      metric_name: "spotPrice",
      threshold_op: "gte",
      threshold_val: 100_000
    )]
  ],
  cooldown_minutes: 60
)
sub = client.subscriptions.create(input)
```

```ruby
# Register a wallet
input = Attago::WalletRegisterInput.new(
  wallet_address: "0x...",
  chain: "base",
  signature: "0x...",
  timestamp: Time.now.utc.iso8601
)
wallet = client.wallets.register(input)
```

## Webhook Verification

Verify incoming webhook signatures without a full client:

```ruby
body = request.body.read
signature = request.headers["X-AttaGo-Signature"]
secret = "whsec_..."

if Attago::Webhooks.verify_signature(body, secret, signature)
  payload = JSON.parse(body)
  # Handle webhook
else
  # Invalid signature -- reject
end
```

## Webhook Listener

Standalone HTTP server for receiving webhooks in development or background
workers:

```ruby
require "attago"

listener = Attago::WebhookListener.new(secret: "whsec_...", port: 4000)

listener.on_alert do |payload|
  puts "#{payload.alert.token}: #{payload.alert.state}"
end

listener.on_test do |payload|
  puts "Test webhook received"
end

listener.on_error do |err|
  warn "Webhook error: #{err.message}"
end

listener.start  # Runs in a background thread
# ... do other work ...
listener.stop
```

## MCP (Model Context Protocol)

JSON-RPC 2.0 over HTTP for AI agent integration:

```ruby
client = Attago::Client.new(api_key: "ak_live_...")

info = client.mcp.initialize_session
tools = client.mcp.list_tools

result = client.mcp.call_tool("get_score", { "symbol" => "BTC" })
puts result.content.first.text

client.mcp.ping

client.close
```

## Error Handling

```ruby
begin
  score = client.agent.get_score("BTC")
rescue Attago::PaymentRequiredError => e
  puts "Payment required: #{e.message}"
  puts "Requirements: #{e.payment_requirements}"
rescue Attago::RateLimitError => e
  puts "Rate limited, retry after: #{e.retry_after}s"
rescue Attago::ApiError => e
  puts "API error #{e.status_code}: #{e.message}"
rescue Attago::McpError => e
  puts "MCP error #{e.mcp_code}: #{e.mcp_message}"
rescue Attago::AuthError => e
  puts "Auth error: #{e.message}"
rescue Attago::MfaRequiredError => e
  puts "MFA required: #{e.challenge_name}"
end
```

## Configuration

```ruby
client = Attago::Client.new(
  api_key: "ak_live_...",
  base_url: "https://staging.attago.io",  # Default: https://api.attago.bid
)
```

## Testing

The SDK ships with a `MockTransport` for unit testing your integrations:

```ruby
require "attago"

transport = Attago::Testing::MockTransport.new do |req|
  Attago::Testing::MockResponse.new(
    code: 200,
    body: { "token" => "BTC", "composite" => { "score" => 75, "signal" => "GO" } }
  )
end

client = Attago::Client.new(api_key: "test", transport: transport)
score = client.agent.get_score("BTC")
assert_equal "GO", score.composite.signal
```

## Development

```bash
git clone git@github.com:AttaGo/attago-rb-sdk.git
cd attago-rb-sdk
bundle install

# Run unit tests
bundle exec rake test

# Run conformance tests (requires live API)
ATTAGO_BASE_URL=https://api.attago.bid ATTAGO_API_KEY=ak_... bundle exec rake conformance
```

## License

[MIT](LICENSE)
