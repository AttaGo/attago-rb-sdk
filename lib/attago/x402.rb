# frozen_string_literal: true

require "base64"
require "json"

module Attago
  module X402
    module_function

    # Parse X-Payment header from a 402 response into X402PaymentRequirements.
    def parse_payment_required(resp)
      headers = if resp.respond_to?(:each_header)
                  h = {}
                  resp.each_header { |k, v| h[k] = v }
                  h
                elsif resp.is_a?(Hash)
                  resp
                else
                  {}
                end

      raw = headers["x-payment"] || headers["X-Payment"]
      return nil unless raw

      decoded = begin
        Base64.strict_decode64(raw)
      rescue ArgumentError
        begin
          Base64.urlsafe_decode64(raw)
        rescue ArgumentError
          return nil
        end
      end

      data = JSON.parse(decoded)
      X402PaymentRequirements.from_hash(data)
    rescue JSON::ParserError
      nil
    end

    # Find first accepted payment matching network.
    def filter_accepts_by_network(accepts, network)
      accepts.find { |a| a.network == network }
    end

    # Execute request, handle 402 auto-sign-and-retry with x402 signer.
    # CRITICAL: params must be forwarded (lesson from Python audit PY-C2)
    def do_with_x402(transport, signer, method, url, headers:, body: nil, params: nil)
      resp = transport.request(method, url, headers: headers, body: body)
      return resp unless resp.code.to_i == 402

      reqs = parse_payment_required(resp)
      return resp unless reqs

      accepted = filter_accepts_by_network(reqs.accepts, signer.network)
      unless accepted
        resp_headers = {}
        if resp.respond_to?(:each_header)
          resp.each_header { |k, v| resp_headers[k] = v }
        end
        raise PaymentRequiredError.new(
          message: "No accepted payment for network #{signer.network}",
          body: {},
          headers: resp_headers,
          payment_requirements: reqs
        )
      end

      payment = signer.sign(reqs)
      retry_headers = headers.merge("X-Payment" => payment)
      transport.request(method, url, headers: retry_headers, body: body)
    end
  end
end
