module CSVImporter
  # The configuration of a CSVImporter
  class Config
    include Virtus.model

    attribute :model
    attribute :column_definitions, Array[ColumnDefinition], default: proc { [] }
    attribute :identifiers, Array[Symbol], default: []
    attribute :when_invalid, Symbol, default: proc { :skip }
    attribute :after_build_blocks, Array[Proc], default: []
    attribute :after_save_blocks, Array[Proc], default: []

    def after_build(block)
      self.after_build_blocks << block
    end

    def after_save(block)
      self.after_save_blocks << block
    end

    def dup
      # Make sure we dup the attributes as well as variable itself
      self.class.new(attribute_set.get(self))
    end
    alias clone dup
  end
end

