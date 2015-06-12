# CSVImporter

Importing a CSV file is easy to code until real users attempt to import
real data.

CSVImporter aims to handle validations, column mapping, import
and reporting.

[![Build
Status](https://travis-ci.org/BrewhouseTeam/csv-importer.svg)](https://travis-ci.org/BrewhouseTeam/csv-importer)
[![Code
Climate](https://codeclimate.com/github/BrewhouseTeam/csv-importer/badges/gpa.svg)](https://codeclimate.com/github/BrewhouseTeam/csv-importer)
[![Test
Coverage](https://codeclimate.com/github/BrewhouseTeam/csv-importer/badges/coverage.svg)](https://codeclimate.com/github/BrewhouseTeam/csv-importer/coverage)

## Rationale

Importing CSV files seems easy until you deal with *real* users uploading
their *real* CSV file. You then have to deal with ASCII-8BIT formats,
missing columns, empty rows, malformed headers, wild separators, etc.
Reporting progress and errors to the end-user is also key for a good
experience.

I went through this many times so I decided to build CSV Importer to
save us a lot of trouble.


CSV Importer provides:

* a DSL to define the mapping between CSV columns and your model
* good reporting to the end user
* support for wild encodings and CSV formats.

## Usage

Define your CSVImporter:

```ruby
class ImportUserCSV
  include CSVImporter

  model User

  column :email, to: ->(email) { email.downcase }, required: true
  column :first_name, as: [ /first.?name/i, /pr(é|e)nom/i ]
  column :last_name,  as: [ /last.?name/i, "nom" ]
  column :published,  to: ->(published, model) { model.published_at = published ? Time.now : nil }

  identifier :email # will find_or_update via :email

  when_invalid :skip # or :abort
end
```

Let's run an new import:

```ruby
# Import a file (IOStream or file path) and from CSV content

import = ImportUserCSV.new(file: InputStream)
import = ImportUserCSV.new(path: String)
import = ImportUserCSV.new(content: String)

# Validate header

import.valid_header?
  # => false
import.report.message
  # => "The following columns are required: email"

# Assume the header was valid, let's run the import!

report = import.run!

report.success? # => true
report.message # => "Import completed. 4 created, 2 updated, 1 failed to update"
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'csv-importer'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install csv-importer

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release` to create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

1. Fork it ( https://github.com/BrewhouseTeam/csv-importer/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
