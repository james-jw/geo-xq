(:~
 : Geo Utility module for working with GeoJSON, GML and ESRI features
 : @author James Wright
 :)
module namespace geo = 'https://github.com/james-jw/geo-xq';
declare namespace gml ='http://www.opengis.net/gml';
declare namespace kml = "http://www.opengis.net/kml/2.2";

declare variable $geo:unknownGeometry := xs:QName('geo:unknownGeometry');

declare %private function geo:get($service, $paths) {
  $paths ! geo:request($service, '/' || .)
};

(: Internal helper method :)
declare function geo:process-response($res) {
  try { $res[2] => parse-json() }
  catch * { $res[2] }
};

(:~ 
 : Makes a request, but does not process the response 
 : @param $service - Service to make the request against 
 : @param $url - Full or relative url of the endpoint to request
 : @param $method - HTTP verb to utilize (GET, PUT, POST, DELETE, HEAD)
 :)
declare function geo:primitive-request($service, $url, $method) {
  let $url := 
    if($url => matches('f=json')) then $url 
    else (
      if($url => contains('?')) then $url || '&amp;f=json'
      else $url || '?f=json'
    )
  let $req := element http:request { $service?request/@*, attribute method {$method}}
  let $decoded-url := trace(web:decode-url($url))
  return 
    http:send-request($req, ($service?_url || $url))
};

(:~ 
 : Makes a request, processing the response as JSON 
 : @param $service - Service to make the request against 
 : @param $url - Full or relative url of the endpoint to request
 : @param $method - HTTP verb to utilize (GET, PUT, POST, DELETE, HEAD)
 :)
declare function geo:request($service, $url, $method) {
  geo:primitive-request($service, $url, $method)
     => geo:process-response()
};

(:~ 
 : Makes a GET request, processing the response as JSON 
 : @param $service - Service to make the request against 
 : @param $url - Full or relative url of the endpoint to request
 :)
declare function geo:request($service, $url) {
  geo:request($service, $url, 'GET')
};

(:~
 : Creates a request template for connecting to a passord protected service
 : @param $login - Username to use
 : @param $password - Password to use
 :)
declare function geo:request-template($login, $password) {
  if($login) then
    <http:send-request username="{$login}" password="{$password}" send-authorization="true" />
  else 
    <http:send-request />
};

(:~ Connect to a non secured service :)
declare function geo:request-template() {
  geo:request-template((), ())
};

(:~
 : Connects to the specified service url with the provided 
 : request template object
 :)
declare function geo:connect($req, $url as xs:string) {
  map:merge((geo:request(map { '_request': $req }, $url), map { 
    '_url': $url,
    '_request': $req
  }))
};

(:~ 
 : Retrieves a list of layer names/ids from the provided service if they
 : exist; otherwise, returns the empty sequence
 : @param Service to request the layers from
 : @return Layer names
 :)
declare function geo:layers($service) {
  $service?layers?*
};

(:~
 : Retrieves the layer details for the provided layers on the
 : specified service
 : @param $service - Service to request the layers from
 : @param $layers - Layers to request
 : @return Request layer details
 :)
declare function geo:get-layers($service, $layers) {
  geo:get($service, $layers?id)
};

(:~
 : Retrieves the layer details for the provided layers on the
 : specified service
 : @param $service - Service to request the layers from
 : @param $folders - folders to request
 : @return Request folder details
 :)
declare function geo:get-folders($server, $folders) {
  geo:get($server, $folders)
};

(:~
 : Returns service details for the provided server
 : @param $server - Servier to retrieve the services from
 : @param $services - List of services to retrieve
 : @return Service details for the requested services
 :)
declare function geo:get-services($server, $services) {
  for $path in ($services ! (.?name || '/' || .?type))
  let $service := geo:get($server, $path)
  return map:merge(($service, map {
    '_url': $server?_url || '/' || $path,
    '_request': $server?_request
  }))
};

