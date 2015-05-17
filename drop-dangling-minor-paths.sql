/*------------------------------------------
-----run tarjan.php before this-------------
------------------------------------------*/

--Delete minor dangling roads and paths-to-nowhere. 
DELETE FROM cincy_segments
WHERE 
	( highway = 'service' AND dangling )
	OR 
	( highway = 'path' AND (bicycle IS NULL OR bicycle != 'designated') AND dangling);
