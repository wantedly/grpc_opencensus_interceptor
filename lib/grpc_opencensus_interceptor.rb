require "grpc_opencensus_interceptor/version"
require "grpc_opencensus_interceptor/server_interceptor"

module GrpcOpencensusInterceptor
  class << self
    def new(options = {})
      ServerInterceptor.new(**options)
    end
  end
end
