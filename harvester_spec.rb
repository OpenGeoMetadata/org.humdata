require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'json'
require_relative 'harvester'

# Define a manual stubbing helper on Net::HTTP to bypass Gem/Minitest version conflicts
class << Net::HTTP
  alias_method :original_get_response, :get_response rescue nil

  def get_response(uri)
    if defined?(@custom_get_handler) && @custom_get_handler
      @custom_get_handler.call(uri)
    else
      original_get_response(uri)
    end
  end

  def with_stub_get_response(handler)
    @custom_get_handler = handler
    yield
  ensure
    @custom_get_handler = nil
  end
end

class MockResponse
  attr_reader :body, :code, :message

  def initialize(body, code = "200", message = "OK")
    @body = body
    @code = code
    @message = message
  end

  def is_a?(klass)
    klass == Net::HTTPSuccess || super
  end
end

class HarvesterTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @tmp_dir = Dir.mktmpdir

    # Save original BATCH_SIZE and redefine it to 1 for pagination testing
    @original_batch_size = Harvester::BATCH_SIZE
    Harvester.send(:remove_const, :BATCH_SIZE)
    Harvester.const_set(:BATCH_SIZE, 1)

    # We define our temporary paths inside the temp directory
    @state_file = File.join(@tmp_dir, "state.json")
    @hdx_metadata_dir = File.join(@tmp_dir, "metadata-hdx")
    @aardvark_metadata_dir = File.join(@tmp_dir, "metadata-aardvark")

    # Change to temp directory for absolute filesystem safety
    Dir.chdir(@tmp_dir)
  end

  def teardown
    # Restore constants
    Harvester.send(:remove_const, :BATCH_SIZE)
    Harvester.const_set(:BATCH_SIZE, @original_batch_size)

    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmp_dir)
  end

  def test_load_last_run_default
    harvester = Harvester.new(
      state_file: @state_file,
      hdx_metadata_dir: @hdx_metadata_dir,
      aardvark_metadata_dir: @aardvark_metadata_dir
    )
    last_run = harvester.send(:load_last_run)
    assert_equal Time.parse("2024-01-01T00:00:00Z").utc, last_run
  end

  def test_load_last_run_from_state_file
    state_data = { "last_run" => "2026-06-10T12:00:00Z" }
    File.write(@state_file, JSON.pretty_generate(state_data))

    harvester = Harvester.new(
      state_file: @state_file,
      hdx_metadata_dir: @hdx_metadata_dir,
      aardvark_metadata_dir: @aardvark_metadata_dir
    )
    last_run = harvester.send(:load_last_run)
    assert_equal Time.parse("2026-06-10T12:00:00Z").utc, last_run
  end

  def test_harvester_empty_results
    # Setup initial state in temporary state file path
    state_data = { "last_run" => "2026-06-10T12:00:00Z" }
    File.write(@state_file, JSON.pretty_generate(state_data))

    # Stub Net::HTTP.get_response to return empty results
    mock_resp = MockResponse.new({
      "result" => {
        "results" => [],
        "count" => 0
      }
    }.to_json)

    Net::HTTP.with_stub_get_response(->(uri) { mock_resp }) do
      # Harvester exits when no datasets are fetched
      assert_raises(SystemExit) do
        Harvester.run(
          state_file: @state_file,
          hdx_metadata_dir: @hdx_metadata_dir,
          aardvark_metadata_dir: @aardvark_metadata_dir
        )
      end
    end

    # Confirm directories were not created
    refute File.exist?(@hdx_metadata_dir)
    refute File.exist?(@aardvark_metadata_dir)
  end

  def test_harvester_saves_and_maps_page_by_page
    # Setup initial state in temporary state file path
    state_data = { "last_run" => "2026-06-10T10:00:00Z" }
    File.write(@state_file, JSON.pretty_generate(state_data))

    # Mock responses for pagination:
    # Page 1 (start=0): Returns dataset 1 (newer, should be processed)
    # Page 2 (start=1): Returns dataset 2 (older, should be skipped)
    dataset1 = {
      "id" => "dataset-1",
      "title" => "Test Dataset One",
      "metadata_modified" => "2026-06-10T11:00:00Z" # newer than 10:00:00
    }
    dataset2 = {
      "id" => "dataset-2",
      "title" => "Test Dataset Two",
      "metadata_modified" => "2026-06-10T09:00:00Z" # older than 10:00:00
    }

    requests_made = []

    get_response_handler = ->(uri) {
      requests_made << uri
      params = URI.decode_www_form(uri.query).to_h
      start_offset = params['start'].to_i

      results = if start_offset == 0
                  [dataset1]
                elsif start_offset == 1
                  [dataset2]
                else
                  []
                end

      body = {
        "result" => {
          "results" => results,
          "count" => 2
        }
      }.to_json

      MockResponse.new(body)
    }

    Net::HTTP.with_stub_get_response(get_response_handler) do
      # Run Harvester
      # We expect processed datasets, it should not call exit
      Harvester.run(
        state_file: @state_file,
        hdx_metadata_dir: @hdx_metadata_dir,
        aardvark_metadata_dir: @aardvark_metadata_dir
      )
    end

    # Verify requests
    assert_equal 2, requests_made.size
    assert_match(/start=0/, requests_made[0].query)
    assert_match(/start=1/, requests_made[1].query)

    # Check file outputs in temporary paths
    # dataset-1 (newer) should be saved
    assert File.exist?(File.join(@hdx_metadata_dir, "dataset-1.json"))
    assert File.exist?(File.join(@aardvark_metadata_dir, "dataset-1.json"))

    # dataset-2 (older) should NOT be saved
    refute File.exist?(File.join(@hdx_metadata_dir, "dataset-2.json"))
    refute File.exist?(File.join(@aardvark_metadata_dir, "dataset-2.json"))

    # Verify state.json was updated with current time
    updated_state = JSON.parse(File.read(@state_file))
    refute_equal "2026-06-10T10:00:00Z", updated_state["last_run"]
  end
end
