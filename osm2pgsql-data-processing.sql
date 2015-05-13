/*
import with:
osm2pgsql --create --database osm --prefix cincy --style /home/nate/GIS/OSM/osm2pgsql/osm2pgsql.style --username nate --multi-geometry  --proj EPSG:4326 cincy.osm
*/

--LABELS
ALTER TABLE cincy_line ADD COLUMN label text;
--look for shortest possible name
UPDATE cincy_line 
SET label = 
	CASE 
		WHEN char_length(loc_name) < char_length(short_name) THEN loc_name
		WHEN short_name IS NOT NULL THEN short_name
		ELSE name
	END
WHERE short_name IS NOT NULL OR loc_name IS NOT NULL OR name IS NOT NULL;

UPDATE cincy_line 
SET label = 
	CASE	--trim ends of names
		WHEN label LIKE '% Street' THEN replace(label,' Street','')
		WHEN label LIKE '% Road' THEN replace(label,' Road','')
		WHEN label LIKE '% Court' THEN replace(label,' Court','')
		WHEN label LIKE '% Lane' THEN replace(label,' Lane','')
		WHEN label LIKE '% Avenue' THEN replace(label,' Avenue','')
		WHEN label LIKE '% Ave' THEN replace(label,' Ave','')
		WHEN label LIKE '% Drive' THEN replace(label,' Drive','')
		WHEN label LIKE '% Circle' THEN replace(label,' Circle','')
		WHEN label LIKE '% Boulevard' THEN replace(label,' Boulevard','')
		WHEN label LIKE '% Place' THEN replace(label,' Place','')
		WHEN label LIKE '% Parkway' THEN replace(label,' Parkway','')
		WHEN label LIKE '% Viaduct' THEN replace(label,' Viaduct','')
		WHEN label LIKE '% Bridge' THEN replace(label,' Bridge','')
		WHEN label LIKE '% Highway' THEN replace(label,' Highway','')
		WHEN label LIKE '% Pike' THEN replace(label,' Pike','')
		ELSE label	
	END
WHERE highway IS NOT NULL;

UPDATE cincy_line
SET label = 
	CASE    --trim directions from beginnings of names
		WHEN label LIKE 'East %' THEN replace(label,'East ','')
		WHEN label LIKE 'West %' THEN replace(label,'West ','')
		WHEN label LIKE 'North %' THEN replace(label,'North ','')
		WHEN label LIKE 'South %' THEN replace(label,'South ','')		
		ELSE label	
	END
WHERE 
	highway IS NOT NULL AND 
	label IS NOT NULL AND 
	label NOT IN ('North Bend%','West Fork%'); --only trim highways...don't want to mislabel East Walnut Hills or something


/*SPEEDS*/

/*add new MPH column and populate with available data*/
ALTER TABLE cincy_line ADD COLUMN mph integer;
UPDATE cincy_line
SET mph =
	CASE
		WHEN maxspeed LIKE '% mph' THEN replace(maxspeed,' mph','')::integer
		WHEN maxspeed LIKE '%mph' THEN replace(maxspeed,'mph','')::integer
		ELSE maxspeed::integer * 0.621371 /*conversion factor from KMPH*/
	END
WHERE maxspeed IS NOT NULL;
/*set DEFAULT speed limits by highway type*/
UPDATE cincy_line
SET mph = 
	CASE
		WHEN highway IN ('motorway','motorway_link') THEN 55
		WHEN highway IN ('primary','primary_link') THEN 45
		WHEN highway IN ('secondary','secondary_link') THEN 35
		WHEN highway IN ('tertiary','tertiary_link') THEN 30
		WHEN highway IN ('residential','unclassified') THEN 25
		WHEN highway IN ('service','') THEN 10
		ELSE NULL
	END
WHERE 
	mph IS NULL AND 
	highway IS NOT NULL;


/*SERVICE ROADS*/

ALTER TABLE cincy_line ADD COLUMN service_is_in varchar;
/*service roads in golf_courses*/
UPDATE cincy_line
SET service_is_in = 'golf_course'
WHERE osm_id IN (
	SELECT L.osm_id
	FROM cincy_line AS L, cincy_polygon AS P
	WHERE 
		L.highway = 'service' AND 
		P.leisure = 'golf_course' AND 
		ST_Intersects(L.way, P.way)
);
/*service roads in cemeteries*/
UPDATE cincy_line
SET service_is_in = 'cemetery'
WHERE osm_id IN (
	SELECT L.osm_id
	FROM cincy_line AS L, cincy_polygon AS P
	WHERE
		L.highway = 'service' AND
		P.landuse = 'cemetery' AND
		ST_Intersects(L.way, P.way)
);
/*service roads in parks*/
UPDATE cincy_line
SET service_is_in = 'park'
WHERE osm_id IN (
	SELECT L.osm_id
	FROM cincy_line AS L, cincy_polygon AS P
	WHERE
		L.highway = 'service' AND 
		P.leisure = 'park' AND 
		ST_Intersects(L.way, P.way) 
);


/*LANES*/

--create a new column for altered lane values
ALTER TABLE cincy_line ADD COLUMN all_lanes real;
--set lane values where we have them already
UPDATE cincy_line 
SET all_lanes = 
	CASE 
		WHEN oneway IN ('yes','reverse') THEN lanes * 2 --oneway factor
		ELSE lanes
	END
