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

  def test_mapper_adds_embed_reference_for_custom_visualization
    dataset = {
      "id" => "test-dataset-customviz",
      "title" => "Test custom visualization dataset",
      "customviz" => [
        { "url" => "https://giscience.github.io/open-access-lens/#/jam" }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    assert_equal "https://giscience.github.io/open-access-lens/#/jam", refs['http://schema.org/embedUrl']
  end

  def test_mapper_does_not_add_embed_reference_without_custom_visualization
    dataset = {
      "id" => "test-dataset-no-customviz",
      "title" => "Test dataset without custom visualization",
      "customviz" => []
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    refute refs.key?('http://schema.org/embedUrl')
  end

  def test_mapper_does_not_embed_unembedded_visualizations
    [
      "https://sf.earthobservatory.sg/event/EOSRS_2026_013_IDN_EQ_202608_Flores",
      "https://production-raw-data-api.s3.amazonaws.com/ISO3/HRV/education_facilities/hotosm_hrv_education_facilities_report.html",
      "https://s3.dualstack.us-east-1.amazonaws.com/production-raw-data-api/ISO3/IOT/railways/lines/stats-summary.html",
      "https://data.humdata.org/dataset/5ad71c11/resource/05f6c1a9/download/osgeonepal_npl_settlements_report.html",
      "https://turkeyeq2023.atlasai.co/images/syria-bui.png",
      "https://mma.prnewswire.com/media/1999946/Atlas_AI_HumanSettlements_Map_Turkey.jpg?p=publish",
      "https://mcarans.github.io/view-images/#https://static.gis.wfp.org/adam_eq/sm.jpg",
      "http://example.com/insecure-dashboard.html"
    ].each do |url|
      dataset = {
        "id" => "test-dataset-unembedded",
        "title" => "Test unembedded visualization dataset",
        "customviz" => [{ "url" => url }]
      }
      mapped = Mapper.map(dataset)
      refs = JSON.parse(mapped['dct_references_s'])

      refute refs.key?('http://schema.org/embedUrl'), "embedded #{url}"
    end
  end

  def test_mapper_embeds_first_embeddable_visualization
    dataset = {
      "id" => "test-dataset-several-customviz",
      "title" => "Test dataset with several custom visualizations",
      "customviz" => [
        { "url" => "https://turkeyeq2023.atlasai.co/images/syria-bui.png" },
        { "url" => "https://umap.hotosm.org/en/map/drc-ebola-outbreak-2026-priority-area_2892" },
        { "url" => "https://giscience.github.io/open-access-lens/#/jam" }
      ]
    }
    mapped = Mapper.map(dataset)
    refs = JSON.parse(mapped['dct_references_s'])

    assert_equal "https://umap.hotosm.org/en/map/drc-ebola-outbreak-2026-priority-area_2892", refs['http://schema.org/embedUrl']
  end

  def test_mapper_adds_geometry_for_small_country
    dataset = {
      "id" => "test-dataset-grenada",
      "title" => "Test Grenada dataset",
      "groups" => [{ "title" => "Grenada" }]
    }
    mapped = Mapper.map(dataset)

    assert_equal "ENVELOPE(-61.8, -61.42, 12.53, 12.0)", mapped['locn_geometry']
    assert_equal mapped['locn_geometry'], mapped['dcat_bbox']
  end

  def test_mapper_adds_geometry_for_hdx_country_names
    {
      "Democratic Republic of the Congo" => "ENVELOPE(12.18, 31.17, 5.26, -13.26)",
      "Côte d'Ivoire" => "ENVELOPE(-8.6, -2.56, 10.52, 4.34)",
      "Turks and Caicos Islands" => "ENVELOPE(-72.49, -71.12, 21.96, 21.29)"
    }.each do |country, envelope|
      dataset = {
        "id" => "test-dataset-hdx-country-name",
        "title" => "Test HDX country name dataset",
        "groups" => [{ "title" => country }]
      }
      mapped = Mapper.map(dataset)

      assert_equal envelope, mapped['locn_geometry'], country
    end
  end

  def test_mapper_ignores_groups_that_are_not_places
    dataset = {
      "id" => "test-dataset-crisis-group",
      "title" => "Test crisis group dataset",
      "groups" => [{ "title" => "Nepal" }, { "title" => "Nepal Earthquake" }]
    }
    mapped = Mapper.map(dataset)

    assert_equal "ENVELOPE(80.09, 88.17, 30.42, 26.4)", mapped['locn_geometry']
  end
end
