require "spec_helper"

module CSVImporter
  describe CSVReader do
    it "removes invalid byte sequences" do
      reader = CSVReader.new(content: "email,first_name,last_name\x81")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end

    it "handles windows line separators" do
      reader = CSVReader.new(content: "email,first_name,last_name\r\r
                             mark@example.com,mark,example")
      expect(reader.header).to eq ["email", "first_name", "last_name"]
    end
  end
end
