import module namespace geo = "http://expath.org/ns/geo";
declare namespace gml='http://www.opengis.net/gml';
import module namespace promise = 'org.jw.basex.async.xq-promise'; 

(: Internal helper methods :)
declare %private function local:get($service, $paths) {
  $paths ! local:request($service, '/' || .)
};

(: Internal helper method :)
declare function local:process-response($res) {
  try { $res[2] => parse-json() }
  catch * { $res[2] }
};

(:~ 
 : Makes a request, but does not process the response 
 : @param $service - Service to make the request against 
 : @param $url - Full or relative url of the endpoint to request
 : @param $method - HTTP verb to utilize (GET, PUT, POST, DELETE, HEAD)
 :)
declare function local:primitive-request($service, $url, $method) {
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
declare function local:request($service, $url, $method) {
  local:primitive-request($service, $url, $method)
     => local:process-response()
};

(:~ 
 : Makes a GET request, processing the response as JSON 
 : @param $service - Service to make the request against 
 : @param $url - Full or relative url of the endpoint to request
 :)
declare function local:request($service, $url) {
  local:request($service, $url, 'GET')
};

(:~
 : Creates a request template for connecting to a passord protected service
 : @param $login - Username to use
 : @param $password - Password to use
 :)
declare function local:request-template($login, $password) {
  if($login) then
    <http:send-request username="{$login}" password="{$password}" send-authorization="true" />
  else 
    <http:send-request />
};

(:~ Connect to a non secured service :)
declare function local:request-template() {
  local:request-template((), ())
};

(:~
 : Connects to the specified service url with the provided 
 : request template object
 :)
declare function local:connect($req, $url as xs:string) {
  map:merge((local:request(map { '_request': $req }, $url), map { 
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
declare function local:layers($service) {
  $service?layers?*
};

(:~
 : Retrieves the layer details for the provided layers on the
 : specified service
 : @param $service - Service to request the layers from
 : @param $layers - Layers to request
 : @return Request layer details
 :)
declare function local:get-layers($service, $layers) {
  local:get($service, $layers?id)
};

(:~
 : Retrieves the layer details for the provided layers on the
 : specified service
 : @param $service - Service to request the layers from
 : @param $folders - folders to request
 : @return Request folder details
 :)
declare function local:get-folders($server, $folders) {
  local:get($server, $folders)
};

(:~
 : Returns service details for the provided server
 : @param $server - Servier to retrieve the services from
 : @param $services - List of services to retrieve
 : @return Service details for the requested services
 :)
declare function local:get-services($server, $services) {
  for $path in ($services ! (.?name || '/' || .?type))
  let $service := local:get($server, $path)
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
declare function local:query-layer($service, $layer, $query) {
  let $url := '/' || $layer?id || '/query'
  return try { local:request($service, web:create-url($url, $query)) } 
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
declare function local:query-layer-xml($service, $layer, $queryIn, $index) {
  let $url := '/' || $layer?id || '/query'
  let $where := trace($queryIn?where)
  let $query := 
   if($index >= 0) then map:put($queryIn, 'where', trace('ObjectID > ' || format-number($index, '#')))
   else $queryIn
  let $res := (local:primitive-request($service, web:create-url($url, $query), 'GET'))
  let $headers := trace($res[1]/@status)
  return  
    let $features :=
      for $feature in ($res[2] => json:parse())/json/features/_
      return
        <feature>
           {$feature/attributes}
           {local:to-geo-json-geom(json:serialize(<json type="object">{$feature/geometry/*}</json>) => parse-json()) => local:to-gml-geom()}
        </feature>
     return
        ($features, 
          if($index >= 0 and trace(count($features)) = 1000) then
            let $maxId := trace(max($features/attributes/ObjectID), 'maxid ')
            return 
              local:query-layer-xml($service, $layer, $query, trace($maxId, 'subQuery: '))
          else ()
        )
};

(:~ 
 : Converts an ESRI JSON geometry into a GeoJSON geometry 
 : @param $geom - Geometry to convert
 : @return GeoJSON geometry
 :)
declare function local:to-geo-json-geom($geometry) {
  let $temp-geom := ($geometry?geometry, $geometry)[1]
  let $geom := local:from-gml-geom($temp-geom)
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
};

(:~ 
 : Converts an ESRI JSON feature into a GeoJSON feature 
 : @param $feature - feature to convert
 : @return GeoJSON geometry
 :)
declare function local:to-geo-json($features) {
  let $features := local:from-gml($features)
  return
    for $feature in $features return
    map:merge((
      map { 'geometry': local:to-geo-json-geom($feature) },
      map { 'properties': $feature?attributes }
    ))
};

(:~
 : Converts GeoJSON feature into GML
 : @param $features - features to convert
 : @return Converted features as GML
 :)
declare function local:to-gml($features) {
  for $feature in $features return
  element gml:Feature {
     attribute typeName {'Feature'},
     let $properties := feature?properties
     return
      for $key in map:keys($properties) return
      element {$key} {$properties($key)},
     element gml:geometricProperty {
       local:to-gml-geom($feature?geometry)
     }
  }
};

(:~ 
 : Converts an GeoJSON geometry into a GML xml geometry 
 : @param $feature - Geometry to convert
 : @return GeoJSON geometry
 :)
declare function local:to-gml-geom($feature) {
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
    else error("Invalid geometry")
};

(:~
 : Converts GML feature to GeoJSON
 : @param $geometry - Feature to convert
 : @return Feature as GML
 :)
declare function local:from-gml($features) {
  if(exists(features//gml:geometry) then 
    for $feature in $features return
    map:merge((
      for $property in $feature/*[local-name() != 'geometricProperty']
      return
        map { $property/name(): data($property) },
      map { 'geometry': local:from-gml-geom($feature//gml:geometry) }
    ))
  else ($features)
};

(:~
 : Converts GML geometry to GeoJSON
 : @param $geometry - Geometry to convert
 : @return Geometry of feature as GML
 :)
declare function local:from-gml-geom($geometry) {
  let $type := $geometry/local-name() 
  if($type = 'Point') then
   map {
     'type': 'Point',
     'coordinates': array { tokenize($geometry/gml:coordinates) ! (tokenize(., ',') ! xs:double(.)) }
   }
  else ($type = 'LineString') then
   map {
     'type': 'LineString',
     'coordinates': array {
       tokenize($geometry/gml:coordinates) ! (array { tokenize(., ',') ! xs:double(.)) }
     }
   }
  else ($type = 'Polygon') then
   map {
     'type': 'Polygon',
     'coordinates': array {
       ($geometry/(gml:outerBoundaryIs,gml:innerBoundaryIs)/gml:coordinates !  tokenize(.)) 
          ! (array { tokenize(., ',') ! xs:double(.)) }
     }
  else ()
};

(:~
 : Converts a GeoJson geometry into an ESRI json geometry
 : @param $feature - Geometry to convert
 : @return ESRI Json geometry
 :)
declare function local:to-esri-geom($feature) {
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
declare function local:to-esri($features) {
  for $feature in $features return
  if(exists($feature?properties)) then
    map:merge((
      map { 'geometry': local:to-esri-geom($feature) },
      map { 'attributes': $feature?properties }
    ))
  else ($feature)
};

(: Internal helper function :)
declare %private function local:edit-features($service, $layer, $features, $endpoint, $options) {
  local:request($service, web:create-url('/' || $layer?id || '/' || $endpoint, map:merge(($options,
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
declare function local:update-features($service, $layer, $features, $options) {
  local:edit-features($service, $layer, $features, 'updateFeatures', $options)
};

(:~
 : Updates the provided features
 : @param $service - Service to update the features in
 : @param $layer - Layer to update the features in
 : @param $features - Features to update
 : @return Result of the request as a json response object
 :)
declare function local:update-features($service, $layer, $features) {
  local:edit-features($service, $layer, $features, 'updateFeatures', ())
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
declare function local:delete-features($service, $layer, $features, $options) {
  local:edit-features($service, $layer, $features, 'deleteFeatures', $options)
};

(:~
 : Deletes the provided features
 : @param $service - Service to delete the features from
 : @param $layer - Layer to delete the features from 
 : @param $features - Features to delete 
 : documentation for details
 : @return Result of the request as a json response object
 :)
declare function local:delete-features($service, $layer, $features) {
  local:edit-features($service, $layer, $features, 'deleteFeatures', ())
};

(:~
 : Create the provided features
 : @param $service - Service to addthe features in
 : @param $layer - Layer to add the features in
 : @param $features - Features to add
 : @param $options - Request options as a map(*). See ESRI's REST SDK
 : @return Result of the request as a json response object
 :)
declare function local:add-features($service, $layer, $features, $options) {
  local:edit-features($service, $layer, $features, 'addFeatures', $options)
};

(:~
 : Create the provided features
 : @param $service - Service to addthe features in
 : @param $layer - Layer to add the features in
 : @param $features - Features to add
 : @return Result of the request as a json response object
 :)
declare function local:add-features($service, $layer, $features) {
  local:edit-features($service, $layer, $features, 'addFeatures', ())
};

(:~
 : Updates the supplied map with the specified map of values
 : @param $item - Item up set the value on
 : @values $values - Values to set
 : @return The augmented item
 :)
declare function local:set($item, $values) {
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
declare function local:geocode($service, $parameters as map(*)) {
  local:request($service, web:create-url('/findAddressCandidates', $parameters))?candidates?*
};

(:~
 : Reverse Geocodes an ESRI json geometry using the provided Geocoding service
 : @param $service - Geocoding service to use
 : @param $paramters - Url paramters to send to the service
 : @return Geocoded result
 :)
declare function local:reverse-geocode($service, $geometry as map(*)) {
  let $url := web:create-url('/reverseGeocode', trace(map { 'location': json:serialize($geometry) })) 
  return
    local:request($service, $url)
};

declare function local:push-to-service($destination, $name, $index, $contents) {
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

(:~
 : Replicates the provided layers to a BaseX XML database
 : @param $service - Service to replicate
 : @param $layers - Layers to replicate from the service
 : @param $destination - Url of the BaseX service to replicate too.
 : @return Status of the replication (Failed/Complete)
 :)
declare function local:replicate($service, $layers, $destination) {
  for $layer in $layers
    let $count := local:query-layer($service, $layer, map {
      'returnCountOnly': true(),
      'where': 'ObjectID > 0'
    })?count div 1000
    let $promises := 
       (for $i in (0 to 10) 
        return
         promise:defer(local:query-layer-xml(?, ?, ?, ()), ($service, $layer, map { 
             "outFields": "*",
             "where": "ObjectID >= " || format-number($i * 1000, '#') || " and ObjectID <= " || format-number(($i * 1000) + 1000, '#')
           }, ())) 
          => promise:done(local:push-to-service($destination, $layer?id || ($layer?name => replace(' ', '')), $i, ?))
       )
     return
      $promises ! .()
};
