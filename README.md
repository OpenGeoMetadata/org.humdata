# OpenGeoMetadata Harvester

This project contains a tool to harvest dataset metadata from the Humanitarian Data Exchange (HDX) and transform it into the OpenGeoMetadata (OGM) Aardvark schema.

## Setup

Make sure you have Ruby installed on your system.

## Usage

To run the harvester:

```bash
ruby harvester.rb
```

The script will:
1. Check `state.json` for the last run date.
2. Fetch datasets from HDX that have been modified since that date.
3. Save the original metadata to `metadata-hdx/`.
4. Transform and save the metadata to `metadata-aardvark/`.
5. Update `state.json` with the current timestamp.

## Converting metadata to Aardvark

`convert.rb` transforms one or more HDX metadata files from `metadata-hdx/` into the OGM Aardvark schema and writes the results to `metadata-aardvark/`.

Pass the input files as arguments:

```bash
ruby convert.rb metadata-hdx/some-id.json metadata-hdx/another-id.json
```

Or convert all files at once using a shell glob:

```bash
ruby convert.rb metadata-hdx/*.json
```

Output files are written to `metadata-aardvark/` with the same filename as the corresponding input file.
