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

    def identifier(*params)
      config.identifiers = params.first.is_a?(Proc) ? params.first : params
    end

    alias_method :identifiers, :identifier

    def when_invalid(action)
      config.when_invalid = action
    end

    def after_build(&block)
      config.after_build(block)
    end

    def after_set_attributes(&block)
      config.after_set_attributes(block)
    end

    def after_save(&block)
      config.after_save(block)
    end
  end
end
