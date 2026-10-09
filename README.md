# org.humdata

This repository contains [OpenGeoMetadata Aardvark](https://opengeometadata.org/ogm-aardvark/) records for the datasets with geodata on the [Humanitarian Data Exchange](https://data.humdata.org/) (HDX), except those HDX has archived. There is one record per dataset.

The records are mapped from HDX's own metadata for each dataset, which is kept alongside them. This repository is not an official HDX product.

## File Structure

```
metadata-hdx/
  0a01505d-cf39-4d5c-b805-60073b555a95.json      a dataset's metadata as HDX gives it, named by its id
  ...
metadata-aardvark/
  0a01505d-cf39-4d5c-b805-60073b555a95.json      its record, whose id is hdx-0a01505d-cf39-4d5c-b805-60073b555a95
  ...
state.json                                       where the next harvest starts from
withdrawn.json                                   records that have left the repository
```

## Metadata

- **Version:** OGM Aardvark, with no custom fields.
- **Other formats:** each dataset's metadata as HDX gives it is in `metadata-hdx/`.
- **Updates:** a GitHub Actions workflow harvests daily, fetching only the datasets HDX has modified since the last run. A record changes only when HDX modifies its dataset, so a change to `mapper.rb` reaches the other records only once they're converted again; see [Converting Metadata to Aardvark](#converting-metadata-to-aardvark).
- **Validation:** the tests in `test/` run before every harvest.

### Source

HDX's [CKAN API](https://data.humdata.org/api/3/action/help_show?name=package_search): `package_search` for the datasets with `has_geodata:true` that aren't `archived:true`, and for the ones that are, and `package_show` for one that has left both lists.

## Withdrawn Records

When a record leaves the repository, its files in both directories are deleted and it's logged in `withdrawn.json`.

Every run lists the ids of HDX's datasets with geodata: those it has archived, and those it hasn't. A record whose dataset is in neither list is looked up on HDX:

- **Archived:** if HDX has archived the dataset, which it does with datasets no longer maintained, the entry's reason is `out-of-scope`, with a note saying so. HDX keeps archived datasets, so they haven't been removed upstream.
- **Upstream-removed:** if HDX no longer shows the dataset, because it was deleted or made private, the reason is `upstream-removed`.
- **No geodata:** if HDX still has the dataset but no longer says it has geodata, the reason is also `out-of-scope`, with a note saying so.
- **Kept:** if HDX still has the dataset with geodata and hasn't archived it, the lists missed it, and the record stays.
- **Republished:** entries are only removed when their dataset comes back.

The harvester stops without changing anything when:
- `state.json` can't be read;
- either of HDX's lists holds fewer datasets than it says it has, twice running;
- the run would remove more than 2% of all records. Set `FORCE=1` if this is intentional.

If HDX fails partway through the modified datasets, the records saved so far stay, and nothing is withdrawn. Only a run that finishes updates `state.json`, so the next one fetches them all again.

## Running the Harvester

The harvester needs Ruby 4.0 and the Nokogiri gem. HDX's times have no zone, and `mapper.rb` reads them in the local zone, so run it with `TZ=UTC` to get the dates CI does.

```bash
gem install nokogiri
TZ=UTC ruby harvester.rb
```

These environment variables change how it runs:

- `DRY_RUN=1` reports what would change without writing anything.
- `FORCE=1` allows a run that would withdraw more than 2% of the records.

To run the tests:

```bash
for test in test/*_test.rb; do ruby "$test"; done
```

## Converting Metadata to Aardvark

`convert.rb` maps the HDX metadata files passed to it into the OGM Aardvark schema, and writes each record to `metadata-aardvark/` with the same filename as its input:

```bash
TZ=UTC ruby convert.rb metadata-hdx/some-id.json metadata-hdx/another-id.json
```

To convert every dataset:

```bash
TZ=UTC ruby convert.rb metadata-hdx/*.json
```

## How to Contribute

For problems with the records, open an issue in this repository. Records are regenerated whenever HDX modifies their datasets, so edits to the files would be overwritten:
- **How fields are mapped:** change `mapper.rb`.
- **Which datasets get records, and when they're withdrawn:** change `harvester.rb` and `hdx.rb`.
- **The data itself:** titles, descriptions and files are HDX's, and corrections have to be made on HDX by the organization that shares the dataset.
