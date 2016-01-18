module namespace test = 'https://github.com/james-jw/geo-xq-test';
import module namespace geo = 'https://github.com/james-jw/geo-xq';

declare %unit:test test:to-geo-json-point-from-esri() {
  let $geom := map { 'x': 1, 'y': 2 }
  let $out := geo:to-geo-json($geom)
  return (
    unit:assert-equals($out?coordinates?x, $geom?x),
    unit:assert-equals($out?coordinates?y, $geom?y)
  )
};

declare %unit:test test:to-geo-json-lineString-from-esri-polyline() {
  let $geom := map { 'paths': array {
      array { (array { 1, 2}, array { 3, 4 }) }
  }
  let $out := geo:to-geo-json($geom)
  return (
    unit:assert-equals($out?coordinates?1?1, $geom?coordinates?1),
    unit:assert-equals($out?coordinates?1?2, $geom?coordinates?2)
  )
};

declare %unit:test test:to-geo-json-point-from-gml-point() {
  let $gml :=
  <gml:Point xmlns:gml="http://www.opengis.net/gml">
    <gml:coordinates>-86.77711799999999 32.608276000000004</gml:coordinates>
  </gml:Point>
  let $geom := geo:to-geo-json($gml)
  return (
    unit:assert-equals($gml/gml:coordinates => tokenize(), $geom?coordinates)
};

