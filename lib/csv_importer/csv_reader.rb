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
        cells = CSV.parse(
          sane_content,
          col_sep: separator, quote_char: quote_char, skip_blanks: true,
          external_encoding: source_encoding
        )
        sanitize_cells(encode_cells(cells))
      end
    end

    # Returns the header as an Array of Strings
    def header
      @header ||= csv_rows.first
    end

    # Returns the rows as an Array of Arrays of Strings
    def rows
      @rows ||= csv_rows[1..-1]
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
      csv_content
        .encode(Encoding.find(source_encoding), invalid: :replace, undef: :replace, replace: '') # Remove invalid byte sequences
        .gsub(/\r\r?\n?/, "\n") # Replaces windows line separators with "\n"
    end

    SEPARATORS = [",", ";", "\t"]

    def detect_separator(csv_content)
      SEPARATORS.min_by do |separator|
        csv_content.count(separator)

        all_lines = csv_content.lines
        base_number = all_lines.first.count(separator)

        if base_number.zero?
          Float::MAX
        else
          all_lines.map{|line| line.count(separator) - base_number }.map(&:abs).inject(0) { |sum, i| sum + i }
        end
      end
    end

    # Remove trailing white spaces and ensure we always return a string
    def sanitize_cells(rows)
      rows.map do |cells|
        cells.map do |cell|
          cell ? cell.strip : ""
        end
      end
    end

    def encode_cells(rows)
      rows.map do |cells|
        cells.map do |cell|
          cell ? cell.encode(target_encoding) : ""
        end
      end
    end

    def source_encoding
      encoding.split(':').first || 'UTF-8'
    end

    def target_encoding
      encoding.split(':').last || 'UTF-8'
    end
  end
end
