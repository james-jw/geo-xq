module namespace test = 'https://github.com/james-jw/geo-xq-test';
import module namespace geo = 'https://github.com/james-jw/geo-xq';
declare namespace gml = "http://www.opengis.net/gml";
declare namespace kml = "http://www.opengis.net/kml/2.2";

declare %unit:test function test:as-geo-json-point-from-esri() {
  let $geom := map { 'x': 1, 'y': 2 }
  let $out := geo:as-geo-json-geom($geom)
  return (
    unit:assert-equals($out?coordinates?1, $geom?x),
    unit:assert-equals($out?coordinates?2, $geom?y)
  )
};

declare %unit:test function test:as-geo-json-lineString-from-esri-polyline() {
  let $geom := map { 'paths': array {
      array { (array { 1, 2}, array { 3, 4 }) }
  }}
  let $out := geo:as-geo-json($geom)
  return (
    unit:assert-equals($out?coordinates?1?1, $geom?coordinates?1),
    unit:assert-equals($out?coordinates?1?2, $geom?coordinates?2)
  )
};

declare %unit:test function test:as-geo-json-point-from-gml-point() {
  let $gml :=
  <gml:Point>
    <gml:coordinates>-86.77711799999999 32.608276000000004</gml:coordinates>
  </gml:Point>
  let $geom := geo:from-gml-geom($gml)
  return (
    unit:assert-equals($geom?coordinates?2, 32.608276000000004))
};

declare %unit:test function test:as-geo-json-point-from-kml-point() {
  let $kml := 
    <kml xmlns="http://www.opengis.net/kml/2.2">
      <Placemark>
        <name>Simple placemark</name>
        <description>
          Attached to the ground. Intelligently places itself at the
          height of the underlying terrain.
        </description>
        <Point>
          <coordinates>-122.0822035425683,37.42228990140251,0</coordinates>
        </Point>
      </Placemark>
    </kml>
    let $geom := geo:from-kml($kml/kml:Placemark)
  return (
    unit:assert-equals($geom?geometry?coordinates?2, 37.42228990140251)
  )
};

declare variable $test:kml-point := 
     <kml xmlns="http://www.opengis.net/kml/2.2">
      <Placemark>
        <name>Simple placemark</name>
        <description>A simple marker</description>
        <LineString>
           <coordinates>
        -112.080622229595,36.10673460007995,0
        -112.085242575315,36.09049598612422,0
      </coordinates>
        </LineString>
      </Placemark>
    </kml>;
    
declare %unit:test function test:as-get-json-linestring-from-kml() {
 let $geom := geo:from-kml($test:kml-point/kml:Placemark)
  return 
    unit:assert-equals($geom?geometry?coordinates?2?2, 36.09049598612422)
};

declare %unit:test function test:as-geo-json-from-kml() {
 let $geom := geo:as-geo-json-geom($test:kml-point//kml:LineString)
  return 
    unit:assert-equals($geom?coordinates?2?2, 36.09049598612422)
};

declare %unit:test function test:as-geo-json-from-esri() {
  let $geom := map { 'paths': array {
      array { (array { 1.23, 2.23213}, array { 3.293, 42.23 }) }
  }}
  let $out := geo:as-geo-json-geom($geom)
  return unit:assert-equals($out?coordinates?1?2, $geom?paths?1?1?2 )
};

declare %unit:test function test:as-geo-json-from-gml() {
  let $geom :=
  <gml:Point>
    <gml:coordinates>-86.77711799999999 32.608276000000004</gml:coordinates>
  </gml:Point>
  let $geoJson := geo:as-geo-json-geom($geom)
  return
    unit:assert-equals($geoJson?coordinates?2, 32.608276000000004)
};

(:
import module namespace p = 'https://github.com/james-jw/xq-promise';
import module namespace geo = 'https://github.com/james-jw/geo-xq';
declare namespace gml='http://www.opengis.net/gml';

let $db := db:open("DetailedCounties")
let $geoms := ($db//feature/gml:*)
return p:fork-join(
  for $geom in $geoms
  return
  p:defer(geo:from-gml-geom(?), $geom)
, 2)
:)
