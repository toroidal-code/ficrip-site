# Ficrip

This project is a web frontend for [ficrip](toroidal-code/ficrip)

It provides feature-complete API integration with the backend gem, allowing everything from
simple downloads to complex processing with custom cover images and choosing the
generated EPUB version.

To be quite honest, this project is basically done. It does everything I could
imagine it doing, and quite well at that.

Technologies used include:
- [Sinatra](https://github.com/sinatra/sinatra) web application framework
- [Puma](https://github.com/puma/puma), a highly concurrent web server
- [Rubinius](https://github.com/rubinius/rubinius), a Ruby runtime which supports native parallel threads
- [Materialize](https://github.com/Dogfalo/materialize), a material-design based css/styling framework
- [Sprockets](https://github.com/rails/sprockets) for asset management
- [Sinatra-asset-pipeline](https://github.com/kalasjocke/sinatra-asset-pipeline) for simplification of integrating Sprockets into Sinatra
- [Heroku](heroku.com) application hosting (it's free!)
- [Cloudflare](cloudflare.com) for asset delivery and CDN/caching of static assets
