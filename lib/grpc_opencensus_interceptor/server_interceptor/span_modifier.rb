module GrpcOpencensusInterceptor
  class ServerInterceptor < GRPC::ServerInterceptor
    ##
    # Modify span by request, call, method if necessary
    #
    class SpanModifier
      # @param [OpenCensus::Trace::SpanBuilder] span
      # @param [Object] request
      # @param [GRPC::ActiveCall::SingleReqView] call
      # @param [Method] method
      def call(span, request, call, method)
        # Do something necessary
      end
    end
  end
end
