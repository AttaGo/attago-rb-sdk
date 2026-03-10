# frozen_string_literal: true

require_relative "lib/attago/version"

Gem::Specification.new do |spec|
  spec.name = "attago"
  spec.version = Attago::VERSION
  spec.authors = ["AttaGo"]
  spec.email = ["sdk@attago.io"]

  spec.summary = "Ruby SDK for the AttaGo crypto trading dashboard API"
  spec.description = "Go/No-Go crypto trading signals, alert subscriptions, x402 payments, " \
                     "webhook HMAC verification, and MCP JSON-RPC 2.0 — zero runtime deps."
  spec.homepage = "https://attago.bid"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/AttaGo/attago-rb-sdk"
  spec.metadata["documentation_uri"] = "https://attago.bid/docs"

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies — stdlib only (net/http, openssl, json, uri)

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webrick", "~> 1.8"
end
