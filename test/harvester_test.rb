require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require_relative 'fake_hdx'
require_relative '../harvester'

# Harvests from a fake HDX holding a few datasets, all modified before LAST_RUN unless a test says otherwise
class HarvesterTest < Minitest::Test
  TODAY = Date.new(2026, 10, 8)
  LAST_RUN = '2026-10-08T02:00:00Z'
  IDS = %w[a1 b2 c3 d4 e5].freeze

  def setup
    @tmp_dir = Dir.mktmpdir
    @state_file = File.join(@tmp_dir, 'state.json')
    @hdx_metadata_dir = File.join(@tmp_dir, 'metadata-hdx')
    @aardvark_metadata_dir = File.join(@tmp_dir, 'metadata-aardvark')
    @withdrawn_file = File.join(@tmp_dir, 'withdrawn.json')
    @hdx = FakeHdx.new(IDS.map { |id| dataset(id) })
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def dataset(id, modified: '2026-10-01T12:00:00.000000', **fields)
    { 'id' => id, 'name' => "dataset-#{id}", 'title' => "Dataset #{id.upcase}", 'metadata_modified' => modified,
      'has_geodata' => true }.merge(fields.transform_keys(&:to_s))
  end

  # With five records, one leaving is more than the 2% drop a real run allows
  def harvest(max_shrink: 1.0, **options)
    Harvester.run(state_file: @state_file, hdx_metadata_dir: @hdx_metadata_dir,
                  aardvark_metadata_dir: @aardvark_metadata_dir, withdrawn_file: @withdrawn_file, today: TODAY,
                  log: StringIO.new, http: @hdx, max_shrink: max_shrink, **options)
  end

  # The repository as a first run leaves it, with state.json set to LAST_RUN
  def harvested
    harvest
    write_state(LAST_RUN)
  end

  def write_state(last_run)
    File.write(@state_file, JSON.pretty_generate({ last_run: last_run }))
  end

  def last_run
    JSON.parse(File.read(@state_file))['last_run']
  end

  def record_path(id)
    File.join(@aardvark_metadata_dir, "#{id}.json")
  end

  def hdx_path(id)
    File.join(@hdx_metadata_dir, "#{id}.json")
  end

  def record(id)
    JSON.parse(File.read(record_path(id), mode: 'r:utf-8'))
  end

  def withdrawals
    JSON.parse(File.read(@withdrawn_file, mode: 'r:utf-8'))['withdrawn']
  end

  def remove(id)
    @hdx.datasets = @hdx.datasets.reject { |dataset| dataset['id'] == id }
  end

  def edit(id, **fields)
    @hdx.datasets = @hdx.datasets.map { |dataset| dataset['id'] == id ? dataset.merge(fields.transform_keys(&:to_s)) : dataset }
  end

  def test_a_first_run_saves_every_dataset_and_its_record
    counts = harvest

    assert_equal IDS.size, counts[:created]
    assert_equal 'dataset-a1', JSON.parse(File.read(hdx_path('a1')))['name']
    assert_equal 'hdx-a1', record('a1')['id']
    assert_equal 'metadata_modified:[2024-01-01T00:00:00Z TO *]', @hdx.searches.last['fq']
    refute File.exist?(@withdrawn_file), 'nothing was withdrawn, so there should be no log'
  end

  def test_files_are_pretty_printed_utf8_without_a_trailing_newline
    @hdx.datasets = [dataset('a1', title: 'Côte d’Ivoire')]
    harvest
    content = File.read(record_path('a1'), mode: 'r:utf-8')

    assert content.start_with?("{\n  \"id\": \"hdx-a1\",")
    assert content.end_with?('}')
    assert_equal 'Côte d’Ivoire', record('a1')['dct_title_s']
  end

  def test_fetches_only_datasets_modified_since_the_last_run
    harvested
    @hdx.datasets = @hdx.datasets.map do |dataset|
      dataset['id'] == 'b2' ? dataset.merge('title' => 'Renamed', 'metadata_modified' => '2026-10-08T03:00:00.000000') : dataset
    end
    counts = harvest

    assert_equal 1, counts[:modified]
    assert_equal 1, counts[:updated]
    assert_equal 'Renamed', record('b2')['dct_title_s']
    assert_equal "metadata_modified:[#{LAST_RUN} TO *]", @hdx.searches.last['fq']
    refute_equal LAST_RUN, last_run
  end

  def test_skips_datasets_not_modified_since_the_last_run
    harvested
    # As if HDX's query matched datasets it shouldn't
    def @hdx.search(params) = super(params.merge('fq' => nil))
    @hdx.datasets = @hdx.datasets.map do |dataset|
      dataset['id'] == 'a1' ? dataset.merge('title' => 'Changed', 'metadata_modified' => '2026-10-08T01:30:00.000000') : dataset
    end
    counts = harvest

    assert_equal IDS.size, counts[:not_newer]
    assert_equal 'Dataset A1', record('a1')['dct_title_s']
  end

  def test_a_run_with_nothing_modified_leaves_the_state_file_alone
    harvested
    counts = harvest

    assert_equal 0, counts[:modified]
    assert_equal LAST_RUN, last_run
  end

  def test_a_state_file_that_cant_be_read_stops_the_run
    File.write(@state_file, '{"last_run": ')

    error = assert_raises(Harvester::Error) { harvest }
    assert_match 'has no usable last_run', error.message
    assert_empty @hdx.requests
  end

  def test_withdraws_datasets_hdx_no_longer_has
    harvested
    remove('b2')
    counts = harvest

    assert_equal 1, counts[:withdrawn]
    refute File.exist?(record_path('b2'))
    refute File.exist?(hdx_path('b2'))
    log = JSON.parse(File.read(@withdrawn_file))
    assert_equal 'https://opengeometadata.org/schema/ogm-withdrawals-1.0.json', log['$schema']
    assert_equal '1.0', log['ogm_version']
    assert_equal [{ 'id' => 'hdx-b2', 'date' => '2026-10-08', 'reason' => 'upstream-removed' }], log['withdrawn']
    assert File.read(@withdrawn_file).end_with?("}\n")
  end

  def test_a_dataset_hdx_made_private_is_withdrawn
    harvested
    remove('b2')
    @hdx.show('b2', 'Authorization Error')
    harvest

    assert_equal [{ 'id' => 'hdx-b2', 'date' => '2026-10-08', 'reason' => 'upstream-removed' }], withdrawals
  end

  def test_a_dataset_that_lost_its_geodata_is_withdrawn_as_out_of_scope
    harvested
    remove('b2')
    @hdx.show('b2', dataset('b2', has_geodata: false))
    counts = harvest

    assert_equal 1, counts[:without_geodata]
    assert_equal [{ 'id' => 'hdx-b2', 'date' => '2026-10-08', 'reason' => 'out-of-scope',
                    'note' => 'HDX still has this dataset, but no longer says it has geodata.' }], withdrawals
  end

  def test_a_first_run_skips_archived_datasets
    edit('b2', archived: true)
    counts = harvest

    assert_equal IDS.size - 1, counts[:created]
    refute File.exist?(record_path('b2'))
  end

  def test_archived_datasets_are_withdrawn_without_asking_hdx_about_each
    harvested
    edit('b2', archived: true, metadata_modified: '2026-10-08T03:00:00.000000')
    counts = harvest

    assert_equal 1, counts[:archived]
    assert_equal [{ 'id' => 'hdx-b2', 'date' => '2026-10-08', 'reason' => 'out-of-scope',
                    'note' => 'HDX has archived this dataset.' }], withdrawals
    assert_empty @hdx.shows
    refute File.exist?(record_path('b2'))
    refute File.exist?(hdx_path('b2'))
  end

  # Archived after the archived datasets were listed
  def test_a_dataset_hdx_shows_as_archived_is_withdrawn
    harvested
    remove('b2')
    @hdx.show('b2', dataset('b2', archived: true))
    harvest

    assert_equal [{ 'id' => 'hdx-b2', 'date' => '2026-10-08', 'reason' => 'out-of-scope',
                    'note' => 'HDX has archived this dataset.' }], withdrawals
  end

  def test_an_unarchived_dataset_is_republished
    harvested
    edit('b2', archived: true)
    harvest
    edit('b2', archived: false, metadata_modified: '2026-10-08T03:00:00.000000')
    counts = harvest

    assert_equal 1, counts[:republished]
    assert_empty withdrawals
    assert File.exist?(record_path('b2'))
  end

  # A listing that shifted as HDX changed can miss a dataset that's still there
  def test_a_dataset_missing_from_the_listing_that_hdx_still_has_stays
    harvested
    missed = @hdx.datasets.find { |dataset| dataset['id'] == 'b2' }
    remove('b2')
    @hdx.show('b2', missed)
    counts = harvest

    assert_equal 1, counts[:unlisted]
    assert_equal 0, counts[:withdrawn]
    assert File.exist?(record_path('b2'))
    refute File.exist?(@withdrawn_file)
  end

  def test_only_datasets_missing_from_the_listing_are_looked_up
    harvested
    remove('b2')
    harvest

    assert_equal ['b2'], @hdx.shows
  end

  # Presence wins: one HDX shows again by the time its modifications are fetched isn't withdrawn
  def test_a_dataset_back_by_the_time_its_modifications_are_fetched_stays
    harvested
    back = dataset('b2', title: 'Back', modified: '2026-10-08T03:00:00.000000')
    remove('b2')
    @hdx.define_singleton_method(:search) do |params|
      self.datasets += [back] if params['fq'] && datasets.none? { |dataset| dataset['id'] == 'b2' }
      super(params)
    end
    counts = harvest

    assert_equal 0, counts[:withdrawn]
    assert_equal 'Back', record('b2')['dct_title_s']
    refute File.exist?(@withdrawn_file)
  end

  def test_republished_dataset_leaves_the_log
    harvested
    remove('b2')
    remove('c3')
    harvest
    write_state(LAST_RUN)
    @hdx.datasets += [dataset('b2', modified: '2026-10-08T03:00:00.000000')]
    counts = harvest

    assert_equal 1, counts[:republished]
    assert_equal ['hdx-c3'], (withdrawals.map { |entry| entry['id'] })
    assert File.exist?(record_path('b2'))
  end

  def test_entries_already_in_the_log_are_kept
    File.write(@withdrawn_file, JSON.pretty_generate('$schema' => Harvester::WITHDRAWALS_SCHEMA, 'ogm_version' => '1.0',
                                                     'withdrawn' => [{ 'id' => 'hdx-old', 'date' => '2026-01-01',
                                                                       'reason' => 'rights' }]))
    harvested
    remove('b2')
    harvest

    assert_equal %w[hdx-old hdx-b2], (withdrawals.map { |entry| entry['id'] })
  end

  def test_refuses_to_withdraw_after_a_large_drop
    harvested
    remove('b2')
    remove('c3')
    error = assert_raises(Harvester::Error) { harvest(max_shrink: 0.25) }

    assert_match 'This run would leave 3 records, down from 5', error.message
    assert_empty @hdx.shows, 'nothing should be looked up for a listing that might be broken'
    assert File.exist?(record_path('b2'))
    refute File.exist?(@withdrawn_file)
    assert_equal LAST_RUN, last_run
  end

  def test_force_allows_a_large_drop
    harvested
    remove('b2')
    remove('c3')
    counts = harvest(max_shrink: 0.25, force: true)

    assert_equal 2, counts[:withdrawn]
  end

  def test_a_failed_listing_stops_the_run
    harvested
    def @hdx.get(_url) = FakeHdx::Response.new('403', '<html>403 Forbidden</html>')

    assert_raises(Hdx::Error) { harvest }
    assert File.exist?(record_path('b2'))
    assert_equal LAST_RUN, last_run
  end

  def test_dry_run_writes_nothing
    counts = harvest(dry_run: true)

    assert_equal IDS.size, counts[:created]
    refute Dir.exist?(@aardvark_metadata_dir)
    refute File.exist?(@state_file)

    harvested
    remove('b2')
    @hdx.datasets += [dataset('f6', modified: '2026-10-08T03:00:00.000000')]
    counts = harvest(dry_run: true)

    assert_equal 1, counts[:withdrawn]
    assert_equal 1, counts[:created]
    assert File.exist?(record_path('b2'))
    refute File.exist?(record_path('f6'))
    refute File.exist?(@withdrawn_file)
    assert_equal LAST_RUN, last_run
  end
end