WHERE lanes IS NOT NULL;
--set lane values to defaults where we don't have an explicit value
-- these are effectively already doubled by default for one-ways
UPDATE cincy_line
SET all_lanes = 
	CASE
		WHEN highway IN (
			'motorway',
			'trunk') THEN 6       -- six
		WHEN highway IN (
			'primary') THEN 4     -- four
		WHEN highway IN (
			'secondary',
			'motorway_link',
			'trunk_link') THEN 3   -- three
		WHEN highway IN (
			'primary_link',
			'secondary_link',
			'tertiary_link',
			'tertiary',
			'residential',
			'unclassified',
			'road') THEN 2       -- two
		WHEN highway IN (
			'service') THEN 1    -- one
		ELSE 1                 -- one
	END
WHERE 
	lanes IS NULL AND 
	highway IS NOT NULL;

/*POINTS*/   /*from polygons*/

/*supermarkets*/
INSERT INTO cincy_point (osm_id,shop,name,way)
SELECT osm_id,'supermarket' AS shop, name, ST_Centroid(way) AS way
FROM cincy_polygon 
WHERE amenity = 'marketplace' OR shop = 'supermarket';


/*coffee shops*/
INSERT INTO cincy_point (osm_id,amenity,name,way,cuisine)
SELECT osm_id, amenity, name, ST_Centroid(way),cuisine
FROM cincy_polygon 
WHERE amenity = 'cafe' AND cuisine = 'coffee_shop';


/*POLYGONS*/
/*merge all touching river segments*/
Insert INTO cincy_polygon (waterway, name, way)
SELECT 'riverbank',
	'merged_rivers',
	ST_Union(way)
FROM cincy_polygon
WHERE waterway = 'riverbank' OR leisure = 'marina'
GROUP BY waterway;
/*Clean up what are now duplicates*/
DELETE FROM cincy_polygon
WHERE waterway = 'riverbank' AND (name != 'merged_rivers' OR name IS NULL);


/*
Identify landmark buildings
*/
ALTER TABLE cincy_polygon ADD COLUMN landmark_building boolean;
UPDATE cincy_polygon SET landmark_building = false;
UPDATE cincy_polygon SET landmark_building = true
WHERE osm_id IN (
	141726417, --St John church Covington
	123059448, --Covington Basilica
	80307110 , --Covington Ascent tower
	168830714, --casino
	42786531,42786524,162656312, --DAAP
	27922392,27922376 , --Cincy State
	157499875, --Can Lofts in Northside
	27669543, --Union Terminal
	30735242, --Longworth Hall
	80308915, --Assumption of Mary church, covington
	49231068, --Mount Airy watertower
	46704876, --The Crosley Building
	-1185188, --Cincinnati City Hall
	91327377, 100146895, 91489690, 93602243, --Carew Tower
	40047145, --Music Hall
	69701756, --Desales Corner church
	95661163, 56225682, 56225983, 56225652, --Christ Hospital
	31009336, 31009349, --ballpark
	-280132, --football stadium
	55750519, --school on stilts
	263067886, --Mt Washington watertower
	42269236, --the freedom bell
	115828127, --crosley tower
	51133765, --good sam hospital
	28718288, --newport on the levee
	66985209, --St. monica, st. george, clifton heights
	-1338829, --art museum
	2474228, -- vontz center, that ugly medical building 
	80321957, --huge college hill old-people's home with the two towers
	34230865, -- greyhound station
	162285313, -- big church in cumminsville
	97668106, -- collapsing silo on the mill creek
	201239198, -- big weird cement tower in mt airy
	80320130, -- mayerson JCC
	33650831, -- round hotel in covington
	43541266-- cincinnati gardens arena
);
-- create fields and defaults for special building types
ALTER TABLE cincy_polygon 
	ADD COLUMN hs_building boolean,
	ADD COLUMN commercial_building boolean,
	ADD COLUMN university_building boolean;
UPDATE cincy_polygon SET 
	hs_building = false,
	commercial_building = false,
	university_building = false;

--identify high school buildings
UPDATE cincy_polygon AS b SET hs_building = true
FROM cincy_polygon AS hs
WHERE 
	b.building IS NOT NULL AND 
	hs.amenity = 'school' AND hs.name LIKE '%High%' AND 
	ST_Within(b.way, hs.way);
	
-- identify university buildings
UPDATE cincy_polygon AS b SET university_building = true
FROM cincy_polygon AS u
WHERE 
	b.building IS NOT NULL AND 
	u.amenity IN ('university','college') AND
	ST_Within(b.way, u.way);
	
-- identify retail buildings
UPDATE cincy_polygon AS b SET commercial_building = true
FROM cincy_polygon AS c
WHERE 
	b.building IS NOT NULL AND 
	c.landuse IN ('retail') AND
	ST_Within(b.way, c.way);


--measure length
ALTER TABLE cincy_line ADD COLUMN feet real;
UPDATE cincy_line SET feet = ST_Length(ST_Transform(way,3735));
--measure area
ALTER TABLE cincy_polygon ADD COLUMN sqfeet real;
UPDATE cincy_polygon SET sqfeet = ST_Area(ST_Transform(way,3735));
