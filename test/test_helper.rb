# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "attago"
require "minitest/autorun"
require "json"
require "net/http"
require "uri"

# ── Mock HTTP transport ──────────────────────────────────────────────
# Captures requests and returns canned responses for unit testing.

module Attago
  module Testing
    # A mock HTTP response matching the interface of Net::HTTPResponse.
    class MockResponse
      attr_reader :code, :body, :header

      def initialize(code:, body: nil, headers: {})
        @code = code.to_s
        @body = body.is_a?(Hash) ? JSON.generate(body) : (body || "")
        @header = headers.transform_keys(&:downcase)
      end

      def [](key)
        @header[key.downcase]
      end

      def each_header(&block)
        @header.each(&block)
      end

      def content_type
        @header["content-type"] || "application/json"
      end
    end

    # Records requests and returns mock responses.
    class MockTransport
      attr_reader :requests

      def initialize(&handler)
        @handler = handler
        @requests = []
      end

      def request(http_method, uri, headers: {}, body: nil)
        req = { method: http_method, uri: uri, headers: headers, body: body }
        @requests << req
        @handler.call(req)
      end

      def last_request
        @requests.last
      end
    end
  end
end
