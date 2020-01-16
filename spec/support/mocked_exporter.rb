module Support
  class MockedExporter
    def initialize
      @spans = []
    end

    def export(spans)
      @spans += spans
    end

    attr_reader :spans
  end
end
