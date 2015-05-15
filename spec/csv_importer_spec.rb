require 'spec_helper'

describe CSVImporter do
  it 'has a version number' do
    expect(CSVImporter::VERSION).not_to be nil
  end

  class User
    include Virtus.model
    include ActiveModel::Model

    attribute :email
    attribute :f_name
    attribute :l_name
    attribute :confirmed_at

    validates_presence_of :email
    validates_format_of :email, with: /[^@]+@[^@]/ # contains one @ symbol
    validates_presence_of :f_name

    def persisted?
      @persisted ||= false
    end

    def save
      if valid?
        @persisted = true
      end
    end

    def self.find_by_email(email)
      STORE.select { |u| u.email == email }.first
    end

    STORE = [
        User.new(email: "mark@example.com", f_name: "mark", l_name: "old last name", confirmed_at: Time.new(2012))
    ].tap { |u| u.map(&:save) }
  end

  class ImportUserCSV
    include CSVImporter

    model User

    column :email, required: true
    column :first_name, to: :f_name, required: true
    column :last_name,  to: :l_name
    column :confirmed,  to: ->(confirmed, model) do
      model.confirmed_at = confirmed == "true" ? Time.new(2012) : nil
    end

    identifier :email # will find_or_update via

    when_invalid :skip # or :abort
  end

  describe "happy path" do
    it 'imports' do
      csv_content = "email,confirmed,first_name,last_name
bob@example.com,true,bob,,"

      import = ImportUserCSV.new(content: csv_content)
      expect(import.rows.size).to eq(1)

      row = import.rows.first

      expect(row.csv_attributes).to eq(
        {
          email: "bob@example.com",
          first_name: "bob",
          last_name: nil,
          confirmed: "true"
        }
      )

      import.run!

      expect(import.report.valid_rows.size).to eq(1)
      expect(import.report.created_rows.size).to eq(1)

      model = import.report.valid_rows.first.model
      expect(model).to be_persisted
      expect(model).to have_attributes(
        email: "bob@example.com",
        f_name: "bob",
        l_name: nil,
        confirmed_at: Time.new(2012)
      )
    end
  end

  describe "invalid records" do
    it "does not import them" do
      csv_content = "email,confirmed,first_name,last_name
  NOT_AN_EMAIL,true,bob,,"
      import = ImportUserCSV.new(content: csv_content)
      import.run!

      expect(import.rows.first.model).to_not be_persisted

      expect(import.report.valid_rows.size).to eq(0)
      expect(import.report.created_rows.size).to eq(0)
      expect(import.report.invalid_rows.size).to eq(1)
      expect(import.report.failed_to_create_rows.size).to eq(1)
    end

    it "maps errors back to the csv header column name" do
      csv_content = "email,confirmed,first_name,last_name
  bob@example.com,true,,last,"
      import = ImportUserCSV.new(content: csv_content)
      import.run!

      row = import.report.invalid_rows.first
      expect(row.errors.size).to eq(1)
      expect(row.errors).to eq(first_name: "can't be blank")
    end
  end

  describe "missing required columns" do
    let(:csv_content) do
"confirmed,first_name,last_name
bob@example.com,true,,last,"
    end

    let(:import) { ImportUserCSV.new(content: csv_content) }

    it "lists missing required columns" do
      expect(import.header.missing_required_columns).to eq([:email])
    end

    it "is not a valid header" do
      expect(import.header).to_not be_valid
    end

    it "raises an error if you attempt to run the import" do
      expect { import.run! }.to raise_error CSVImporter::Error
    end
  end

  describe "missing columns" do
    it "lists missing columns" do
      csv_content = "email,first_name,
  bob@example.com,bob,"
      import = ImportUserCSV.new(content: csv_content)

      expect(import.header.missing_required_columns).to be_empty
      expect(import.header.missing_columns).to eq([:last_name, :confirmed])
    end
  end

  describe "extra columns" do
    it "lists extra columns" do
      csv_content = "email,confirmed,first_name,last_name,age
  bob@example.com,true,,last,"
      import = ImportUserCSV.new(content: csv_content)

      expect(import.header.extra_columns).to eq([:age])
    end
  end

  describe "find or create" do
    it "finds or create via identifier" do
      csv_content = "email,confirmed,first_name,last_name
bob@example.com,true,bob,,
mark@example.com,false,mark,new_last_name"
      import = ImportUserCSV.new(content: csv_content)

      import.run!

      expect(import.report.valid_rows.size).to eq(2)
      expect(import.report.created_rows.size).to eq(1)
      expect(import.report.updated_rows.size).to eq(1)

      model = import.report.created_rows.first.model
      expect(model).to be_persisted
      expect(model).to have_attributes(
        email: "bob@example.com",
        f_name: "bob",
        l_name: nil,
        confirmed_at: Time.new(2012)
      )

      model = import.report.updated_rows.first.model
      expect(model).to be_persisted
      expect(model).to have_attributes(
        email: "mark@example.com",
        f_name: "mark",
        l_name: "new_last_name",
        confirmed_at: nil
      )
    end
  end

end