(:~
 : Queries the service layer with the provided query parameters
 : @param $service - Service to query
 : @param $layer - Layer to query
 : @param $query - Query parameters as map(xs:string)
 : @return Result of the query 
 :)
declare function geo:query-layer($service, $layer, $query) {
  let $url := '/' || $layer?id || '/query'
  return try { geo:request($service, web:create-url($url, $query)) } 
         catch * {($err:description)}
};

(:~
 : Same as query-layer but returns the result as XML instead of JSON
 : @param $service - Service to query
 : @param $layer - Layer to query
 : @param $query - Query parameters as map(xs:string)
 : @param $index - If 0 is provided, the entire collection will be paged. If
 : the empty sequence is provided, no auto paging will occur
 : @return Result of the query 
 :)
declare function geo:query-layer-xml($service, $layer, $queryIn, $index) {
  let $url := '/' || $layer?id || '/query'
  let $where := trace($queryIn?where)
  let $query := 
   if($index >= 0) then map:put($queryIn, 'where', trace('ObjectID > ' || format-number($index, '#')))
   else $queryIn
  let $res := (geo:primitive-request($service, web:create-url($url, $query), 'GET'))
  let $headers := trace($res[1]/@status)
  return  
    let $features :=
      for $feature in ($res[2] => json:parse())/json/features/_
      return
        <feature>
           {$feature/attributes}
           {geo:as-geo-json-geom(json:serialize(<json type="object">{$feature/geometry/*}</json>) => parse-json()) => geo:as-gml-geom()}
        </feature>
     return
        ($features, 
          if($index >= 0 and trace(count($features)) = 1000) then
            let $maxId := trace(max($features/attributes/ObjectID), 'maxid ')
            return 
              geo:query-layer-xml($service, $layer, $query, trace($maxId, 'subQuery: '))
          else ()
        )
};

(:~ 
 : Converts an ESRI JSON geometry into a GeoJSON geometry 
 : @param $geom - Geometry to convert
 : @return GeoJSON geometry
 :)
declare function geo:as-geo-json-geom($geometry) {
  if($geometry => geo:is-gml()) then geo:from-gml-geom($geometry)
  else if($geometry => geo:is-kml()) then geo:from-kml-geom($geometry)
  else if($geometry => geo:is-geo-json()) then $geometry
  else if($geometry => geo:is-esri()) then
    let $geom := ($geometry?geometry, $geometry)[1]
    return
      if($geom?x) then map {
        'type': 'Point',
        "coordinates": array { 
          $geom?x, $geom?y 
        }
      } 
      else if(exists($geom?paths)) then map {
        'type': 'LineString',
        'coordinates': $geom?paths?1
      }
      else if(exists($geom?rings)) then map {
        'type': 'Polygon',
        'coordinates': $geom?rings
      }
      else ()
   else(fn:error($geo:unknownGeometry, 'Invalid or unknown geometry type.'))
};

(:~ 
 : Converts an ESRI JSON, GML or KML feature into a GeoJSON feature 
 : @param $feature - feature to convert
 : @return GeoJSON geometry
 :)
declare function geo:as-geo-json($features) {
  let $features := 
     if($features[1] => geo:is-gml()) then geo:from-gml($features)
     else if($features[1] => geo:is-kml()) then geo:from-kml($features)
     else if($features[1] => geo:is-geo-json()) then $features
     else if($features[1] => geo:is-esri()) then
      for $feature in $features return
      map:merge((
        map { 'geometry': geo:as-geo-json-geom($feature) },
        map { 'properties': $feature?attributes }
      ))
     else (fn:error($geo:unknownGeometry, 'Not a valid, or compatible geometry type.', $features))
  return $features
};

(:~ 
 : Denotes if a single feature is an ESRI JSON geometry
 : @geom Geometry to inspect
 : @return True or false
 :)
declare function geo:is-esri($geomIn) {
  if($geomIn instance of map(*)) then
    let $geom := ($geomIn?geometry, $geomIn)[1] 
    return if(exists($geom?('x', 'paths', 'rings'))) 
      then true() else false()
  else false()
};

(:~ 
 : Denotes if a single feature is a GeoJSON geometry
 : @geom Geometry to inspect
 : @return True or false
 :)
declare function geo:is-geo-json($geomIn) {
  if($geomIn instance of map(*)) then 
    let $geom := ($geomIn?geometry, $geomIn)[1]
    return if(exists($geom?coordinates))
      then true() else false()
  else false()
};

(:~ 
 : Denotes if a single feature is a GML geometry
 : @geom Geometry to inspect
 : @return True or false
 :)
declare function geo:is-gml($geom) {
  if(not($geom instance of map(*))) then 
    if($geom/namespace-uri() = ('http://www.opengis.net/gml'))
    then true() else false()
  else false()
};

(:~ 
 : Denotes if a single feature is a KML geometry
 : @geom Geometry to inspect
 : @return True or false
 :)
declare function geo:is-kml($geom) {
  if(not($geom instance of map(*))) then 
    if($geom/namespace-uri() = ('http://www.opengis.net/kml/2.2'))
    then true() else false()
  else false()
};

(:~
 : Converts GeoJSON feature into GML
 : @param $features - features to convert
 : @return Converted features as GML
 :)
declare function geo:as-gml($features) {
  for $feature in $features return
  element gml:Feature {
     attribute typeName {'Feature'},
     let $properties := $feature?properties
     return
      for $key in map:keys($properties) return
      element {$key} {$properties($key)},
     element gml:geometricProperty {
       geo:as-gml-geom($feature?geometry)
     }
  }
};

(:~ 
 : Converts an GeoJSON geometry into a GML xml geometry 
 : @param $feature - Geometry to convert
 : @return GeoJSON geometry
 :)
declare function geo:as-gml-geom($feature) {
  let $type := $feature?type
  return
    if($type = 'Point') then
      element gml:Point {
        element gml:coordinates {
          $feature?coordinates?*
        }
      }
    else if($type = 'MultiPoint') then
      element gml:Point {
        element gml:coordinates {
          $feature?coordinates?* !
            element gml:LineString { 
              element gml:coordinates { .?* }
            }
        }
      }
    else if($type = 'LineString') then
      element gml:LineString {
        element gml:coordniates {
          $feature?coordinates?*
        }
      }
    else if($type = 'MultiLineString') then
      element gml:MultiLineString {
        element gml:coordinates {
          $feature?coordinates?* !
            element gml:LineString { 
              element gml:coordinates { .?* }
            }
        }
      }
    else if($type = 'Polygon') then 
      element gml:Polygon {
        let $coords := $feature?coordinates
          return (
            element gml:outerBoundaryIs { 
              element gml:LinearRing { 
                element gml:coordinates {
                  $coords?1?* ! string-join(., ',') }
                } 
            },
            if(count($coords) = 2) then 
              $coords?*[position() > 1] ! (
                element gml:innerBoudaryIs { element gml:LinearRing { 
                  element gml:coordinate { .?* ! string-join(., ',') }}}
              )
            else ()
          )
      }
    else error($geo:unknownGeometry)
};

(:~
 : Converts KML features to GeoJSON
 : @param $geometry - Feature to convert
 : @return Feature as GeoJSON 
 :)
declare function geo:from-kml($features) {
  if($features[1]/local-name() = 'Placemark') then
    for $feature in $features return
    map:merge((
      for $property in $feature/* return
      if(not($property/local-name() = ('LineString', 'Point', 'LinearRing', 'Polygon'))) then 
         map { $property/local-name(): data($property) }
      else
         map { 'geometry': geo:from-gml-geom($property) }       
    ))
  else ($features)
};

(:~
 : Converts KML geometry to a GeoJSON one
 : @param $geometry - KML geometry to convert
 : @return Geometry as GeoJSON 
 :)
declare function geo:from-kml-geom($geometry) {
  (: KML and GML share the same geometry :)
  geo:from-gml-geom($geometry)
};

(:~
 : Converts GML features to GeoJSON
 : @param $geometry - Feature to convert
 : @return Feature as GeoJSON
 :)
declare function geo:from-gml($features) {
  if(exists($features[1]//gml:geometry)) then 
    for $feature in $features return
    map:merge((
      for $property in $feature/*[local-name() != 'geometricProperty']
      return
        map { $property/local-name(): data($property) },
      map { 'geometry': geo:from-gml-geom($feature//gml:geometry) }
    ))
  else ($features)
};

(:~
 : Converts GML geometry to GeoJSON
 : @param $geometry - Geometry to convert
 : @return Geometry of feature as GML
 :)
declare function geo:from-gml-geom($geometry) {
  let $type := $geometry/local-name() 
  return
  if($type = 'Point') then
   map {
     'type': 'Point',
     'coordinates': array { tokenize($geometry/*:coordinates) ! (tokenize(., ',') ! xs:double(.)) }
   }
  else if($type = 'LineString') then
   map {
     'type': 'LineString',
     'coordinates': array {
       tokenize($geometry/*:coordinates) ! (array { tokenize(., ',') ! xs:double(.) })
     }
   }
  else if($type = 'Polygon') then
   map {
     'type': 'Polygon',
     'coordinates': array {
       ($geometry/(*:outerBoundaryIs,*:innerBoundaryIs)//*:coordinates 
         ! (array { tokenize(.) ! (array { tokenize(., ',') ! xs:double(.) }) }))
     }
   }
  else ()
};

declare function geo:as-esri-geom($feature) {
  if(geo:is-esri($feature)) then $feature
  else geo:as-geo-json-geom($feature) => geo:to-esri-geom()
};

(:~
 : Converts a GeoJson geometry into an ESRI json geometry
 : @param $feature - Geometry to convert
 : @return ESRI Json geometry
 :)
declare function geo:to-esri-geom($feature) {
  let $geom := $feature?geometry 
  return
    if($geom?type = 'Point') then map { 
       'x': $geom?coordinates?1,
       'y': $geom?coordinates?2 
    } else if($geom?type = 'LineString') then map {
      'paths': array { $geom?coordinates }
    } else $geom
};

(:~
 : Converts a GeoJson feature into an ESRI json feature
 : @param $feature - feature to convert
 : @return ESRI Json feature
 :)
declare function geo:as-esri($features) {
  if(geo:is-esri($features[1])) then $features
  else geo:as-geo-json($features) => geo:to-esri()
};

declare function geo:to-esri($features) {
  for $feature in $features return
  if(exists($feature?properties)) then
    map:merge((
      map { 'geometry': geo:to-esri-geom($feature) },
      map { 'attributes': $feature?properties }
    ))
  else ($feature)
};

(: Internal helper function :)
declare %private function geo:edit-features($service, $layer, $features, $endpoint, $options) {
  geo:request($service, web:create-url('/' || $layer?id || '/' || $endpoint, map:merge(($options,
  map {
    'features': json:serialize(array { $features })
  }))), 'POST')
};

(:~
 : Updates the provided features
 : @param $service - Service to update the features in
 : @param $layer - Layer to update the features in
 : @param $features - Features to update
 : @param $options - Request options as a map(*). See ESRI's REST SDK
 : documentation for details
 : @return Result of the request as a json response object
 :)
declare function geo:update-features($service, $layer, $features, $options) {
  geo:edit-features($service, $layer, $features, 'updateFeatures', $options)
};


(:~ 
 : Applies the map of adds, updates and deletes to the service 
 : @param $service - Service to update the features in
 : @param $layer - Layer to update the features in
 : @param $edits - edits as a map with any of: adds, updates and deletes as sequences of features
 : @returns See the ArcGIS REST Api specification on 'applyEdits' for details on the return format.
 :)
declare function geo:apply-edits($service, $layer, $edits) {
  geo:request($service, web:create-url('/' || $layer?id || '/applyEdits', map:merge((
    map {
      'updates': json:serialize(array { $edits?updates }),
      'deletes': json:serialize(array { $edits?deletes?OBJECTID }),
      'adds': json:serialize(array { $edits?adds })
    }))), 'POST'
  )
};

(:~
 : Updates the provided features
 : @param $service - Service to update the features in
 : @param $layer - Layer to update the features in
 : @param $features - Features to update
 : @return Result of the request as a json response object
 :)
declare function geo:update-features($service, $layer, $features) {
  geo:edit-features($service, $layer, $features, 'updateFeatures', ())
};

(:~
 : Deletes the provided features
 : @param $service - Service to delete the features from. 
 : @param $layer - Layer to delete the features from. 
 : @param $features - Features to delete 
 : @param $options - Request options as a map(*). See ESRI's REST SDK
 : documentation for details
 : @return Result of the request as a json response object
 :)
declare function geo:delete-features($service, $layer, $features, $options) {
  geo:edit-features($service, $layer, $features, 'deleteFeatures', $options)
};

(:~
 : Deletes the provided features
 : @param $service - Service to delete the features from
 : @param $layer - Layer to delete the features from 
 : @param $features - Features to delete 
 : documentation for details
 : @return Result of the request as a json response object
 :)
declare function geo:delete-features($service, $layer, $features) {
  geo:edit-features($service, $layer, $features, 'deleteFeatures', ())
};

(:~
 : Create the provided features
 : @param $service - Service to addthe features in
 : @param $layer - Layer to add the features in
 : @param $features - Features to add
 : @param $options - Request options as a map(*). See ESRI's REST SDK
 : @return Result of the request as a json response object
 :)
declare function geo:add-features($service, $layer, $features, $options) {
  geo:edit-features($service, $layer, $features, 'addFeatures', $options)
};

(:~
 : Create the provided features
 : @param $service - Service to addthe features in
 : @param $layer - Layer to add the features in
 : @param $features - Features to add
 : @return Result of the request as a json response object
 :)
declare function geo:add-features($service, $layer, $features) {
  geo:edit-features($service, $layer, $features, 'addFeatures', ())
};

(:~
 : Updates the supplied map with the specified map of values
 : @param $item - Item up set the value on
 : @values $values - Values to set
 : @return The augmented item
 :)
declare function geo:set($item, $values) {
  map:merge((
    $item,
    map {
      'attributes': map:merge((
        $item?attributes,
        $values
      ))
    }
  ))
};

(:~
 : Geocodes an address using the provided Geocoding service
 : @param $service - Geocoding service to use
 : @param $paramters - Url paramters to send to the service
 : @return Geocoded ESRI json result
 :)
declare function geo:geocode($service, $parameters as map(*)) {
  geo:request($service, web:create-url('/findAddressCandidates', $parameters))?candidates?*
};

(:~
 : Reverse Geocodes an ESRI json geometry using the provided Geocoding service
 : @param $service - Geocoding service to use
 : @param $paramters - Url paramters to send to the service
 : @return Geocoded result
 :)
declare function geo:reverse-geocode($service, $geometry as map(*)) {
  let $url := web:create-url('/reverseGeocode', trace(map { 'location': json:serialize($geometry) })) 
  return
    geo:request($service, $url)
};

declare function geo:push-to-service($destination, $name, $index, $contents) {
    let $url := trace($destination/@href || '/' || trace($name) || '/replica-' || $index || '.xml')
    let $req := element http:request {
      $destination/@*[name() != 'href'],
      attribute href {$url},
      element http:body {
        attribute media-type { 'application/xml' },
        <features>{($contents)}</features>
      }
    }
    return trace(http:send-request($req)[2], ' ' || $url)
};


