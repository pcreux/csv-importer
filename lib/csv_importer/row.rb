module CSVImporter
  # A Row from the CSV file.
  #
  # Using the header, the model_klass and the identifier it builds the model
  # to be persisted.
  class Row
    include Virtus.model

    attribute :header, Header
    attribute :line_number, Integer
    attribute :row_array, Array[String]
    attribute :model_klass
    attribute :identifiers # Array[Symbol] or Proc
    attribute :after_build_blocks, Array[Proc], default: []
    attribute :after_set_attributes_blocks, Array[Proc], default: []
    attribute :default_values, Hash, default: {}
    attribute :skip, Virtus::Attribute::Boolean, default: false

    # The model to be persisted
    def model
      @model ||= begin
        model = find_or_build_model

        set_attributes(model)

        after_set_attributes_blocks.each { |block| instance_exec(model, &block) }
        after_build_blocks.each { |block| instance_exec(model, &block) }
        model
      end
    end

    # A hash with this row's attributes
    def csv_attributes
      @csv_attributes ||= Hash[header.column_names.zip(row_array)]
    end

    # Set attributes
    def set_attributes(model)
      header.columns.each do |column|
        value = csv_attributes[column.name]
        begin
          value = value.dup if value
        rescue TypeError
          # can't dup Symbols, Integer etc...
        end

        next if column.definition.nil?

        set_attribute(model, column, value)
      end

      model
    end

    # Set the attribute using the column_definition and the csv_value
    def set_attribute(model, column, csv_value)
      column_definition = column.definition
      transformer = column_definition.to
      if transformer.respond_to?(:call)
        arity = transformer.is_a?(Proc) ? transformer.arity : transformer.method(:call).arity

        case arity
        when 1 # to: ->(email) { email.downcase }
          model.public_send("#{column_definition.name}=", transformer.call(csv_value))
        when 2 # to: ->(published, post) { post.published_at = Time.now if published == "true" }
          transformer.call(csv_value, model)
        when 3 # to: ->(field_value, post, column) { post.hash_field[column.name] = field_value }
          transformer.call(csv_value, model, column)
        else
          raise ArgumentError, "arity: #{transformer.arity.inspect} - `to` can only have 1, 2 or 3 arguments"
        end
      else
        attribute = column_definition.attribute
        model.public_send("#{attribute}=", csv_value)
      end

      model
    end

    # Error from the model mapped back to the CSV header if we can
    def errors
      Hash[
        model.errors.to_hash.map do |attribute, errors|
          if column_name = header.column_name_for_model_attribute(attribute)
            [column_name, errors.last]
          else
            [attribute, errors.last]
          end
        end
      ]
    end

    def find_or_build_model
      find_model || build_model
    end

    def find_model
      return nil if identifiers.nil?

      model = build_model
      set_attributes(model)

      after_set_attributes_blocks.each { |block| instance_exec(model, &block) }

      identifiers = model_identifiers(model)
      return nil if identifiers.empty?

      query = Hash[
        identifiers.map { |identifier| [ identifier, model.public_send(identifier) ] }
      ]
      model_klass.find_by(query)
    end

    def build_model
      model_klass.new(default_values)
    end

    def skip!
      self.skip = true
    end

    private

    def model_identifiers(model)
      if identifiers.is_a?(Proc)
        [identifiers.call(model)].flatten
      else
        identifiers
      end
    end
  end
end
