#!/usr/bin/env ruby
# convert.rb
#
# Reads the JSON files passed as arguments, maps each to OGM Aardvark format
# via Mapper.map, and writes the result to metadata-aardvark/.
#
# Usage: ruby convert.rb <file1.json> [file2.json ...]

require 'json'
require 'fileutils'
require_relative 'mapper'

OUTPUT_DIR = File.join(__dir__, 'metadata-aardvark')

if ARGV.empty?
  warn "Usage: ruby convert.rb <file1.json> [file2.json ...]"
  exit 1
end

FileUtils.mkdir_p(OUTPUT_DIR)

input_files = ARGV

success_count = 0
error_count   = 0

input_files.each do |input_path|
  filename = File.basename(input_path)
  output_path = File.join(OUTPUT_DIR, filename)

  begin
    raw = File.read(input_path, encoding: 'UTF-8')
    dataset = JSON.parse(raw)
    aardvark = Mapper.map(dataset)
    File.write(output_path, JSON.pretty_generate(aardvark))
    success_count += 1
  rescue JSON::ParserError => e
    warn "JSON parse error in #{filename}: #{e.message}"
    error_count += 1
  rescue StandardError => e
    warn "Error processing #{filename}: #{e.message}"
    error_count += 1
  end
end

puts "Done. #{success_count} file(s) converted, #{error_count} error(s)."
