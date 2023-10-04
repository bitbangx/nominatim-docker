UPDATE places p SET address_rank = x.rank_address, osm_type = x.osm_type, osm_id = x.osm_id
FROM placex x
WHERE x.place_id = p.place_id;

UPDATE kam_places SET address_class = CASE
    WHEN address_rank = 0 AND osm_type = 'R' THEN 0
    WHEN address_rank >= 1 AND address_rank <= 3 AND osm_type = 'R' THEN 1
    WHEN address_rank >= 4 AND address_rank <= 4 AND osm_type = 'R' THEN 2
    WHEN address_rank >= 5 AND address_rank <= 9 AND osm_type = 'R' THEN 3
    WHEN address_rank >= 10 AND address_rank <= 12 AND osm_type = 'R' THEN 4
    WHEN address_rank >= 13 AND address_rank <= 16 AND osm_type = 'R' THEN 5
    WHEN address_rank >= 17 AND address_rank <= 21 AND osm_type = 'R' THEN 6
    WHEN address_rank >= 22 AND address_rank <= 24 AND osm_type = 'R' THEN 7
    ELSE NULL
  END;

UPDATE places SET address = get_place_address(
    place_id,
    -1,
    ARRAY ['name:it-IT','name:it','name:en-US','name:en','name','brand','official_name:it-IT','short_name:it-IT','official_name:it','short_name:it','official_name:en-US','short_name:en-US','official_name:en','short_name:en','official_name','short_name','ref','type']
  );

UPDATE places SET short_address = get_place_address(
    place_id,
    -1,
    ARRAY ['short_name:it-IT','short_name:it','short_name:en-US','short_name:en','short_name','name:it-IT','name:it','name:en-US','name:en','name','brand','official_name:it-IT','official_name:it','official_name:en-US','official_name:en','official_name','type','ref']
  );

UPDATE places p SET short_name = get_name_by_language(
    x.name,
    ARRAY ['short_name:it-IT','short_name:it','short_name:en-US','short_name:en','short_name','name:it-IT','name:it','name:en-US','name:en','name','brand','official_name:it-IT','official_name:it','official_name:en-US','official_name:en','official_name','type','ref']
  )
FROM placex x
WHERE x.place_id = p.place_id;