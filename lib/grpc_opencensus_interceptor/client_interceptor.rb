module GrpcOpencensusInterceptor
  class ClientInterceptor < GRPC::ClientInterceptor
    # @param [SpanContext] span_context The span context within which
    #     to create spans. Optional: If omitted, spans are created in the
    #     current thread-local span context.
    # @param [#call] sampler The sampler to use when creating spans.
    #     Optional: If omitted, uses the sampler in the current config.
    def initialize(span_context: nil, sampler: nil)
      @span_context = span_context || OpenCensus::Trace
      @sampler      = sampler
      @serializer   = OpenCensus::Trace::Formatters::Binary.new
    end

    ##
    # Intercept a unary request response call
    #
    # @param [Object] request
    # @param [GRPC::ActiveCall] call
    # @param [String] method
    # @param [Hash] metadata
    #
    def request_response(request:, call:, method:, metadata:)
      span_context = @span_context
      if span_context == OpenCensus::Trace && !span_context.span_context
        return yield
      end

      # NOTE: Use method as span name
      span_name = method

      span = span_context.start_span span_name, sampler: @sampler
      start_request span, method, metadata
      begin
        grpc_ex = GRPC::Ok.new
        yield
      rescue StandardError => e
        grpc_ex = Util.to_grpc_ex(e)
        raise e
      ensure
        finish_request span, grpc_ex
        span_context.end_span span
      end
    end

    # NOTE: For now, we don't support server_streamer, client_streamer and bidi_streamer

  private

    ##
    # @private Set span attributes
    #
    # @param [OpenCensus::Trace::SpanBuilder] span
    # @param [String] method
    # @param [Hash] metadata
    #
    def start_request span, method, metadata
      span.kind = OpenCensus::Trace::SpanBuilder::CLIENT
      span.put_attribute "http.method", "POST" # NOTE: Always use POST

      span.put_attribute "http.path", method

      # TODO(south37) Set attributes
      # span.put_message_event SpanBuilder::SENT, 1, body_size

      trace_context = @serializer.serialize span.context.trace_context
      metadata[Util::OPENCENSUS_TRACE_BIN_KEY] = trace_context
    end

    ##
    # @private Set span attributes from response
    #
    # @param [OpenCensus::Trace::SpanBuilder] span
    # @param [GRPC::BadStatus] exception
    #
    def finish_request span, exception
      span.set_status exception.code
      span.put_attribute "http.status_code", Util.to_http_status(exception)

      # TODO(south37) Set attributes
      # span.put_message_event SpanBuilder::RECEIVED, 1, body_size
    end
  end
end
