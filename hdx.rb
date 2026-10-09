require 'json'
require 'set'
require 'time'
require 'uri'
require_relative 'http_client'

# The datasets with geodata on the Humanitarian Data Exchange (HDX), from its CKAN API. HDX archives datasets that
# are no longer maintained, but keeps them, and the repository has no records for those.
#
# Listings are sorted by id, which editing a dataset leaves alone, so their pages don't shift as HDX changes
# mid-listing; HDX's own order puts the most recently modified first.
class Hdx
  API_URL = 'https://data.humdata.org/api/3/action'
  QUERY = 'has_geodata:true -archived:true'
  ARCHIVED_QUERY = 'has_geodata:true archived:true'
  PAGE_SIZE = 1000

  # What CKAN says about a dataset it won't show an anonymous user: one HDX has purged, or one it has deleted or
  # made private
  GONE = ['Not Found Error', 'Authorization Error'].freeze

  class Error < StandardError; end

  # HDX's times are in UTC without saying so, which Time.parse would take for local time
  def self.time(value)
    Time.parse(value.match?(/(Z|[+-]\d{2}:?\d{2})\z/) ? value : "#{value}Z").utc
  end

  def initialize(http: HttpClient.new, log: $stdout, page_size: PAGE_SIZE)
    @http = http
    @log = log
    @page_size = page_size
  end

  # Yields every dataset with geodata that isn't archived and was modified since a time, as HDX gives it, fetching
  # them a page at a time
  # @return [Integer] how many datasets there were
  def modified_since(time, &block)
    fq = "metadata_modified:[#{time.utc.strftime('%Y-%m-%dT%H:%M:%SZ')} TO *]"
    page_through('fq' => fq) do |datasets, start, count|
      @log.puts "Modified datasets: #{start + datasets.size} of #{count}"
      datasets.each(&block)
    end
  end

  # The id of every dataset with geodata that isn't archived, or of every one that is. Datasets that leave the
  # listing midway shift the later pages and hide one, so a listing that comes up short is run once more before
  # giving up.
  # @return [Set<String>]
  def ids(archived: false, attempts: 2)
    kind = archived ? 'archived datasets with geodata' : 'datasets with geodata'
    attempts.times do |attempt|
      ids = Set.new
      total = page_through('q' => archived ? ARCHIVED_QUERY : QUERY, 'fl' => 'id') do |rows|
        ids.merge(rows.map { |row| row['id'] })
      end
      @log.puts "#{kind.capitalize}: #{ids.size}"
      return ids if ids.size >= total
      raise Error, "HDX has #{total} #{kind}, but its pages listed #{ids.size}" if attempt == attempts - 1
    end
  end

  # @return [Hash, nil] the dataset, or nil if HDX no longer shows it
  def dataset(id)
    response, body = request('package_show', 'id' => id)
    return body['result'] if body['success'] && body['result'].is_a?(Hash)
    return nil if GONE.include?(body.dig('error', '__type'))

    raise Error, "package_show for #{id} answered #{response.code}: #{body['error'].to_json}"
  end

  private

  # @yieldparam datasets [Array<Hash>] a page of results
  # @yieldparam start [Integer] the page's offset
  # @yieldparam total [Integer] how many results the query has
  # @return [Integer] how many results the query has
  def page_through(params)
    start = 0
    total = nil
    loop do
      _response, body = request('package_search', { 'q' => QUERY, 'sort' => 'id asc', 'rows' => @page_size,
                                                    'start' => start }.merge(params))
      raise Error, "package_search answered without success: #{body['error'].to_json}" unless body['success']

      total ||= body.dig('result', 'count').to_i
      results = body.dig('result', 'results') || []
      results.each { |dataset| raise Error, 'package_search listed a dataset without an id' unless dataset['id'] }
      yield results, start, total unless results.empty?
      start += @page_size
      return total if results.empty? || start >= total
    end
  end

  # @return [Array(Net::HTTPResponse, Hash)] the response, and its body. CKAN answers errors with JSON too, so
  # anything else, like a proxy's error page, stops the run.
  def request(action, params)
    url = "#{API_URL}/#{action}?#{URI.encode_www_form(params)}"
    response = @http.get(url)
    body = JSON.parse(response.body.to_s)
    raise Error, "#{url} answered #{response.code} with #{body.class} JSON" unless body.is_a?(Hash)

    [response, body]
  rescue JSON::ParserError
    raise Error, "#{url} answered #{response.code} without JSON"
  end
end
