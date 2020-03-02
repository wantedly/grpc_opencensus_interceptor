require "opencensus"
require "grpc"

require "grpc_opencensus_interceptor/client_interceptor"
require "grpc_opencensus_interceptor/server_interceptor"
require "grpc_opencensus_interceptor/util"
require "grpc_opencensus_interceptor/version"

module GrpcOpencensusInterceptor
  class << self
    def new(options = {})
      ServerInterceptor.new(**options)
    end
  end
end
