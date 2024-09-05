require 'csv'
require 'stringio'

module CSVImporter

  # Reads, sanitize and parse a CSV file
  class CSVBatchReader < CSVReader

    attr_reader :separator

    def initialize(**kwargs)
      super
      # To avoid reprocessing the stream, let's process & cache the first few lines while detecting the separator
      @separator = detect_separator(lines.take(10).join("\n"))
    end

    # Returns the header as an Array of Strings
    def header
      return @header if @header

      parsed = CSV.parse_line(lines.first, col_sep: separator, quote_char: quote_char, skip_blanks: true,
                              external_encoding: source_encoding)
      @header = encode_cells([parsed])[0]
    end

    # Returns the rows as an Enumerator
    def rows
      @rows ||= csv_enumerator
    end

    private

    def memoized_enumerator(enum, limit = 10)
      cache = []
      Enumerator.new do |yielder|
        # Yield from cache first
        cache.each { |value| yielder << value }

        # Fill cache and yield values from the underlying enumerator
        while cache.size < limit
          begin
            value = enum.next
            cache << value
            yielder << value
          rescue StopIteration
            break
          end
        end

        # Yield the remaining values directly from the original enumerator
        loop do
          begin
            yielder << enum.next
          rescue StopIteration
            break
          end
        end
      end
    end

    def lines
      @lines ||= memoized_enumerator(stream_lines(content_stream))
    end

    def stream_lines(stream, chunk_size = 4096, line_endings_regex = /(\r\n|\r|\n)/)
      Enumerator.new do |yielder|
        case stream
        when StringIO, IO
          buffer = "".force_encoding(source_encoding)
          until stream.eof?
            chunk = stream.read(chunk_size)
            buffer << chunk.force_encoding(source_encoding).encode(Encoding.find(source_encoding), invalid: :replace, undef: :replace, replace: '') # Remove invalid byte sequences

            while (match = buffer.match(line_endings_regex))
              # Yield the part of the buffer before the line ending
              line = sanitize_content(buffer[0...match.begin(0)])
              yielder << line unless line.empty?
              # Remove the processed part (including the line ending)
              buffer = buffer[match.end(0)..-1]
            end
          end

          # Yield any remaining content in the buffer after the end of the file
          yielder << sanitize_content(buffer) unless buffer.empty?
          stream.close if stream.respond_to?(:close)

        when String
          File.open(stream, 'r:' + source_encoding) do |file|
            stream_lines(file, chunk_size, line_endings_regex).each { |line| yielder << line }
          end

        else
          raise ArgumentError, "Unsupported stream type: #{stream.class}"
        end
      end
    end

    def csv_enumerator
      Enumerator.new do |yielder|
        lines.each_with_index do |line, index|
          next if index == 0 # skip header
          row = CSV.parse_line(
            line,
            col_sep: separator,
            quote_char: quote_char,
            skip_blanks: true,
            external_encoding: source_encoding
          )
          yielder << encode_and_sanitize_row(row) if row
        end
      end
    end

    def content_stream
      if content.is_a?(StringIO)
        content
      elsif content.is_a?(String)
        StringIO.new(content)
      elsif file
        file
      elsif path
        File.open(path, 'r')
      else
        raise Error, "Please provide content, file, or path"
      end
    end

    def encode_and_sanitize_row(row)
      row.map do |cell|
        cell ? cell.encode(target_encoding).strip : ""
      end
    end
  end
end
