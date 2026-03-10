# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/test_*.rb"].exclude("test/conformance/**")
end

Rake::TestTask.new(:conformance) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/conformance/**/test_*.rb"]
end

task default: :test
