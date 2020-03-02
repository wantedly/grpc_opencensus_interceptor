module GrpcOpencensusInterceptor
  module Util
    OPENCENSUS_TRACE_BIN_KEY = "grpc-trace-bin".freeze

    class << self
      # cf. https://github.com/grpc/grpc/blob/master/doc/http-grpc-status-mapping.md
      # cf. https://github.com/census-instrumentation/opencensus-specs/blob/master/trace/HTTP.md#mapping-from-http-status-codes-to-trace-status-codes
      #
      # @param [GRPC::BadStatus] exception
      # @return [Integer]
      def to_http_status(exception)
        case exception
        when GRPC::Ok
          200
        when GRPC::InvalidArgument
          400
        when GRPC::DeadlineExceeded
          504
        when GRPC::NotFound
          404
        when GRPC::PermissionDenied
          403
        when GRPC::Unauthenticated
          401
        when GRPC::Aborted
          # For GRPC::Aborted, grpc-gateway uses 409. We do the same.
          # cf. https://github.com/grpc-ecosystem/grpc-gateway/blob/e8db07a3923d3f5c77dbcea96656afe43a2757a8/runtime/errors.go#L17-L58
          409
        when GRPC::ResourceExhausted
          429
        when GRPC::Unimplemented
          501
        when GRPC::Unavailable
          503
        when GRPC::Unknown
          # NOTE: This is not same with the correct mapping
          500
        else
          # NOTE: Here, we use 500 temporarily.
          500
        end
      end

      # @param [Exception] e
      # @return [GRPC::BadStatus] e
      def to_grpc_ex(e)
        case e
        when GRPC::BadStatus
          e
        else
          GRPC::Unknown.new(e.message)
        end
      end
    end
  end
end
