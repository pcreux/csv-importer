require "spec_helper"

module CSVImporter
  describe CSVReader do
    it "removes invalid byte sequences" do
      content = "email,first_name,\xFFlast_name\x81".force_encoding('ASCII-8BIT')
      reader = CSVReader.new(content: content)
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "handles windows line separators" do
      reader = CSVReader.new(content: "email,first_name,last_name\r\r
                             mark@example.com,mark,example")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "supports comma separated csv" do
      reader = CSVReader.new(content: "email,first_name,last_name")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "supports semicolon separated csv" do
      reader = CSVReader.new(content: "email;first_name;last_name")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "supports tab separated csv" do
      reader = CSVReader.new(content: "email\tfirst_name\tlast_name")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "supports custom quote character" do
      reader = CSVReader.new(content: "first_name,last_name\n'bob','the builder'", quote_char: "'")
      expect(reader.rows).to eq [["bob", "the builder"]]
    end
  end
end
