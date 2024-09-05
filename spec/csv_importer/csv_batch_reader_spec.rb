require "spec_helper"
require 'stringio'
require 'tempfile'

class StrictIO < StringIO
  def read(length = nil, outbuf = nil)
    raise "Attempt to read entire file at once!" if length.nil?
    super(length, outbuf)
  end

  def readlines(sep = $/, limit = nil)
    raise "Attempt to read entire file at once!" if limit.nil?
    super(sep, limit)
  end
end

class StrictFileIO < File
  def read(length = nil, outbuf = nil)
    raise "Attempt to read entire file at once!" if length.nil?
    super
  end

  def rewind
    raise "Attempt to reqind file"
  end
end

module CSVImporter
  describe CSVBatchReader do
    it "removes invalid byte sequences" do
      content = "email,first_name,\xFFlast_name\x81".force_encoding('ASCII-8BIT')
      reader = CSVBatchReader.new(content: content)
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "handles windows line separators" do
      reader = CSVBatchReader.new(content: "email,first_name,last_name\r\r
                             mark@example.com,mark,example")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "supports comma separated csv" do
      reader = CSVBatchReader.new(content: "email,first_name,last_name")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "supports semicolon separated csv" do
      reader = CSVBatchReader.new(content: "email;first_name;last_name")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "supports semicolon separated csv when content has lot of commas" do
      reader = CSVBatchReader.new(content: "email;first_name;last_name;letter_ids\n
                                      peter@example.com;Peter;Stone;1,2,3,4,5,6,7,8,9,10,11,12,13,14")
      expect(reader.header).to eq ["email", "first_name", "last_name", "letter_ids"]
    end

    it "supports tab separated csv" do
      reader = CSVBatchReader.new(content: "email\tfirst_name\tlast_name")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "supports custom quote character" do
      reader = CSVBatchReader.new(content: "first_name,last_name\n'bob','the builder'", quote_char: "'")
      expect(reader.rows.to_a).to eq [["bob", "the builder"]]
    end

    it "supports custom encoding" do
      reader = CSVBatchReader.new(content: "メール,氏名".encode('SJIS'), encoding: 'SJIS:UTF-8')
      expect(reader.header).to eq ["メール", "氏名"]
    end

    context "with stream batch processing" do
      let(:csv_content) do
        StrictIO.new(
          "email,first_name,last_name\n" +
          "john@example.com,John,Doe\r" + # old Mac format
          "jane@example.com,Jane,Doe\r\n" + # Windows format
          "bob@example.com,Bob,Smith"
        )
      end

      let(:reader) { CSVBatchReader.new(content: csv_content) }

      it "returns header correctly" do
        expect(reader.header).to eq ["email", "first_name", "last_name"]
      end

      it "returns rows as an enumerator" do
        expect(reader.rows).to be_a(Enumerator)
      end

      it "yields rows in batches" do
        rows = reader.rows.to_a
        expect(rows.size).to eq 3
        expect(rows[0]).to eq ["john@example.com", "John", "Doe"]
        expect(rows[1]).to eq ["jane@example.com", "Jane", "Doe"]
        expect(rows[2]).to eq ["bob@example.com", "Bob", "Smith"]
      end

      it "batching mechanism works correctly" do
        expect(reader.rows).to be_a(Enumerator)

        reader.rows.each do |row|
          expect(row).to eq ["john@example.com", "John", "Doe"]
          break # We don't need to process all rows for this test
        end
      end

      it "processes large files in chunks without loading everything into memory" do
        chunk_size = 1000
        total_rows = 2000
        csv_header = "email,first_name,last_name\n"
        csv_row = "john@example.com,John,Doe\n"

        # Create a StringIO object that simulates a large CSV file
        csv_content = StringIO.new.tap do |io|
          io.puts csv_header
          total_rows.times { io.puts csv_row }
          io.rewind
        end

        large_reader = CSVBatchReader.new(file: csv_content)

        expect(large_reader.header).to eq ["email", "first_name", "last_name"]
        expect(large_reader.rows).to be_a(Enumerator)

        rows_processed = 0
        max_rows_per_iteration = 0

        large_reader.rows.each_slice(chunk_size) do |batch|
          rows_in_this_batch = batch.size
          max_rows_per_iteration = [max_rows_per_iteration, rows_in_this_batch].max
          rows_processed += rows_in_this_batch
        end

        expect(rows_processed).to eq total_rows
        expect(max_rows_per_iteration).to eq chunk_size
      end

      it "doesn't load the whole file when reading the header" do
        header = "email,first_name,last_name\n"
        content = header + ("john@example.com,John,Doe\n" * 100)
        strict_io = StrictIO.new(content)

        reader = CSVBatchReader.new(file: strict_io)

        expect { reader.header }.not_to raise_error
        expect(reader.header).to eq ["email", "first_name", "last_name"]
      end
    end

    context "with file stream processing" do
      it "parses a temporary file without loading entire content into memory" do
        # Create a temporary file with CSV content
        temp_file = Tempfile.new(['test_csv', '.csv'])
        begin
          # Write CSV content to the file
          temp_file.write("email,first_name,last_name\n")
          100.times { temp_file.write("user#{_1}@example.com,User,#{_1}\n") }
          temp_file.close

          strict_file = StrictFileIO.new(temp_file.path, 'r')

          # Create a CSVBatchReader instance with the strict IO object
          reader = CSVBatchReader.new(file: strict_file)

          # Check header
          expect(reader.header).to eq ["email", "first_name", "last_name"]

          # Process rows in batches
          rows_processed = 0
          reader.rows.each_slice(10) do |batch|
            rows_processed += batch.size
            # Ensure each row has the correct format
            expect(batch.first).to match(
              [/user\d+@example.com/, "User", /\d+/]
            )
          end

          # Verify all rows were processed
          expect(rows_processed).to eq 100

          # Ensure the file wasn't fully loaded into memory
          expect(reader.instance_variable_get(:@content)).to be_nil
          expect(reader.instance_variable_get(:@file)).to be_a(File)
        ensure
          temp_file.unlink
        end
      end
    end
  end
end
