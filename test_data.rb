require "csv"
require "minitest/autorun"
require "set"
require "stringex"

parameters = {
  :headers   => true,
  :col_sep   => ';',
  :encoding => 'UTF-8'
}

STATIONS = CSV.read("stations.csv", parameters)
STATIONS_BY_ID = STATIONS.inject({}) { |hash, station| hash[station["id"]] = station; hash }
STATIONS_UIC8_WHITELIST_IDS = ["1144"] # Exception : CDG TGV UIC8 is CDG 2 RER.

CHILDREN = {}
CHILDREN_COUNT = Hash.new(0)
STATIONS.each { |row| CHILDREN[row["id"]] = [] }
STATIONS.each do |row|
  if row["parent_station_id"]
    CHILDREN[row["parent_station_id"]] << row
    if row["is_suggestable"] == "t"
      CHILDREN_COUNT[row["parent_station_id"]] += 1
    end
  end
end

LOCALES = ["fr", "en", "de", "it"]

def slugify(name)
  name.gsub(/[\/\.]/,"-").to_url
end

class StationsTest < Minitest::Test

  def test_number_columns
    nb_columns = 32

    STATIONS.each { |row| assert_equal nb_columns, row.size, "Wrong number of columns #{row["size"]} for station #{row["id"]}" }
  end

  def validate_enabled_and_id_columns(carrier, id_column_size = nil)
    enabled_column = "#{carrier}_is_enabled"
    id_column      = "#{carrier}_id"
    unique_set     = Set.new

    STATIONS.each do |row|
      assert ["t", "f"].include?(row[enabled_column])

      id = row[id_column]
      if row[enabled_column] == "t"
        assert !id.nil?, "Missing #{id_column} for station #{row["id"]}"
      end

      if !id.nil?
        if id_column_size
          assert_equal id_column_size, row[id_column].size, "Invalid #{id_column}: #{row[id_column]} for station #{row["id"]}"
        end

        assert !unique_set.include?(row[id_column]), "Duplicated #{id_column} #{row[id_column]} for station #{row["id"]}"
        unique_set << row[id_column]
      end
    end
  end

  def test_db_enabled_and_id_columns
    validate_enabled_and_id_columns("db")
  end

  def test_idbus_enabled_and_id_columns
    validate_enabled_and_id_columns("idbus", 3)
  end

  def test_idtgv_enabled_and_id_columns
    validate_enabled_and_id_columns("idtgv", 3)
  end

  def test_ntv_enabled_and_id_columns
    validate_enabled_and_id_columns("ntv", 3)
  end

  def test_ouigo_enabled_and_id_columns
    validate_enabled_and_id_columns("ouigo", 3)
  end

  def test_sncf_enabled_and_id_columns
    validate_enabled_and_id_columns("sncf", 5)
  end

  def test_trenitalia_enabled_and_id_columns
    validate_enabled_and_id_columns("trenitalia", 7)
  end

  def test_ntv_enabled_and_id_columns
    validate_enabled_and_id_columns("ntv", 3)
  end

  def test_id_unicity
    uniq_size = STATIONS.map { |row| row["id"] }.uniq.size

    assert_equal STATIONS.size, uniq_size
  end

  def test_uic_unicity
    count = {}
    STATIONS.each do |row|
      if row["uic"]
        count[row["uic"]] = (count[row["uic"]] || 0) + 1
      end
    end

    count.each do |uic, count|
      if count != 1
       puts "Station with UIC #{uic} is duplicated"
      end
    end
  end

  def test_coordinates
    STATIONS.each do |row|
      lon = row["longitude"]
      lat = row["latitude"]

      if lon
        assert !lat.nil?, "Longitude of station #{row["id"]} set, but not latitude"
      end
      if lat
        assert !lon.nil?, "Latitude of station #{row["id"]} set, but not longitude"
      end

      if row["is_suggestable"] == "t"
        assert !lon.nil? && !lat.nil?, "Station #{row["id"]} is suggestable but has no coordinates"
      end

      if lon && lat
        lon = lon.to_f
        lat = lat.to_f

        # Very rough bounding box of Europe
        # Mostly tests if lon and lat are not switched
        assert_operator lon, :>, -10, "Coordinates of station #{row["id"]} not within the bounding box"
        assert_operator lon, :<, 39, "Coordinates of station #{row["id"]} not within the bounding box"
        assert_operator lat, :>, 35, "Coordinates of station #{row["id"]} not within the bounding box"
        assert_operator lat, :<, 68, "Coordinates of station #{row["id"]} not within the bounding box"
      end
    end
  end

  def test_sorted_by_id
    ids = STATIONS.map { |row| row["id"].to_i }

    assert ids == ids.sort, "The data is not sorted by the id column"
  end

  def test_is_suggestable
    STATIONS.each do |row|
      assert ["t", "f"].include?(row["is_suggestable"]), "Invalid value for is_suggestable for station #{row["id"]}"
    end
  end

  def test_is_main_station
    STATIONS.each do |row|
      assert ["t", "f"].include?(row["is_main_station"]), "Invalid value for is_main_station for station #{row["id"]}"
    end
  end

  def test_country
    STATIONS.each do |row|
      assert_match /[A-Z]{2}/, row["country"], "Invalid country for station #{row["id"]}"
    end
  end

  def test_time_zone
    STATIONS.each do |row|
      assert !row["time_zone"].empty? , "No timezone for station #{row["id"]}"
    end
  end

  def test_suggestable_has_name
    STATIONS.each do |row|
      if row["is_suggestable"] == "t"
        assert !row["name"].nil?, "Station #{row["id"]} is suggestable but has empty name"
      end
    end
  end

  def test_unique_suggestable_name
    names = Set.new

    STATIONS.each do |row|
      if row["is_suggestable"] == "t"
        assert !names.include?(row["name"]), "Duplicate name '#{row["name"]}'"

        names << row["name"]
      end
    end
  end

  def test_info_different_than_name
    STATIONS.each do |row|
      if row["is_suggestable"] == "t"
        LOCALES.each do |locale|
          refute_equal row["name"], row["info:#{locale}"], "Name and info station should be different: '#{row["name"]}'"
        end
      end
    end
  end

  def valid_carrier(row)
    row["db_is_enabled"] == "t" ||
      row["idbus_is_enabled"] == "t" ||
      row["idtgv_is_enabled"] == "t" ||
      row["ntv_is_enabled"] == "t" ||
      row["ouigo_is_enabled"] == "t" ||
      row["sncf_is_enabled"] == "t" ||
      row["trenitalia_is_enabled"] == "t"
  end

  def test_suggestable_has_carrier
    STATIONS.each do |row|
      if row["is_suggestable"] == "t"
        assert valid_carrier(row) || CHILDREN[row["id"]].any? { |r| valid_carrier(r) },
               "Station #{row["id"]} is suggestable but has no enabled system"
      end
    end
  end

  def test_idtgv_id
    STATIONS.each do |row|
      if row["idtgv_is_enabled"] == "t"
        assert_equal row["sncf_id"][2..5], row["idtgv_id"], "Station #{row["id"]} mismatched sncf_id and idtgv_id"
      end
    end
  end

  def test_parent_station
    STATIONS.each do |row|
      parent_id = row["parent_station_id"]
      if parent_id && row["is_suggestable"] == "t"
        parent = STATIONS_BY_ID[parent_id]
        assert !parent.nil?, "Station #{row["id"]} references a not existing parent station (#{parent_id})"
        assert !parent["name"].nil?, "The station #{parent_id} has no name (parent of station #{row["id"]})"
      end
    end
  end

  def test_slugify
    assert_equal slugify("Figueras/Figueres Vilafant Esp."), "figueras-figueres-vilafant-esp"
  end

  def test_slugs
    unique_set = Set.new

    STATIONS.each do |row|
      if row["is_suggestable"] == "t"
        assert_equal slugify(row["name"]), row["slug"], "Station #{row["id"]} has not a correct slug"
        assert !unique_set.include?(row["slug"]), "Duplicated slug '#{row["slug"]}' for station #{row["id"]}"
        unique_set << row["slug"]
      end
    end

  end

  def test_metastation_have_multiple_children
    CHILDREN_COUNT.each do |id, children_count|
      station = STATIONS_BY_ID[id]
      if station["is_suggestable"] == "t"
        assert children_count >= 2, "The meta station #{id} is suggestable and has only #{children_count} child."
      end
    end
  end

  def test_uic8_sncf
    STATIONS.each do |row|
      uic8_sncf = row["uic8_sncf"]
      uic = row["uic"]
      if !uic8_sncf.nil? && !STATIONS_UIC8_WHITELIST_IDS.include?(row["id"])
        assert uic == uic8_sncf[0...-1], "Station #{row["id"]} have an incoherent uic8_sncf code"
      end
    end
  end

end
