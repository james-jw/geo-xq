# geo-xq
XQuery 3.1 SDK for accessing various GIS map and feature services and data types.

This service currently supports and interops between the following geometry types:
- GeoJSON
- ESRI Json Format
- GML (OGC xml standard)

The following Feature and Map services are currently supported
- ESRI Feature/Map service
- ESRI Geocoding service

# Working with Features and Geometries
The geo-xq module provides several methods for converting between different geographic representations. In particular GeoJSON, GML and ESRI's json format.

### as-geo-json
Converts a feature into a GeoJSON format. For example:

```xquery
let $geoJson := local:to-geo-json($geomIn)
return
  $geoJson
```

### as-geo-json-geom
Converts a GML, KML or ESRI's JSON geometry format into the GeoJSON format. For example:
```xquery
import module namespace geo = 'https://github.com/james-jw/geo-xq';
declare namespace gml ='http://www.opengis.net/gml';
let $geom :=
  <gml:Point>
    <gml:coordinates>-86.77711799999999 32.608276000000004</gml:coordinates>
  </gml:Point>
let $geoJson := geo:as-geo-json-geom($geom)
return
  $geoJson
```

The above should return:
```json
{
  "type": "Point",
  "coordinates": [ -86.77711799999999, 32.608276000000004 ]
}
```

### as-gml
Converts a feature into the GML format.

### as-gml-geom
Converts a geometry into a GML format.

```xquery
import module namespace geo = 'https://github.com/james-jw/geo-xq';
declare namespace gml ='http://www.opengis.net/gml';
let $geom := map {
  "type": "Point",
  "coordinates": array {( -86.77711799999999, 32.608276000000004 )} 
}
let $gml := geo:as-gml-geom($geom)
return
  $gml
```

### as-esri
Converts a feature into ESRI's json format

### as-esri-geom
Converts a geometry into ESRI's json format

### is-gml
### is-kml
### is-geo-json
### is-esri

The above four methods can be used to deteremine what geometry type an object is or is not.

# Working with Services
This module provides several methods for interacting with services and interoping between geometries and feature representations (GML, GeoJSON, ESRI Json)

### request-template
The first step will be to retrieve a request object for use in future API calls. For example to connect to a non-secured service simply call this method with no arguments:

```xquery
let $req := local:request-template()
```

If a login is required, you can pass in the login/password:

```xquery
let $req := local:request-template('myLogin', 'myPassword')
```

### connect 
Connect takes a request template and a service URL and returns the service detials as a service object.

Here is a simple example illustrating how to connect and query an ESRI feature service:
```xquery
(: Connect to the service :)
let $req := local:request-template()
let $service := local:connect($req, 'http://sampleserver6.arcgisonline.com/arcgis/rest/services/Energy/Infrastructure/FeatureServer')
return
  $service
```

### layers
Returns a set of layer names/ids for use in requesting additional layer information. 

```xquery
... continued from above
(: Request the first layer :)
let $layer-list := local:layers($service)
return
 $layer-list
```

### get-layers
Get layer's simply returns a list of layers from the service further anaylsis

```xquery
... continued from above
let $layer-list := local:layers($service)

(: Request the first layer :)
let $layers := local:get-layers($service, $layer-list[1])
return
 $layers
```

### query-layer
Queries a specified layer with the provided query parameters. For example, with ESRI's feature services a 'where' clause can be provided via the 'where' query paramater.

Here is a full example leveraging the 4 functions we have learned so far:
```xquery
let $service := local:connect($req, 'http://sampleserver6.arcgisonline.com/arcgis/rest/services/Energy/Infrastructure/FeatureServer')
let $layers := local:get-layers($service, local:layers($service)[1])
return
  (: Query the first layer for all objects with ID's between 0 and 100 :)
  local:query-layer($service, $layers, map { 
      'where': 'ObjectID > 0 and ObjectID < 100',
      'outFields': '*'
  })
```

`NOTE: For details on query properties and other REST SDK specifics please consult the ESRI Rest SDK documentation.`

Here is another example that retrieves the number of objects in a layer. 
```xquery
local:query-layer($service, $layer, map {
  'returnCountOnly': true(),
  'where': 'ObjectID > 0'
})?count
```

`Note the 'returnCountOnly' ESRI Rest SDK parameter.`

## Editing features

### updates-features
Updates the provided features

```xquery
update-features($service, $layer, $features as item()*, $options as map()
```

For example, to update a set of features you could do the following:
```xquery
let $service := local:connect($req, 'http://your-service.com/arcgis/rest/services/example-service/FeatureServer')
let $layer := local:get-layers($service, local:layers($service)[1])
let $features := local:query-layer($service, $layer, map {
  'where': 'ObjectID > 0',
  'outFields': '*'
})?features
let $updated-features := $features ! map:merge((., map {
    'field-to-update': 'new-value',
    ...
}))
return
  local:update-features($service, $layer, $updated-features)
```

### delete-features

Used to delete a set of features. Simply pass in the features as a sequence:
```xquery
delete-features($service, $layer, $features as item()*, $options as map()
```

### add-features

Used to create a set of features. 
```xquery
add-features($service, $layer, $features as item()*, $options as map()
```

## Geocoding

### geocode
The geocode method accepts a Geocoding service connection. The paramters required are defined by the ESRI REST SDK. The result will
either be the empty sequence of a set of geocoded candidates. 

```xquery
let $url := 'http://sampleserver1.arcgisonline.com/ArcGIS/rest/services/Locators/ESRI_Geocode_USA/GeocodeServer'
let $geo-service := local:connect($req, $url)
return 
  local:geocode($geo-service, map { 
    'Address': '380 NEW YORK ST', 
    'City': 'REDLANDS', 
    'State': 'CA' 
  }) 
```

### reverse-geocode
Operates similar to geocode but in the opposite direction. Instead of returning a geometry for an address, it will return an address
given a geometry. Alternatively it will return the empty sequence if no candidates exist. For example:

```xquery
let $url := 'http://sampleserver1.arcgisonline.com/ArcGIS/rest/services/Locators/ESRI_Geocode_USA/GeocodeServer'
let $geo-service := local:connect($req, $url)
let $geometry := $feature?location
return
  local:reverse-geocode($geo-service, $geometry) 
```

Other examples
 ```xquery
(: Example connect to service :)
let $req := local:request-template()
let $server := local:connect($req, 'http://sampleserver1.arcgisonline.com/ArcGIS/rest/services')
let $folders := $server => local:get-folders($server?folders?*)
let $s := local:get-services($server, $folders?services?*)[1]
return

  for $s in $s[1] return
  local:replicate($s, $s?layers?5, <http:request method="put" href='http://localhost:8984/rest/' username='admin' password='admin' send-authorization='true' />) 
```
