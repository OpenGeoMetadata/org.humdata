require 'net/http'
require 'openssl'
require 'uri'

# The harvester's HTTP client: one kept-alive connection per host, a pause between requests to each host so
# that a run never hammers HDX's servers, and retries with backoff for the errors that pass. Adapted from
# gov.usgs.tnm's.
class HttpClient
  # HDX's firewall answers 403 to any user agent with "harvester" in it
  USER_AGENT = 'org.humdata (+https://github.com/OpenGeoMetadata/org.humdata)'

  # Responses worth asking again for: rate limiting, and the gateway errors a busy server gives
  RETRY_STATUSES = [429, 500, 502, 503, 504, 520, 522, 524].freeze
  NETWORK_ERRORS = [Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
                    EOFError, IOError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse].freeze

  class Error < StandardError; end

  # @param interval [Hash, Float] seconds to leave between requests to a host, or a Hash of them by host
  def initialize(interval: 0.5, retries: 4, timeout: 180, sleeper: method(:sleep))
    @interval = interval
    @retries = retries
    @timeout = timeout
    @sleeper = sleeper
    @connections = {}
    @last_request = {}
  end

  # Net::HTTP asks for gzip and decodes it, which shrinks a page of HDX's search results about sixfold
  def get(url, headers: {})
    request(Net::HTTP::Get, url, headers)
  end

  private

  # @return [Net::HTTPResponse] the first response that isn't worth retrying
  # @raise [Error] when every attempt failed
  def request(type, url, headers)
    uri = URI(url)
    attempt = 0
    begin
      pause(uri.host)
      request = type.new(uri, { 'User-Agent' => USER_AGENT }.merge(headers))
      response = connection(uri).request(request)
      raise Error, "#{response.code} #{response.message}" if RETRY_STATUSES.include?(response.code.to_i)

      response
    rescue Error, *NETWORK_ERRORS => e
      close(uri)
      attempt += 1
      raise Error, "#{type::METHOD} #{url} failed #{attempt} times; last: #{e.class}: #{e.message}" if attempt > @retries

      @sleeper.call(2**attempt)
      retry
    end
  end

  # Hosts without an interval of their own get half a second
  def pause(host)
    interval = @interval.is_a?(Hash) ? @interval.fetch(host, 0.5) : @interval
    wait = interval - (monotonic - @last_request.fetch(host, -Float::INFINITY))
    @sleeper.call(wait) if wait.positive?
    @last_request[host] = monotonic
  end

  def connection(uri)
    @connections[[uri.host, uri.port]] ||= Net::HTTP.new(uri.host, uri.port).tap do |http|
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 30
      http.read_timeout = @timeout
      http.keep_alive_timeout = 30
      http.start
    end
  end

  def close(uri)
    http = @connections.delete([uri.host, uri.port])
    http&.finish if http&.started?
  rescue IOError
    nil
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
