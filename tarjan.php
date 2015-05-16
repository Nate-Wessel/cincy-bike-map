<?php
$username = 'POSTGRESQL USERNAME HERE';
$password = 'POSTGRESQL PASSWORD HERE';
$database = 'DATABASE NAME';

$edge_table = 'NAME OF TABLE FROM OSM2PGROUTING';
$v1 = 'COLUMN NAME OF VERTEX 1';
$v2 = 'COLUMN NAME OF VERTEX 2';
$dangling_boolean_field = 'NAME OF BOOLEAN FLAG FIELD'; //indicates whether edge is part of main network
$edge_id_field = 'NAME OF COLUMN CONTAINING EDGE ID'; 

//global variables declared
$index = 0;
$component_index = 0;
$nodes = array();
$stack = array();

pg_connect("host=localhost dbname=$database user=$username password=$password");

// get vertices
echo "getting data from database\n";
$neighbors_query = pg_query("
WITH nodes AS (
	SELECT DISTINCT $v1 AS node FROM $edge_table
	UNION
	SELECT DISTINCT $v2 AS node FROM $edge_table
), 
edges AS (
SELECT 
	node,
	$edge_id_field AS edge
FROM nodes JOIN $edge_table
	ON node = $v1 OR node = $v2
)
SELECT
	node,
	array_agg(CASE WHEN node = $v2 THEN $v1 
	WHEN node = $v1 THEN $v2
	ELSE NULL
	END) AS neighbor	
FROM edges JOIN $edge_table ON 
	(node = $v2 AND edge = $edge_id_field) OR 
	(node = $v1 AND edge = $edge_id_field)
GROUP BY node");

// now make the results into php results
echo "putting the results in an array\n";
while($r = pg_fetch_object($neighbors_query)){ // for each node record
	$nodes[$r->node]['id'] = $r->node;
	$nodes[$r->node]['neighbors'] = explode(',',trim($r->neighbor,'{}'));
}

// create a temporary table to store results
pg_query("
	DROP TABLE IF EXISTS temp_nodes;
	CREATE TABLE temp_nodes (node integer, component integer);
");

// the big traversal
echo "traversing graph (this part takes a while)\n";
foreach($nodes as $id => $values){
	if(!isset($values['index'])){
		tarjan($id, 'no parent');
	}
}

// identify dangling edges
echo "identifying dangling edges\n";
pg_query("
	UPDATE $edge_table SET $dangling_boolean_field = FALSE; 
	WITH dcn AS ( -- DisConnected Nodes
		-- get nodes that are NOT in the primary component
		SELECT node FROM temp_nodes WHERE component != (
			-- select the number of the largest component
			SELECT component
			FROM temp_nodes 
			GROUP BY component 
			ORDER BY count(*) DESC
			LIMIT 1)
	),
	edges AS (
		SELECT DISTINCT e.$edge_id_field AS disconnected_edge_id
		FROM 
			dcn JOIN $edge_table AS e ON dcn.node = e.$v1 OR dcn.node = e.$v2
	)
	UPDATE $edge_table SET $dangling_boolean_field = TRUE
	FROM edges WHERE $edge_id_field = disconnected_edge_id;
");

// clean up after ourselves
echo "cleaning up\n";
pg_query("DROP TABLE IF EXISTS temp_nodes;");
pg_query("VACUUM ANALYZE;");

 // the recursive function definition
//
function tarjan($id, $parent)
{
	global $nodes;
	global $index;
	global $component_index;
	global $stack;

	// mark and push
	$nodes[$id]['index'] = $index;
	$nodes[$id]['lowlink'] = $index;
	$index++;
	array_push($stack, $id);

	// go through neighbors
	foreach ($nodes[$id]['neighbors'] as $child_id) {
		if ( !isset($nodes[$child_id]['index']) ) { // if neighbor not yet visited
			// recurse
			tarjan($child_id, $id);
			// find lowpoint
			$nodes[$id]['lowlink'] = min(
				$nodes[$id]['lowlink'],
				$nodes[$child_id]['lowlink']
			);
		} else if ($child_id != $parent) { // if already visited and not parent
			// assess lowpoint
			$nodes[$id]['lowlink'] = min(
				$nodes[$id]['lowlink'],
				$nodes[$child_id]['index']
			);
		}
	}
	// was this a root node?
	if ($nodes[$id]['lowlink'] == $nodes[$id]['index']) {
		do {
			$w = array_pop($stack);
			$scc[] = $w;
		} while($id != $w);
		// record results in table
		pg_query("
			INSERT INTO temp_nodes (node, component)
			VALUES (".implode(','.$component_index.'),(',$scc).",$component_index) 
		");
		$component_index++;
	}
	return NULL;
}

?>
