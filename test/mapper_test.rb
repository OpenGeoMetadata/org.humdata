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
    assert_equal "https://example.com/data.geojson", refs['http://schema.org/downloadUrl']
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
    assert_equal "https://example.com/data.zip", refs['http://schema.org/downloadUrl']
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
    assert_equal "https://example.com/data.zip", refs['http://schema.org/downloadUrl']
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
end
