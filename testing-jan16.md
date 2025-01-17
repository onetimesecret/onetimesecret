
us.onetimesecret.com
curl -k -X POST -u 'onetimesecret.salary001@passmail.net:3fcb7028d55e0f64e354ffcfd749943c5efb32a6' -d 'secret=SECRET&ttl=3600' https://us.onetimesecret.com/api/v1/share

curl -k -X POST -u 'onetimesecret.salary001@passmail.net:3fcb7028d55e0f64e354ffcfd749943c5efb32a6' -H 'Content-Type: application/json' -d '{"secret":{"secret":"SECRET","ttl":3600}}' 'https://us.onetimesecret.com/api/v2/secret/conceal'

curl -k -X POST -u 'onetimesecret.salary001@passmail.net:3fcb7028d55e0f64e354ffcfd749943c5efb32a6' -d 'secret=SECRET&ttl=3600' https://us.onetimesecret.com/api/v1/share



dev.onetimesecret.com
curl -k -X POST -u 'onetimesecret.elm802@passmail.net:c9b8ae87767f3f267a7a114329d1ee27c6160073' -d 'secret=SECRET&ttl=3600' https://dev.onetimesecret.com/api/v1/share
curl -k -X POST -u 'onetimesecret.elm802@passmail.net:c9b8ae87767f3f267a7a114329d1ee27c6160073' -H 'Content-Type: application/json' -d '{"secret":{"secret":"SECRET","ttl":3600}}' https://dev.onetimesecret.com/api/v1/share
