module CSVImporter
  # This Dsl extends a class that includes CSVImporter
  # It is a thin proxy to the Config object
  module Dsl
    def model(model_klass)
      config.model = model_klass
    end

    def column(name, options={})
      config.column_definitions << options.merge(name: name)
    end

    def identifier(identifier)
      config.identifier = identifier
    end

    def when_invalid(action)
      config.when_invalid = action
    end

    def after_build(&block)
      config.after_build = block
    end
  end
end
