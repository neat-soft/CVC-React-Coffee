$p = require('./promise')
_ = require('lodash')

module.exports = (options) ->
  path = require('path')
  glob = require('glob')
  basePaths = _.flatten([options.root])

  mincer = require('mincer')
  mincer.logger.use(console) if options.debug is true
  environment = new mincer.Environment()
  (_.flatten _.map basePaths, (basePath) ->
    [ $p.wrap(glob(path.join(basePath, "**/stylesheets"), $p.ecb()))
      $p.wrap(glob(path.join(basePath, "**/javascripts"), $p.ecb()))
      $p.wrap(glob(path.join(basePath, "**/css"), $p.ecb()))
      $p.wrap(glob(path.join(basePath, "**/js"), $p.ecb()))
      $p.wrap(glob(path.join(basePath, "**/images"), $p.ecb()))
      $p.wrap(glob(path.join(basePath, "**/fonts"), $p.ecb()))
    ]
  ).then (files...) ->
    files = _.flatten _.reject(files, (p) -> p.length == 0)
    _.each files, (p) -> environment.appendPath(p)

    self = {
      createServerModule: -> mincer.createServer(environment)
      findAsset: (file) -> environment.findAsset(file)
      registerHelper: (name, helper) -> environment.registerHelper(name, helper)
      assetPath: (file) ->
        asset = self.findAsset(file)
        throw new Error("Unknown asset [#{file}]") unless asset?
        path = "#{options.assetPrefix || "/assets/"}#{asset.digestPath}"
        path = options?.cdnPrefix + path if options?.cdnPrefix?
        path += "?version=#{options.assetVersion}" if options?.assetVersion?
        path
    }
    environment.registerHelper('assetPath', (args...) -> self.assetPath(args...))
    return self

