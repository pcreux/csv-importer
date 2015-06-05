if ENV['CODECLIMATE_REPO_TOKEN']
  require "codeclimate-test-reporter"
  CodeClimate::TestReporter.start
else
  require "simplecov"
  SimpleCov.start
end

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'active_model'

require 'csv_importer'
