# frozen_string_literal: true

require "test_helper"

class TestConformance < Minitest::Test
  SPEC_DIR = ENV.fetch("ATTAGO_SPEC_DIR", File.expand_path("../../../../attago-spec", __dir__))
  FIXTURE_DIR = File.join(SPEC_DIR, "spec", "fixtures", "rest")
  BASE_URL = ENV["ATTAGO_BASE_URL"]
  API_KEY = ENV["ATTAGO_API_KEY"]

  # Fixtures that require Cognito auth (skip in conformance)
  SKIP_FIXTURES = %w[
    user-profile-success.json
    user-profile-unauthorized.json
  ].freeze

  if BASE_URL && Dir.exist?(FIXTURE_DIR)
    Dir.glob(File.join(FIXTURE_DIR, "*.json")).sort.each do |path|
      basename = File.basename(path)
      next if SKIP_FIXTURES.include?(basename)

      test_name = File.basename(path, ".json").tr("-", "_")

      define_method("test_conformance_#{test_name}") do
        fixture = JSON.parse(File.read(path))
        req = fixture["request"]
        expected = fixture["response"]

        uri = URI.parse("#{BASE_URL}#{req['path']}")
        if req["query"]
          uri.query = URI.encode_www_form(req["query"])
        end

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 10
        http.read_timeout = 30

        http_req = case req["method"]
                   when "GET" then Net::HTTP::Get.new(uri)
                   when "POST" then Net::HTTP::Post.new(uri)
                   when "PUT" then Net::HTTP::Put.new(uri)
                   when "DELETE" then Net::HTTP::Delete.new(uri)
                   end

        # Set headers
        (req["headers"] || {}).each { |k, v| http_req[k] = v }
        http_req["X-API-Key"] = API_KEY if API_KEY
        http_req.body = JSON.generate(req["body"]) if req["body"]

        resp = http.request(http_req)

        # Assert status code
        assert_equal expected["status"], resp.code.to_i,
                     "#{basename}: expected #{expected['status']}, got #{resp.code}"

        # If success, validate key fields exist
        if expected["status"] == 200 && resp.body && !resp.body.empty?
          body = JSON.parse(resp.body)
          validate_schema(body, expected["schema"]) if expected["schema"]
        end
      end
    end
  end

  private

  def validate_schema(body, schema_name)
    case schema_name
    when "agent-score"
      assert body.key?("token"), "Missing 'token'"
      assert body.key?("composite"), "Missing 'composite'"
      assert body["composite"].key?("score"), "Missing 'composite.score'"
      assert body["composite"].key?("signal"), "Missing 'composite.signal'"
    when "agent-data"
      assert body.key?("assets"), "Missing 'assets'"
      assert body.key?("assetOrder"), "Missing 'assetOrder'"
    end
  end
end
