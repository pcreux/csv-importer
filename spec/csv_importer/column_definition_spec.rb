require "spec_helper"

module CSVImporter
  describe ColumnDefinition do
    describe '.meta' do
      it 'defaults to an empty Hash' do
        expect(subject.meta).to eq(Hash.new)
      end

      it 'does not transform values' do
        subject.meta[:key] = 19.0

        expect(subject.meta[:key]).to eq(19.0)
      end

      it 'does not transform keys' do
        subject.meta['key'] = 19.0

        expect(subject.meta[:key]).to eq(nil)
      end
    end

    describe "#match?" do

      matcher :match do |name|
        match { |column_definition| column_definition.match?(name) }
      end

      subject { ColumnDefinition.new(described_class) }

      context(name: :email) do
        [ "email", "Email", "EMAIL" ].each do |name|
          it { should match(name) }
        end

        [ "e-mail", "bob", nil ].each do |name|
          it { should_not match(name) }
        end
      end

      context(name: :first_name) do
        [ "first name", "first_name", "First name" ].each do |name|
          it { should match(name) }
        end

        [ "first-name", "firstname" ].each do |name|
          it { should_not match(name) }
        end
      end

      context(name: :first_name, as: /first.?name/i) do
        [ "first name", "first_name", "First name", "first-name", "Firstname" ].each do |name|
          it { should match(name) }
        end

        [ "lastname" ].each do |name|
          it { should_not match(name) }
        end
      end

      context(name: :email, as: [:email, "courriel", /e.mail/i]) do
        [ "email", "Email", "EMAIL", "E-mail", "courriel", "Courriel" ].each do |name|
          it { should match(name) }
        end
      end

      context(name: :email, as: {not: :valid}) do
        it "should raise an error" do
          expect { subject.match?("hello") }.to raise_error(Error)
        end
      end
    end
  end
end
