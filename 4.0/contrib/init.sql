CREATE OR REPLACE FUNCTION get_place_address_data(in_place_id BIGINT, full_address BOOLEAN)
  RETURNS setof addressline
  AS $$
DECLARE
  place addressdata_place;
  location RECORD;
  country RECORD;
  current_class_address INTEGER;
  location_isaddress BOOLEAN;
BEGIN
  -- The place in question might not have a direct entry in place_addressline.
  -- Look for the parent of such places then and save it in place.

  -- POI objects in the placex table
  IF place IS NULL THEN
    SELECT parent_place_id as place_id, country_code,
           coalesce(address->'housenumber',
                    address->'streetnumber',
                    address->'conscriptionnumber')::text as housenumber,
           postcode,
           class, type,
           name, address,
           centroid
      INTO place
      FROM placex
      WHERE place_id = in_place_id and rank_search > 27;
  END IF;

  -- If place is still NULL at this point then the object has its own
  -- entry in place_address line. However, still check if there is not linked
  -- place we should be using instead.
  IF place IS NULL THEN
    select coalesce(linked_place_id, place_id) as place_id,  country_code,
           null::text as housenumber, postcode,
           class, type,
           null as name, address,
           null as centroid
      INTO place
      FROM placex where place_id = in_place_id;
  END IF;

  --RAISE WARNING '% % % %',searchcountrycode, searchhousenumber, searchpostcode;

  -- --- Return the record for the base entry.

  FOR location IN
    SELECT placex.place_id, osm_type, osm_id, name,
          coalesce(extratags->'linked_place', extratags->'place') as place_type,
          class, type, admin_level,
          CASE
            WHEN rank_address >= 1 AND rank_address <= 3 AND osm_type = 'R' THEN 1
            WHEN rank_address >= 4 AND rank_address <= 4 AND osm_type = 'R' THEN 2
            WHEN rank_address >= 5 AND rank_address <= 9 AND osm_type = 'R' THEN 3
            WHEN rank_address >= 10 AND rank_address <= 12 AND osm_type = 'R' THEN 4
            WHEN rank_address >= 13 AND rank_address <= 16 AND osm_type = 'R' THEN 5
            WHEN rank_address >= 17 AND rank_address <= 21 AND osm_type = 'R' THEN 6
            WHEN rank_address >= 22 AND rank_address <= 24 AND osm_type = 'R' THEN 7
            ELSE 0
          END as class_address,
          country_code
      FROM placex
      WHERE place_id = place.place_id
  LOOP
  --RAISE WARNING '%',location;
    -- mix in default names for countries
    IF location.class_address = 1 and place.country_code is not NULL THEN
      FOR country IN
        SELECT coalesce(name, ''::hstore) as name FROM country_name
          WHERE country_code = place.country_code LIMIT 1
      LOOP
        place.name := country.name || place.name;
      END LOOP;
    END IF;

    IF location.class_address < 1 THEN
      -- no country locations for ranks higher than country
      place.country_code := NULL::varchar(2);
    ELSEIF place.country_code IS NULL AND location.country_code IS NOT NULL THEN
      place.country_code := location.country_code;
    END IF;

    IF full_address IS true THEN
      RETURN NEXT ROW(location.place_id, location.osm_type, location.osm_id,
                      location.name, location.class, location.type,
                      location.place_type,
                      location.admin_level, true,
                      location.type not in ('postcode', 'postal_code'),
                      location.class_address, 0)::addressline;
    END IF;

    current_class_address := location.class_address;
  END LOOP;

  -- --- Return records for address parts.

  FOR location IN
    SELECT placex.place_id, osm_type, osm_id, name, class, type,
           coalesce(extratags->'linked_place', extratags->'place') as place_type,
           admin_level, fromarea, isaddress,
           CASE 
            WHEN rank_address >= 1 AND rank_address <= 3 AND osm_type = 'R' THEN 1
            WHEN rank_address >= 4 AND rank_address <= 4 AND osm_type = 'R' THEN 2
            WHEN rank_address >= 5 AND rank_address <= 9 AND osm_type = 'R' THEN 3
            WHEN rank_address >= 10 AND rank_address <= 12 AND osm_type = 'R' THEN 4
            WHEN rank_address >= 13 AND rank_address <= 16 AND osm_type = 'R' THEN 5
            WHEN rank_address >= 17 AND rank_address <= 21 AND osm_type = 'R' THEN 6
            WHEN rank_address >= 22 AND rank_address <= 24 AND osm_type = 'R' THEN 7
            ELSE NULL
           END as class_address,
           distance, country_code, postcode
      FROM place_addressline join placex on (address_place_id = placex.place_id)
      WHERE place_addressline.place_id IN (place.place_id, in_place_id)
            AND linked_place_id is null
            AND (placex.country_code IS NULL OR place.country_code IS NULL
                 OR placex.country_code = place.country_code)
      ORDER BY class_address desc,
               (place_addressline.place_id = in_place_id) desc,
               (CASE WHEN coalesce((avals(name) && avals(place.address)), False) THEN 2
                     WHEN isaddress THEN 0
                     WHEN fromarea
                          and place.centroid is not null
                          and ST_Contains(geometry, place.centroid) THEN 1
                     ELSE -1 END) desc,
               fromarea desc, distance asc, rank_search desc
  LOOP
    -- RAISE WARNING '%',location;
    location_isaddress := location.class_address != current_class_address;

    IF place.country_code IS NULL AND location.country_code IS NOT NULL THEN
      place.country_code := location.country_code;
    END IF;
    IF location.type in ('postcode', 'postal_code')
       AND place.postcode is not null
    THEN
      -- If the place had a postcode assigned, take this one only
      -- into consideration when it is an area and the place does not have
      -- a postcode itself.
      IF location.fromarea AND location.isaddress
         AND (place.address is null or not place.address ? 'postcode')
      THEN
        place.postcode := null; -- remove the less exact postcode
      ELSE
        location_isaddress := false;
      END IF;
    END IF;
    RETURN NEXT ROW(location.place_id, location.osm_type, location.osm_id,
                    location.name, location.class, location.type,
                    location.place_type,
                    location.admin_level, location.fromarea,
                    location_isaddress,
                    location.class_address,
                    location.distance)::addressline;

    current_class_address := location.class_address;
  END LOOP;

  -- If no country was included yet, add the name information from country_name.
  IF current_class_address > 1 THEN
    FOR location IN
      SELECT *, CASE 
          WHEN rank_address >= 1 AND rank_address <= 3 AND osm_type = 'R' THEN 1
          WHEN rank_address >= 4 AND rank_address <= 4 AND osm_type = 'R' THEN 2
          WHEN rank_address >= 5 AND rank_address <= 9 AND osm_type = 'R' THEN 3
          WHEN rank_address >= 10 AND rank_address <= 12 AND osm_type = 'R' THEN 4
          WHEN rank_address >= 13 AND rank_address <= 16 AND osm_type = 'R' THEN 5
          WHEN rank_address >= 17 AND rank_address <= 21 AND osm_type = 'R' THEN 6
          WHEN rank_address >= 22 AND rank_address <= 24 AND osm_type = 'R' THEN 7
          ELSE NULL
          END as class_address
        FROM placex
        WHERE country_code=place.country_code AND rank_address = 4 LIMIT 1
    LOOP
    --RAISE WARNING '% % %',current_class_address,searchcountrycode,countryname;
      RETURN NEXT ROW(location.place_id, location.osm_type, location.osm_id,
                    location.name, location.class, location.type,
                    null,
                    location.admin_level, null,
                    true,
                    location.class_address,
                    null)::addressline;
    END LOOP;
  END IF;

  RETURN;
END;
$$
LANGUAGE plpgsql STABLE;




CREATE OR REPLACE FUNCTION get_place_address(for_place_id BIGINT,
                                                   housenumber INTEGER,
                                                   languagepref TEXT[])
  RETURNS TEXT
  AS $$
DECLARE
  result TEXT[];
  currresult TEXT;
  prevresult TEXT;
  location RECORD;
BEGIN

  result := '{}';
  prevresult := '';

  FOR location IN
    SELECT place_id, name,
       CASE WHEN place_id = for_place_id THEN 99 ELSE rank_address END as rank_address
    FROM get_place_address_data(for_place_id, false)
    WHERE isaddress order by rank_address desc
  LOOP
    currresult := trim(get_name_by_language(location.name, languagepref));
    IF currresult != prevresult AND currresult IS NOT NULL
       AND result[(100 - location.rank_address)] IS NULL
    THEN
      result[(100 - location.rank_address)] := currresult;
      prevresult := currresult;
    END IF;
  END LOOP;

  RETURN array_to_string(result,', ');
END;
$$
LANGUAGE plpgsql STABLE;