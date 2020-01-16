require "google/protobuf/empty_pb"
require "google/protobuf/wrappers_pb"

class MockedExporter
  def initialize
    @spans = []
  end

  def export(spans)
    @spans += spans
  end

  attr_reader :spans
end

RSpec.describe GrpcOpencensusInterceptor do
  describe "#request_response" do
    let(:interceptor) {
      GrpcOpencensusInterceptor.new(
        exporter: mocked_exporter,
        **options
      )
    }
    let(:mocked_exporter) {
      MockedExporter.new
    }
    let(:request) { Google::Protobuf::StringValue.new(value: "World") }
    let(:call) { double(:call, peer: "ipv4:127.0.0.1:63634", metadata: metadata) }
    let(:method) { service_class.new.method(:hello_rpc) }
    let(:service_class) {
      Class.new(rpc_class) do
        def self.name
          "TestModule::TestService"
        end

        def hello_rpc(req, call)
          # Do nothing
        end
      end
    }
    let(:rpc_class) {
      Class.new do
        include GRPC::GenericService

        self.marshal_class_method = :encode
        self.unmarshal_class_method = :decode
        self.service_name = 'test.Test'

        rpc :HelloRpc, Google::Protobuf::StringValue, Google::Protobuf::Empty
      end
    }

    context "when a span context exists" do
      let(:options) { {} }
      let(:metadata) {
        {
          "user-agent" => "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)".encode(Encoding::ASCII_8BIT),
          "grpc-trace-bin" => span_context_bin,
        }
      }
      let(:span_context_bin) {
        OpenCensus::Trace::Formatters::Binary.new.serialize(span_context)
      }
      let(:span_context) {
        OpenCensus::Trace::TraceContextData.new(
          "621043dbca82f991bf11871f15106390",  # trace_id
          "e8200af626a5fb10",                  # span_id
          0,                                   # trace_options
        )
      }

      it "export a span with parent_span_id" do
        interceptor.request_response(request: request, call: call, method: method) { }
        expect(mocked_exporter.spans.size).to eq 1
        span = mocked_exporter.spans[0]
        expect(span.name.value).to eq "test.Test/HelloRpc"
        expect(span.status.code).to eq 0
        expect(span.attributes.keys).to contain_exactly(
          "http.path",
          "http.method",
          "http.user_agent",
          "http.status_code")
        expect(span.attributes["http.path"].value).to eq "/test.Test/HelloRpc"
        expect(span.attributes["http.method"].value).to eq "POST"
        expect(span.attributes["http.user_agent"].value).to eq "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)"
        expect(span.attributes["http.status_code"]).to eq 200
        expect(span.trace_id).to eq span_context.trace_id
        expect(span.parent_span_id).to eq span_context.span_id
      end
    end

    context "when a span context doex not exist" do
      let(:options) { {} }
      let(:metadata) {
        {
          "user-agent" => "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)".encode(Encoding::ASCII_8BIT),
        }
      }

      it "export a span without parent_span_id" do
        interceptor.request_response(request: request, call: call, method: method) { }
        expect(mocked_exporter.spans.size).to eq 1
        span = mocked_exporter.spans[0]
        expect(span.name.value).to eq "test.Test/HelloRpc"
        expect(span.status.code).to eq 0
        expect(span.attributes.keys).to contain_exactly(
          "http.path",
          "http.method",
          "http.user_agent",
          "http.status_code")
        expect(span.attributes["http.path"].value).to eq "/test.Test/HelloRpc"
        expect(span.attributes["http.method"].value).to eq "POST"
        expect(span.attributes["http.user_agent"].value).to eq "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)"
        expect(span.attributes["http.status_code"]).to eq 200
        expect(span.trace_id).not_to eq ""  # set random value automatically
        expect(span.parent_span_id).to eq ""
      end
    end

    context "when yield raises GRPC::NotFound" do
      let(:options) { {} }
      let(:metadata) {
        {
          "user-agent" => "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)".encode(Encoding::ASCII_8BIT),
        }
      }

      it "export a span which status is 5 (not found)" do
        expect {
          interceptor.request_response(request: request, call: call, method: method) {
            raise GRPC::NotFound
          }
        }.to raise_error(GRPC::NotFound)
        expect(mocked_exporter.spans.size).to eq 1
        span = mocked_exporter.spans[0]
        expect(span.name.value).to eq "test.Test/HelloRpc"
        expect(span.status.code).to eq 5  # GRPC::NotFound
        expect(span.attributes.keys).to contain_exactly(
          "http.path",
          "http.method",
          "http.user_agent",
          "http.status_code")
        expect(span.attributes["http.path"].value).to eq "/test.Test/HelloRpc"
        expect(span.attributes["http.method"].value).to eq "POST"
        expect(span.attributes["http.user_agent"].value).to eq "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)"
        expect(span.attributes["http.status_code"]).to eq 404
      end
    end

    context "when span_modifier is used" do
      let(:options) {
        {
          span_modifier: -> (span, request, call, method) {
            span.put_attribute "test.test_attribute", "dummy-value"
          }
        }
      }
      let(:metadata) {
        {
          "user-agent" => "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)".encode(Encoding::ASCII_8BIT),
        }
      }

      it "export a modified span" do
        expect {
          interceptor.request_response(request: request, call: call, method: method) {
            raise GRPC::NotFound
          }
        }.to raise_error(GRPC::NotFound)
        expect(mocked_exporter.spans.size).to eq 1
        span = mocked_exporter.spans[0]
        expect(span.name.value).to eq "test.Test/HelloRpc"
        expect(span.status.code).to eq 5  # GRPC::NotFound
        expect(span.attributes.keys).to contain_exactly(
          "http.path",
          "http.method",
          "http.user_agent",
          "http.status_code",
          "test.test_attribute"
        )
        expect(span.attributes["http.path"].value).to eq "/test.Test/HelloRpc"
        expect(span.attributes["http.method"].value).to eq "POST"
        expect(span.attributes["http.user_agent"].value).to eq "grpc-node/1.19.0 grpc-c/7.0.0 (linux; chttp2; gold)"
        expect(span.attributes["http.status_code"]).to eq 404
        expect(span.attributes["test.test_attribute"].value).to eq "dummy-value"
      end
    end
  end
end
