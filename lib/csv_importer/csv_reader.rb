module CSVImporter

  # Reads, sanitize and parse a CSV file
  class CSVReader
    include Virtus.model

    attribute :content, String
    attribute :file # IO
    attribute :path, String
    attribute :quote_char, String, default: '"'
    attribute :encoding, String, default: 'UTF-8:UTF-8'

    def csv_rows
      @csv_rows ||= begin
        sane_content = sanitize_content(read_content)
        separator = detect_separator(sane_content)
        cells = CSV.parse(sane_content, col_sep: separator, quote_char: quote_char, skip_blanks: true, encoding: encoding)
        sanitize_cells(cells)
      end
    end

    def add_row(args)
      cells = Array.new(header.size, "")
      args.stringify_keys!

      args.each do |h, val|
        if header.include?(h)
          cells.insert(header.index(h), val)
        end
      end

      @csv_rows = sanitize_cells(@csv_rows << cells)
      @rows = csv_rows[1..-1]
    end

    # Returns the header as an Array of Strings
    def header
      @header ||= csv_rows.first
    end

    # Returns the rows as an Array of Arrays of Strings
    def rows
      @rows ||= csv_rows[1..-1]
    end

    # Gets the value for a specific row array at the header_string column
    def get_from_row_array(row_array, header_string)
      idx = header.index(header_string)
      if row_array.size >= idx
        row_array[idx]
      end
    end

    # Sets the value for a specific row array at the header_string column
    def set_in_row_array(row_array, header_string, val)
      idx = header.index(header_string)
      if row_array.size >= idx
        row_array[idx] = val
      end
    end

    private

    def read_content
      if content
        content
      elsif file
        file.read
      elsif path
        File.open(path).read
      else
        raise Error, "Please provide content, file, or path"
      end
    end

    def sanitize_content(csv_content)
      internal_encoding = encoding.split(':').last
      csv_content
        .encode(Encoding.find(internal_encoding), {invalid: :replace, undef: :replace, replace: ''}) # Remove invalid byte sequences
        .gsub(/\r\r?\n?/, "\n") # Replaces windows line separators with "\n"
    end

    SEPARATORS = [",", ";", "\t"]

    def detect_separator(csv_content)
      SEPARATORS.sort_by { |separator| csv_content.count(separator) }.last
    end

    # Remove trailing white spaces and ensure we always return a string
    def sanitize_cells(rows)
      rows.map do |cells|
        cells.map do |cell|
          cell ? cell.strip : ""
        end
      end
    end
  end
end
