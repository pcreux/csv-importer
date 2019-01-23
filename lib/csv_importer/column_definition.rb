module CSVImporter
  # Define a column. Called from the DSL via `column.
  #
  # Examples
  #
  #   # the csv column "email" will be assigned to the `email` attribute
  #   column :email
  #
  #   # the csv column matching /email/i will be assigned to the `email` attribute
  #   column :email, as: /email/i
  #
  #   # the csv column matching "First name" or "Prénom" will be assigned to the `first_name` attribute
  #   column :first_name, as: [/first ?name/i, /pr(é|e)nom/i]
  #
  #   # the csv column "first_name" will be assigned to the `f_name` attribute
  #   column :first_name, to: :f_name
  #
  #   # email will be downcased
  #   column :email, to: ->(email) { email.downcase }
  #
  #   # transform `confirmed` to `confirmed_at`
  #   column :confirmed, to: ->(confirmed, model) do
  #     model.confirmed_at = confirmed == "true" ? Time.new(2012) : nil
  #   end
  #
  class ColumnDefinition
    include Virtus.model

    attribute :name, Symbol
    attribute :to # Symbol or Proc
    attribute :as # Symbol, String, Regexp, Array
    attribute :required, Virtus::Attribute::Boolean

    # The model attribute that this column targets
    def attribute
      if to.is_a?(Symbol)
        to
      else
        name
      end
    end

    # Return true if column definition matches the column name passed in.
    def match?(column_name, search_query=(as || name))
      return false if column_name.nil?

      downcased_column_name = column_name.downcase
      underscored_column_name = downcased_column_name.gsub(/\s+/, '_')

      case search_query
      when Symbol
        underscored_column_name == search_query.to_s
      when String
        downcased_column_name == search_query.downcase
      when Regexp
        column_name =~ search_query
      when Array
        search_query.any? { |query| match?(column_name, query) }
      else
        raise Error, "Invalid `as`. Should be a Symbol, String, Regexp or Array - was #{as.inspect}"
      end
    end
  end
end
