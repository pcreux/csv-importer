module CSVImporter
  # The configuration of a CSVImporter
  class Config
    attr_accessor :model, :column_definitions, :identifiers, :when_invalid, :after_build_blocks, :after_save_blocks

    def initialize(model: nil, column_definitions: [], identifiers: nil, when_invalid: :skip, after_build_blocks: [], after_save_blocks: [])
      @model = model
      @column_definitions = column_definitions
      @identifiers = identifiers
      @when_invalid = when_invalid
      @after_build_blocks = after_build_blocks
      @after_save_blocks = after_save_blocks
    end

    def initialize_copy(orig)
      super
      @column_definitions = orig.column_definitions.dup
      @identifiers = orig.identifiers.dup
      @after_save_blocks = orig.after_save_blocks.dup
      @after_build_blocks = orig.after_build_blocks.dup
    end

    def after_build(block)
      after_build_blocks << block
    end

    def after_save(block)
      after_save_blocks << block
    end
  end
end
