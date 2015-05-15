require "bundler/gem_tasks"

desc "Run specs"
task :test do
  system("bundle exec rspec spec") || exit(-1)
end

task default: :test
