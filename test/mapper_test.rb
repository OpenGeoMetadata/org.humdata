require 'minitest/autorun'
require 'json'
require_relative '../mapper'

class MapperTest < Minitest::Test
  def test_mapper_adds_geojson_reference
    dataset = {
      "id" => "test-dataset-geojson",
      "title" => "Test GeoJSON dataset",
      "resources" => [
        {
          "format" => "GeoJSON",
          "download_url" => "https://example.com/data.geojson"
        }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    assert_equal "https://example.com/data.geojson", refs['http://geojson.org/geojson-spec.html']
    expected_download = [
      { "url" => "https://example.com/data.geojson", "label" => "GeoJSON" }
    ]
    assert_equal expected_download, refs['http://schema.org/downloadUrl']
  end

  def test_mapper_does_not_add_geojson_reference_without_geojson_resource
    dataset = {
      "id" => "test-dataset-shapefile",
      "title" => "Test Shapefile dataset",
      "resources" => [
        {
          "format" => "Shapefile",
          "download_url" => "https://example.com/data.zip"
        }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    refute refs.key?('http://geojson.org/geojson-spec.html')
    expected_download = [
      { "url" => "https://example.com/data.zip", "label" => "Shapefile" }
    ]
    assert_equal expected_download, refs['http://schema.org/downloadUrl']
  end

  def test_mapper_adds_geojson_reference_when_mixed_resources
    dataset = {
      "id" => "test-dataset-mixed",
      "title" => "Test Mixed dataset",
      "resources" => [
        {
          "format" => "Shapefile",
          "download_url" => "https://example.com/data.zip"
        },
        {
          "format" => "GeoJSON",
          "download_url" => "https://example.com/data.geojson"
        }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    assert_equal "https://example.com/data.geojson", refs['http://geojson.org/geojson-spec.html']
    expected_download = [
      { "url" => "https://example.com/data.zip", "label" => "Shapefile" },
      { "url" => "https://example.com/data.geojson", "label" => "GeoJSON" }
    ]
    assert_equal expected_download, refs['http://schema.org/downloadUrl']
  end

  def test_mapper_concatenates_name_and_format_for_download_url_labels
    dataset = {
      "id" => "test-dataset-concat",
      "title" => "Test Concat Labels",
      "resources" => [
        {
          "name" => "hti_AccessConstraintSeverity_Jan-Sep2024.xls",
          "format" => "XLS",
          "download_url" => "https://example.com/hti_AccessConstraintSeverity_Jan-Sep2024.xls"
        }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    expected_download = [
      { "url" => "https://example.com/hti_AccessConstraintSeverity_Jan-Sep2024.xls", "label" => "hti_AccessConstraintSeverity_Jan-Sep2024.xls (XLS)" }
    ]
    assert_equal expected_download, refs['http://schema.org/downloadUrl']
  end

  def test_mapper_does_not_add_geojson_reference_zipped_geojson
    dataset = {
      "id" => "test-dataset-zipped-geojson",
      "title" => "Test Zipped GeoJSON dataset",
      "resources" => [
        {
          "format" => "GeoJSON",
          "download_url" => "https://example.com/geojson_data.zip"
        }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    refute refs.key?('http://geojson.org/geojson-spec.html')
  end

  def test_mapper_adds_geojson_reference_json_url
    dataset = {
      "id" => "test-dataset-json-url",
      "title" => "Test JSON URL dataset",
      "resources" => [
        {
          "format" => "GeoJSON",
          "download_url" => "https://example.com/data.json"
        }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    assert_equal "https://example.com/data.json", refs['http://geojson.org/geojson-spec.html']
  end

  def test_mapper_adds_pmtiles_reference_when_mixed_resources
    dataset = {
      "id" => "test-dataset-pmtiles",
      "title" => "Test PMTiles dataset",
      "resources" => [
        {
          "format" => "GeoJSON",
          "download_url" => "https://example.com/data_geojson.zip"
        },
        {
          "format" => "PMTiles",
          "download_url" => "https://example.com/data.pmtiles"
        }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    assert_equal "https://example.com/data.pmtiles", refs['https://github.com/protomaps/PMTiles']
    refute refs.key?('http://geojson.org/geojson-spec.html')
  end

  def test_mapper_does_not_add_pmtiles_reference_without_pmtiles_resource
    dataset = {
      "id" => "test-dataset-no-pmtiles",
      "title" => "Test dataset without PMTiles",
      "resources" => [
        {
          "format" => "Geopackage",
          "download_url" => "https://example.com/data_gpkg.zip"
        }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    refute refs.key?('https://github.com/protomaps/PMTiles')
  end

  def test_mapper_does_not_add_pmtiles_reference_zipped_pmtiles
    dataset = {
      "id" => "test-dataset-zipped-pmtiles",
      "title" => "Test Zipped PMTiles dataset",
      "resources" => [
        {
          "format" => "PMTiles",
          "download_url" => "https://example.com/pmtiles_data.zip"
        }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    refute refs.key?('https://github.com/protomaps/PMTiles')
  end
end
