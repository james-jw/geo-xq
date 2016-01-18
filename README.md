# geo-xq
XQuery 3.1 SDK for accessing various GIS map and feature services and data types.

This service currently supports and interops between the following geometry types:
- GeoJSON
- ESRI Json Format
- GML (OGC xml standard)

The following Feature and Map services are currently supported
- ESRI Feature/Map service
- ESRI Geocoding service

## Working with Features and Geometries
The geo-xq module provides several methods for converting between different geographic representations. In particular GeoJSON, GML and ESRI's json format.

### to-geo-json
Converts a feature into a GeoJSON format. For example:

```xquery
let $geoJson := local:to-geo-json($geomIn)
return
  $geoJson
```

### to-geo-json-geom
Converts a GML or ESRI geometry into a GeoJSON format. For example:
```xquery
let $geoJson := local:to-geo-json-geom($geomIn)
return
  $geoJson
```

### to-gml
Converts a feature into the GML format.

### to-gml-geom
Converts a geometry into a GML format.

### to-esri
Converts a feature into ESRI's json format

### to-esri-geom
Converts a geometry into ESRI's json format

## Working with Services
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
