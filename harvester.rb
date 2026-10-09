require 'date'
require 'fileutils'
require 'json'
require 'set'
require 'time'
require_relative 'hdx'
require_relative 'http_client'
require_relative 'mapper'

# Harvests the datasets with geodata on the Humanitarian Data Exchange (HDX) that it hasn't archived: their
# metadata as HDX gives it, in metadata-hdx/, and the Aardvark records mapped from it, in metadata-aardvark/.
# Records that leave the repository are logged in withdrawn.json.
#
# HDX has too many datasets to fetch every one on every run, so a run fetches only those modified since the last
# one began, which state.json records. Their ids are cheap to list, though, so every run also lists them all, and
# withdraws the records of datasets HDX no longer has, or has archived.
class Harvester
  STATE_FILE = 'state.json'
  HDX_METADATA_DIR = 'metadata-hdx'
  AARDVARK_METADATA_DIR = 'metadata-aardvark'
  WITHDRAWN_FILE = 'withdrawn.json'

  WITHDRAWALS_SCHEMA = 'https://opengeometadata.org/schema/ogm-withdrawals-1.0.json'

  # Where a first run, without a state file, starts from
  EPOCH = Time.utc(2024, 1, 1)

  # Refuse to withdraw anything if a run would shrink the repository by more than this fraction, so that a
  # truncated or broken listing can't empty it. Rerun with FORCE=1 when the drop is real.
  MAX_SHRINK = 0.02

  # A pause between requests, in seconds: HDX is asked about 20 times a run, plus once for each dataset that has
  # left the listing without being archived
  INTERVALS = { 'data.humdata.org' => 0.5 }.freeze

  class Error < StandardError; end

  def self.run(**options)
    new(**options).run
  end

  attr_reader :state_file, :hdx_metadata_dir, :aardvark_metadata_dir, :withdrawn_file, :dry_run, :force,
              :max_shrink, :today, :log

  def initialize(state_file: STATE_FILE, hdx_metadata_dir: HDX_METADATA_DIR,
                 aardvark_metadata_dir: AARDVARK_METADATA_DIR, withdrawn_file: WITHDRAWN_FILE, dry_run: false,
                 force: false, max_shrink: MAX_SHRINK, today: Date.today, log: $stdout, http: nil)
    @state_file = state_file
    @hdx_metadata_dir = hdx_metadata_dir
    @aardvark_metadata_dir = aardvark_metadata_dir
    @withdrawn_file = withdrawn_file
    @dry_run = dry_run
    @force = force
    @max_shrink = max_shrink
    @today = today
    @log = log
    @http = http
  end

  # @return [Hash] counts of what the run did
  def run
    last_run = load_last_run
    started = Time.now.utc
    hdx = Hdx.new(http: @http || HttpClient.new(interval: INTERVALS), log: log)
    counts = Hash.new(0)

    existing = existing_records
    listed = hdx.ids
    missing = existing.keys.reject { |id| listed.include?(id) }.sort
    check_shrinkage(existing.size, existing.size - missing.size)
    removals = removals(missing, existing, hdx.ids(archived: true), hdx, counts)

    written = Set.new
    counts[:modified] = hdx.modified_since(last_run) do |dataset|
      modified = dataset['metadata_modified']
      if modified && Hdx.time(modified) > last_run
        counts[save(dataset)] += 1
        written << dataset['id']
      else
        counts[:not_newer] += 1
      end
    end
    # A dataset that's back on HDX by the time its modifications are fetched stays
    removals.reject! { |id, _removal| written.include?(id) }
    published = ((existing.keys - removals.keys) | written.to_a).to_set { |id| record_id(id) }
    counts.merge!(withdraw(removals.values, published))
    update_last_run(started) if counts[:modified].positive?

    report(last_run, listed, counts)
    counts
  end

  private

  # The time the last run began. A state file that can't be read stops the run, rather than fetch every dataset
  # since EPOCH again.
  def load_last_run
    return EPOCH unless File.exist?(state_file)

    Time.parse(JSON.parse(File.read(state_file, mode: 'r:bom|utf-8')).fetch('last_run')).utc
  rescue JSON::ParserError, KeyError, ArgumentError, TypeError => e
    raise Error, "#{state_file} has no usable last_run (#{e.class}: #{e.message}). Nothing was changed."
  end

  def update_last_run(time)
    return if dry_run

    File.write(state_file, JSON.pretty_generate({ last_run: time.strftime('%Y-%m-%dT%H:%M:%SZ') }), mode: 'w:utf-8')
  end

  def check_shrinkage(existing_count, kept_count)
    return if force || existing_count.zero? || kept_count >= existing_count * (1 - max_shrink)

    raise Error, "This run would leave #{kept_count} records, down from #{existing_count}: more than " \
                 "#{(max_shrink * 100).round}% fewer. Nothing was changed; rerun with FORCE=1 if the drop is real."
  end

  def record_id(id)
    "#{Mapper::ID_PREFIX}#{id}"
  end

  def hdx_path(id)
    File.join(hdx_metadata_dir, "#{id}.json")
  end

  def aardvark_path(id)
    File.join(aardvark_metadata_dir, "#{id}.json")
  end

  # Every dataset's record currently in the repository, by the dataset's id, with the files it's kept in
  def existing_records
    Dir.glob(File.join(aardvark_metadata_dir, '*.json')).to_h do |path|
      id = File.basename(path, '.json')
      [id, [hdx_path(id), path]]
    end
  end

  # Saves a dataset as HDX gave it, and its record
  # @return [Symbol] :created, :updated, or :unchanged, for the record
  def save(dataset)
    id = dataset['id']
    write_json(hdx_path(id), dataset)
    write_json(aardvark_path(id), Mapper.map(dataset))
  end

  def write_json(path, data)
    write_file(path, JSON.pretty_generate(data))
  end

  # Writes the file only when its contents change, so unchanged records don't show up in git
  # @return [Symbol] :created, :updated, or :unchanged
  def write_file(path, content)
    exists = File.exist?(path)
    return :unchanged if exists && File.read(path, mode: 'r:bom|utf-8') == content

    unless dry_run
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content, mode: 'w:utf-8')
    end
    exists ? :updated : :created
  end

  # List of datasets that have left the repository, with the reason and the files to delete
  # @param archived [Set<String>] the ids of the archived datasets with geodata
  # @return [Hash{String => Array(Hash, Array<String>)}]
  def removals(missing, existing, archived, hdx, counts)
    missing.each_with_object({}) do |id, removals|
      cause = archived.include?(id) ? :archived : cause(hdx.dataset(id))
      counts[cause] += 1
      removals[id] = [withdrawal(id, cause), existing[id]] unless cause == :unlisted
    end
  end

  # The reason a dataset is missing from the listing
  # @param dataset [Hash, nil] the dataset, if HDX still shows it
  def cause(dataset)
    if dataset.nil? then :removed
    elsif dataset['archived'] then :archived
    elsif dataset['has_geodata'] then :unlisted
    else :without_geodata
    end
  end

  # Records that leave the repository are deleted and logged in withdrawn.json, following the proposed
  # OpenGeoMetadata withdrawal convention: deleting a file alone doesn't tell harvesters to delete the record.
  # Entries are only ever removed for records that have come back.
  # @param published [Set] the id of every record the repository now has
  def withdraw(removals, published)
    withdrawals = read_withdrawals
    republished, entries = withdrawals['withdrawn'].partition { |entry| published.include?(entry['id']) }

    removals.each do |entry, paths|
      entries = entries.reject { |other| other['id'] == entry['id'] } << entry
      paths.each { |path| File.delete(path) if !dry_run && File.exist?(path) }
    end

    if !dry_run && (removals.any? || republished.any?)
      content = JSON.pretty_generate(withdrawals.merge('withdrawn' => entries))
      File.write(withdrawn_file, "#{content}\n", mode: 'w:utf-8')
    end
    { withdrawn: removals.size, republished: republished.size }
  end

  def read_withdrawals
    unless File.exist?(withdrawn_file)
      return { '$schema' => WITHDRAWALS_SCHEMA, 'ogm_version' => '1.0', 'withdrawn' => [] }
    end

    JSON.parse(File.read(withdrawn_file, mode: 'r:bom|utf-8'))
  end

  # HDX keeps the datasets it archives, so they're out of the repository's scope rather than removed upstream
  def withdrawal(id, cause)
    entry = { 'id' => record_id(id), 'date' => today.iso8601 }
    case cause
    when :removed then entry.merge('reason' => 'upstream-removed')
    when :archived then entry.merge('reason' => 'out-of-scope', 'note' => 'HDX has archived this dataset.')
    else entry.merge('reason' => 'out-of-scope', 'note' => 'HDX still has this dataset, but no longer says it has geodata.')
    end
  end

  def report(last_run, listed, counts)
    log.puts "HDX: #{listed.size} datasets with geodata that aren't archived; #{counts[:modified]} modified since " \
             "#{last_run.strftime('%Y-%m-%dT%H:%M:%SZ')}"
    log.puts "Records: #{counts[:created]} created, #{counts[:updated]} updated, #{counts[:unchanged]} unchanged; " \
             "#{counts[:not_newer]} not modified since the last run"
    log.puts "Withdrawn: #{counts[:withdrawn]} (#{counts[:archived]} archived, #{counts[:removed]} gone from HDX, " \
             "#{counts[:without_geodata]} no longer with geodata); republished: #{counts[:republished]}; " \
             "missing from the listing but still on HDX: #{counts[:unlisted]}"
    log.puts 'Dry run: nothing was written' if dry_run
  end
end

if __FILE__ == $0
  # Report progress as it happens, rather than all at the end, when the log is a file or GitHub's
  $stdout.sync = true
  begin
    Harvester.run(dry_run: !ENV['DRY_RUN'].to_s.empty?, force: !ENV['FORCE'].to_s.empty?)
  rescue Harvester::Error, Hdx::Error, HttpClient::Error => e
    warn "Harvest stopped: #{e.message}"
    exit 1
  end
end
