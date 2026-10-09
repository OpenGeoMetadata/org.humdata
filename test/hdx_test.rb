require 'minitest/autorun'
require 'stringio'
require_relative 'fake_hdx'
require_relative '../hdx'

class HdxTest < Minitest::Test
  def datasets(count)
    Array.new(count) { |index| { 'id' => format('d%02d', index), 'metadata_modified' => "2026-10-0#{index % 9 + 1}T00:00:00.000000" } }
  end

  def hdx(api, page_size: 2)
    Hdx.new(http: api, log: StringIO.new, page_size: page_size)
  end

  def test_lists_every_id_a_page_at_a_time_in_id_order
    api = FakeHdx.new(datasets(5).reverse)

    assert_equal %w[d00 d01 d02 d03 d04], hdx(api).ids.to_a
    assert_equal [0, 2, 4], (api.searches.map { |params| params['start'].to_i })
    assert(api.searches.all? { |params| params['q'] == 'has_geodata:true -archived:true' && params['sort'] == 'id asc' })
    assert(api.searches.all? { |params| params['fl'] == 'id' })
  end

  def test_lists_archived_ids_apart
    api = FakeHdx.new(datasets(5).each_with_index.map { |dataset, index| dataset.merge('archived' => index.odd?) })

    assert_equal %w[d00 d02 d04], hdx(api).ids.to_a
    assert_equal %w[d01 d03], hdx(api).ids(archived: true).to_a
    assert_equal 'has_geodata:true archived:true', api.searches.last['q']
  end

  def test_yields_the_datasets_modified_since_a_time_that_arent_archived
    api = FakeHdx.new(datasets(9).map { |dataset| dataset['id'] == 'd07' ? dataset.merge('archived' => true) : dataset })
    modified = []
    count = hdx(api).modified_since(Time.utc(2026, 10, 7)) { |dataset| modified << dataset['id'] }

    assert_equal 2, count
    assert_equal %w[d06 d08], modified
    assert_equal 'metadata_modified:[2026-10-07T00:00:00Z TO *]', api.searches.first['fq']
  end

  # A dataset deleted mid-listing shifts the pages after it and hides one
  def test_a_listing_that_comes_up_short_is_run_again
    api = FakeHdx.new(datasets(5))
    listings = 0
    api.define_singleton_method(:get) do |url|
      response = super(url)
      body = JSON.parse(response.body)
      listings += 1 if body.dig('result', 'results')&.first&.[]('id') == 'd00'
      body['result']['results'] = body['result']['results'].reject { |row| row['id'] == 'd02' } if listings == 1
      FakeHdx::Response.new(response.code, JSON.generate(body))
    end

    assert_equal 5, hdx(api).ids.size
    assert_equal 2, listings
  end

  def test_a_listing_that_stays_short_stops_the_run
    api = FakeHdx.new(datasets(5))
    api.define_singleton_method(:get) do |url|
      body = JSON.parse(super(url).body)
      body['result']['results'] = body['result']['results'].reject { |row| row['id'] == 'd02' }
      FakeHdx::Response.new('200', JSON.generate(body))
    end

    error = assert_raises(Hdx::Error) { hdx(api).ids }
    assert_match 'HDX has 5 datasets with geodata, but its pages listed 4', error.message
  end

  def test_shows_a_dataset_or_nil_when_hdx_no_longer_does
    api = FakeHdx.new(datasets(1))
    api.show('private', 'Authorization Error')

    assert_equal 'd00', hdx(api).dataset('d00')['id']
    assert_nil hdx(api).dataset('purged')
    assert_nil hdx(api).dataset('private')
  end

  def test_other_errors_stop_the_run
    api = FakeHdx.new
    api.show('odd', 'Validation Error')

    assert_raises(Hdx::Error) { hdx(api).dataset('odd') }
  end

  # A proxy's error page isn't CKAN saying a dataset is gone
  def test_an_answer_without_json_stops_the_run
    api = FakeHdx.new
    def api.get(_url) = FakeHdx::Response.new('404', '<html>Not Found</html>')

    assert_raises(Hdx::Error) { hdx(api).dataset('d00') }
    assert_raises(Hdx::Error) { hdx(api).ids }
  end

  # Wherever the harvester runs: CI's zone is UTC, which would hide the difference
  def test_times_without_a_zone_are_utc
    zone = ENV['TZ']
    ENV['TZ'] = 'America/Los_Angeles'

    assert_equal Time.utc(2026, 10, 8, 8, 5, 42.5r), Hdx.time('2026-10-08T08:05:42.500000')
    assert_equal Time.utc(2026, 10, 8, 8, 5, 42), Hdx.time('2026-10-08T08:05:42Z')
    assert_equal Time.utc(2026, 10, 8, 6, 5, 42), Hdx.time('2026-10-08T08:05:42+02:00')
  ensure
    ENV['TZ'] = zone
  end
end
