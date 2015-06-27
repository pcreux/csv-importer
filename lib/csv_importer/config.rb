module CSVImporter
  # The configuration of a CSVImporter
  class Config
    include Virtus.model

    attribute :model
    attribute :column_definitions, Array[ColumnDefinition], default: proc { [] }
    attribute :identifiers, Array[Symbol], default: []
    attribute :when_invalid, Symbol, default: proc { :skip }
    attribute :after_build_blocks, Array[Proc], default: []

    def after_build(block)
      self.after_build_blocks << block
    end
  end
end

