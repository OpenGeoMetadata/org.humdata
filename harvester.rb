require 'net/http'
require 'json'
require 'time'
require 'fileutils'
require 'securerandom'
require_relative 'mapper'

class Harvester
  HDX_API_URL = "https://data.humdata.org/api/3/action/package_search"
  BATCH_SIZE = 1000

  # Default paths for production datastores
  STATE_FILE = "state.json"
  HDX_METADATA_DIR = "metadata-hdx"
  AARDVARK_METADATA_DIR = "metadata-aardvark"

  def self.run(state_file: STATE_FILE, hdx_metadata_dir: HDX_METADATA_DIR, aardvark_metadata_dir: AARDVARK_METADATA_DIR)
    new(
      state_file: state_file,
      hdx_metadata_dir: hdx_metadata_dir,
      aardvark_metadata_dir: aardvark_metadata_dir
    ).run
  end

  attr_reader :state_file, :hdx_metadata_dir, :aardvark_metadata_dir

  def initialize(state_file: STATE_FILE, hdx_metadata_dir: HDX_METADATA_DIR, aardvark_metadata_dir: AARDVARK_METADATA_DIR)
    @state_file = state_file
    @hdx_metadata_dir = hdx_metadata_dir
    @aardvark_metadata_dir = aardvark_metadata_dir
  end

  def run
    last_run = load_last_run
    puts "Last run date: #{last_run}"

    # Prepare the fq filter
    last_run_str = last_run.strftime('%Y-%m-%dT%H:%M:%SZ')
    fq = "metadata_modified:[#{last_run_str} TO *]"

    start = 0
    total_count = 0
    total_fetched_count = 0
    processed_count = 0
    current_time = Time.now.utc

    loop do
      batch, count = fetch_datasets(fq: fq, start: start)
      break if batch.empty?

      total_count = count
      page_number = (start / BATCH_SIZE) + 1
      puts "Fetching page #{page_number} of #{total_count}"

      total_fetched_count += batch.size
      processed_count += process_batch(batch, last_run)

      start += BATCH_SIZE
      break if start >= total_count
    end

    puts "Fetched #{total_fetched_count} datasets from HDX."
    exit if total_fetched_count == 0

    puts "Processed #{processed_count} new datasets."
    update_last_run(current_time)
  end

  private

  # Process a batch of datasets and return the count of successfully processed new datasets
  def process_batch(batch, last_run)
    processed = 0
    batch.each do |dataset|
      processed += 1 if process_dataset(dataset, last_run)
    end
    processed
  end

  # Process, map, and save a single dataset if it was modified since the last run
  def process_dataset(dataset, last_run)
    # Filter by modified date
    modified_date_str = dataset['metadata_modified']
    return false unless modified_date_str

    modified_date = Time.parse(modified_date_str).utc
    return false unless modified_date > last_run

    # Use the ID for file naming
    id = dataset['id'] || dataset['name'] || "unknown_#{SecureRandom.hex(4)}"

    # Save original
    save_metadata(@hdx_metadata_dir, id, dataset)

    # Map and save Aardvark
    aardvark_data = Mapper.map(dataset)
    save_metadata(@aardvark_metadata_dir, id, aardvark_data)

    puts "Processed #{id}"
    true
  end

  def load_last_run
    if File.exist?(@state_file)
      data = JSON.parse(File.read(@state_file))
      Time.parse(data['last_run']).utc
    else
      Time.parse("2024-01-01T00:00:00Z").utc
    end
  rescue StandardError => e
    puts "Error loading state file: #{e.message}"
    Time.parse("2024-01-01T00:00:00Z").utc
  end

  def update_last_run(time)
    File.write(@state_file, JSON.pretty_generate({ last_run: time.strftime('%Y-%m-%dT%H:%M:%SZ') }))
    puts "Updated state file with: #{time.strftime('%Y-%m-%dT%H:%M:%SZ')}"
  rescue StandardError => e
    puts "Error updating state file: #{e.message}"
  end

  def fetch_datasets(fq: nil, start: 0)
    params = {
      "q" => "has_geodata:true",
      "rows" => BATCH_SIZE,
    }
    params["start"] = start
    params["fq"] = fq if fq

    uri = URI(HDX_API_URL)
    uri.query = URI.encode_www_form(params)

    puts "fetching from #{uri}"
    response = Net::HTTP.get_response(uri)

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      return data.dig('result', 'results') || [], data.dig('result', 'count') || 0
    else
      puts "Error fetching from HDX API: #{response.code} #{response.message}"
      return [], 0
    end
  rescue StandardError => e
    puts "Request error: #{e.message}"
    return [], 0
  end

  def save_metadata(dir, id, data)
    FileUtils.mkdir_p(dir)
    filename = File.join(dir, "#{id}.json")
    File.write(filename, JSON.pretty_generate(data))
  rescue StandardError => e
    puts "Error saving metadata for #{id}: #{e.message}"
  end
end

if __FILE__ == $0
  Harvester.run
end
