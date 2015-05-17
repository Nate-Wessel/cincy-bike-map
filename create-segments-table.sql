
-- add all fields useful to rendering highways to a split line table
-- split off from the network table from pgRouting
DROP TABLE IF EXISTS cincy_segments;
SELECT --lets just enumerate all the columns here
	id AS edge_id,
	osm_id,
	ST_Transform(geom_way,3735) AS the_geom,
	source,
	target,
	--we'll populate these from the other table in just a moment
	--for now they are empty
	null::varchar AS highway,
	null::varchar AS label,
	null::varchar AS cycleway,
	null::varchar AS "cycleway:left",
	null::varchar AS "cycleway:right",
	null::varchar AS surface,
	null::varchar AS bicycle,
	null::varchar AS access,
	null::real AS all_lanes,
	null::varchar AS mph,
	null::varchar AS oneway,
	null::varchar AS tunnel,
	null::varchar AS bridge,
	null::varchar AS layer,
	null::varchar AS service,
	null::varchar AS service_is_in,
	-- this is a spatial measure of length in miles
	ST_Length(ST_Transform(geom_way,3735)) / 5280 AS miles,
	--is part of primary biconnected component? TRUE = no
	false::boolean AS dangling
INTO cincy_segments
FROM c_2po_4pgr;  --<<----------<<---------SOURCE EDGE TABLE NAME--------<<--

-- for the join
CREATE INDEX ON cincy_segments (osm_id);

--get attributes from the cincy_line table
UPDATE cincy_segments AS cs
	SET 
		highway = cl.highway,
		label = cl.label,
		cycleway = cl.cycleway,
		"cycleway:left" = cl."cycleway:left",
		"cycleway:right" = cl."cycleway:right",
		surface = cl.surface,
		bicycle = cl.bicycle,
		access = cl.access,
		all_lanes = cl.all_lanes,
		mph = cl.mph,
		oneway = cl.oneway,
		tunnel = cl.tunnel,
		bridge = cl.bridge,
		layer = cl.layer,
		service = cl.service,
		service_is_in = cl.service_is_in
FROM cincy_line AS cl
WHERE cl.osm_id = cs.osm_id;

-- now index to speed things up
CREATE INDEX ON cincy_segments USING GIST(the_geom);
CREATE INDEX ON cincy_segments (source);
CREATE INDEX ON cincy_segments (target);

--drop stuff we don't want in here
DELETE FROM cincy_segments
WHERE 
	service IN ('ramp','parking_aisle','spur','drive-through')
	OR (
		highway IN ('motorway','motorway_link','footway','trunk','trunk_link','track')
		AND (bicycle IS NULL OR bicycle NOT IN ('yes','designated'))
	)
	OR
		(access IN ('no','emergency','private','official') AND
		highway != 'residential')
	OR
	service_is_in IN ('golf_course')
	OR
	bicycle IN ('no');
	
----------------------------------------------------------------------------
/*--------------------------------------------------------------------------
-----RUN tarjan.php at this point to detect dangling components-------------
---------------------------------------------------------------------------*/
---------------------------------------------------------------------------

--Delete minor dangling roads and paths-to-nowhere. 
DELETE FROM cincy_segments
WHERE 
	( highway = 'service' AND dangling )
	OR 
	( highway = 'path' AND (bicycle IS NULL OR bicycle != 'designated') AND dangling);
