require 'json'
require 'net/http'
require 'time'
require 'uri'
require_relative '../hdx'

# Answers like HDX's CKAN API: package_search lists the datasets with geodata, archived or not, and package_show
# shows them, and whatever else it's told to
class FakeHdx
  Response = Struct.new(:code, :body) do
    def is_a?(type)
      type == Net::HTTPSuccess ? code == '200' : super
    end
  end

  ERRORS = { 'Not Found Error' => '404', 'Authorization Error' => '403' }.freeze

  attr_accessor :datasets
  attr_reader :requests, :shown

  # @param datasets [Array<Hash>] the datasets with geodata, the archived ones with `archived: true`
  def initialize(datasets = [])
    @datasets = datasets
    @shown = {}
    @requests = []
  end

  # Makes package_show answer for a dataset that isn't listed
  # @param answer [Hash, String] the dataset, or the type of CKAN error
  def show(id, answer)
    @shown[id] = answer
  end

  def get(url)
    uri = URI(url)
    params = URI.decode_www_form(uri.query).to_h
    @requests << [File.basename(uri.path), params]
    case File.basename(uri.path)
    when 'package_search' then search(params)
    when 'package_show' then show_dataset(params['id'])
    else Response.new('404', '<html>Not Found</html>')
    end
  end

  def searches
    requests.select { |action, _params| action == 'package_search' }.map(&:last)
  end

  def shows
    requests.select { |action, _params| action == 'package_show' }.map { |_action, params| params['id'] }
  end

  private

  def search(params)
    results = datasets.sort_by { |dataset| dataset['id'] }
    results = case params['q']
              when Hdx::QUERY then results.reject { |dataset| dataset['archived'] }
              when Hdx::ARCHIVED_QUERY then results.select { |dataset| dataset['archived'] }
              else raise ArgumentError, "unexpected query #{params['q']}"
              end
    if (since = params['fq'].to_s[/\Ametadata_modified:\[(\S+) TO \*\]\z/, 1])
      results = results.select { |dataset| Hdx.time(dataset['metadata_modified']) >= Time.parse(since) }
    end
    page = results[params['start'].to_i, params['rows'].to_i] || []
    page = page.map { |dataset| dataset.slice('id') } if params['fl'] == 'id'
    success('count' => results.size, 'results' => page)
  end

  def show_dataset(id)
    answer = datasets.find { |dataset| dataset['id'] == id } || shown.fetch(id, 'Not Found Error')
    return success(answer) if answer.is_a?(Hash)

    Response.new(ERRORS.fetch(answer, '409'), JSON.generate('success' => false,
                                                     'error' => { '__type' => answer, 'message' => answer }))
  end

  def success(result)
    Response.new('200', JSON.generate('success' => true, 'result' => result))
  end
end
