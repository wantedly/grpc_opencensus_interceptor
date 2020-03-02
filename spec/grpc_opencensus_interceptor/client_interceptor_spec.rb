require "google/protobuf/empty_pb"

RSpec.describe GrpcOpencensusInterceptor::ClientInterceptor do
  describe "#request_response" do
    subject {
      interceptor.request_response(
        request:  Google::Protobuf::Empty.new,
        call:     double(:call),
        method:   "/test.Test/HelloRpc",
        metadata: metadata) do
        block.call
      end
    }
    let(:interceptor) {
      GrpcOpencensusInterceptor::ClientInterceptor.new(span_context: span_context)
    }
    let(:span_context) { OpenCensus::Trace }
    let(:metadata) { {} }

    context "when not in trace" do
      let(:block) { ->() { Google::Protobuf::Empty.new } }

      it "yields without generating span" do
        expect(span_context).not_to receive(:start_span)
        expect(subject).to eq Google::Protobuf::Empty.new
      end
    end

    context "when in trace" do
      let(:trace_context) {
        OpenCensus::Trace::TraceContextData.new(
          "621043dbca82f991bf11871f15106390",  # trace_id
          "e8200af626a5fb10",                  # span_id
          0,                                   # trace_options
        )
      }

      context "when the execution of block succeeds" do
        let(:block) { ->() { Google::Protobuf::Empty.new } }

        it "yields with generating successful span and set grpc-trace-bin to metadata" do
          span_builders = []

          start_trace(trace_context) do
            expect(subject).to eq Google::Protobuf::Empty.new  # span is generated here
            span_builders = OpenCensus::Trace.span_context.contained_span_builders
          end

          # Check the generated span
          expect(span_builders.size).to eq 1
          span = span_builders[0].to_span
          expect(span.kind).to eq :CLIENT
          expect(span.name.value).to eq "/test.Test/HelloRpc"
          expect(span.status.code).to eq 0
          expect(span.attributes.keys).to contain_exactly(
            "http.path",
            "http.method",
            "http.status_code")
          expect(span.attributes["http.path"].value).to eq "/test.Test/HelloRpc"
          expect(span.attributes["http.method"].value).to eq "POST"
          expect(span.attributes["http.status_code"]).to eq 200
          expect(span.trace_id).to eq trace_context.trace_id

          # Check the metadata
          c = OpenCensus::Trace::Formatters::Binary.new.deserialize(metadata["grpc-trace-bin"])
          expect(c.trace_id).to eq trace_context.trace_id
        end
      end

      context "when the execution of block fails" do
        let(:block) { ->() { raise GRPC::NotFound } }

        it "yields with generating failure span and set grpc-trace-bin to metadata" do
          span_builders = []

          start_trace(trace_context) do
            expect { subject }.to raise_error(GRPC::NotFound)  # span is generated here
            span_builders = OpenCensus::Trace.span_context.contained_span_builders
          end

          # Check the generated span
          expect(span_builders.size).to eq 1
          span = span_builders[0].to_span
          expect(span.kind).to eq :CLIENT
          expect(span.name.value).to eq "/test.Test/HelloRpc"
          expect(span.status.code).to eq 5  # GRPC::NotFound
          expect(span.attributes.keys).to contain_exactly(
            "http.path",
            "http.method",
            "http.status_code")
          expect(span.attributes["http.path"].value).to eq "/test.Test/HelloRpc"
          expect(span.attributes["http.method"].value).to eq "POST"
          expect(span.attributes["http.status_code"]).to eq 404
          expect(span.trace_id).to eq trace_context.trace_id

          # Check the metadata
          c = OpenCensus::Trace::Formatters::Binary.new.deserialize(metadata["grpc-trace-bin"])
          expect(c.trace_id).to eq trace_context.trace_id
        end
      end
    end
  end

  def start_trace(trace_context, &block)
    OpenCensus::Trace.start_request_trace(trace_context: trace_context, same_process_as_parent: false) do
      yield
    end
  end
end
