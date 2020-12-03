require "grpc_opencensus_interceptor/server_interceptor/span_modifier"

module GrpcOpencensusInterceptor
  class ServerInterceptor < GRPC::ServerInterceptor

    # @param [#export] exporter The exported used to export captured spans
    #     at the end of the request. Optional: If omitted, uses the exporter
    #     in the current config.
    # @param [SpanModifier, call] span_modifier Modify span if necessary. It
    # takes span, request, call, method as its parameters.
    #
    def initialize(exporter: nil, span_modifier: nil)
      @exporter      = exporter || OpenCensus::Trace.config.exporter
      @span_modifier = span_modifier
      @deserializer  = OpenCensus::Trace::Formatters::Binary.new
    end

    ##
    # Intercept a unary request response call.
    #
    # @param [Object] request
    # @param [GRPC::ActiveCall::SingleReqView] call
    # @param [Method] method
    #
    def request_response(request:, call:, method:)
      context_bin = call.metadata[Util::OPENCENSUS_TRACE_BIN_KEY]
      if context_bin
        context = deserialize(context_bin)
      else
        context = nil
      end

      OpenCensus::Trace.start_request_trace(
        trace_context:          context,
        same_process_as_parent: false) do |span_context|
        begin
          OpenCensus::Trace.in_span get_name(method) do |span|
            modify_span(span, request, call, method)

            start_request(span, call, method)
            begin
              grpc_ex = GRPC::Ok.new
              yield
            rescue StandardError => e
              grpc_ex = Util.to_grpc_ex(e)
              raise e
            ensure
              finish_request(span, grpc_ex)
            end
          end
        ensure
          @exporter.export span_context.build_contained_spans
        end
      end
    end

    # NOTE: For now, we don't support server_streamer, client_streamer and bidi_streamer

  private

    # @param [String] context_bin OpenCensus span context in binary format
    # @return [OpenCensus::Trace::TraceContextData, nil]
    def deserialize(context_bin)
      @deserializer.deserialize(context_bin)
    end

    ##
    # Span name is represented as $package.$service/$method
    # cf. https://github.com/census-instrumentation/opencensus-specs/blob/master/trace/gRPC.md#spans
    #
    # @param [Method] method
    # @return [String]
    def get_name(method)
      "#{method.receiver.class.service_name}/#{camelize(method.name.to_s)}"
    end

    # @param [Method] method
    # @return [String]
    def get_path(method)
      "/" + get_name(method)
    end

    # @param [String] term
    # @return [String]
    def camelize(term)
      term.split("_").map(&:capitalize).join
    end

    ##
    # Modify span by custom span modifier
    #
    # @param [OpenCensus::Trace::SpanBuilder] span
    # @param [Object] request
    # @param [GRPC::ActiveCall::SingleReqView] call
    # @param [Method] method
    def modify_span(span, request, call, method)
      @span_modifier.call(span, request, call, method) if @span_modifier
    end

    # @param [OpenCensus::Trace::SpanBuilder] span
    # @param [GRPC::ActiveCall::SingleReqView] call
    # @param [Method] method
    def start_request(span, call, method)
      span.kind = OpenCensus::Trace::SpanBuilder::SERVER
      span.put_attribute "http.path", get_path(method)
      span.put_attribute "http.method", "POST"  # gRPC always uses "POST"
      if call.metadata['user-agent']
        span.put_attribute "http.user_agent", call.metadata['user-agent']
      end
    end

    # @param [OpenCensus::Trace::SpanBuilder] span
    # @param [GRPC::BadStatus] exception
    def finish_request(span, exception)
      # Set gRPC server status
      # https://github.com/census-instrumentation/opencensus-specs/blob/master/trace/gRPC.md#spans
      span.set_status exception.code
      span.put_attribute "http.status_code", Util.to_http_status(exception)
    end
  end
end
