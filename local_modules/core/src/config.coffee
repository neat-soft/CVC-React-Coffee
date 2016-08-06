fs = require('fs')
path = require('path')
_ = require('lodash')

exports.parseConfig = (rootFolder) ->
  opts = []
  pushIfExists = (file) ->
    file = path.resolve(rootFolder,file)
    if fs.existsSync(file)
      o = require(file)
      opts.push o
      o
  pushIfExists('config/app.coffee')
  privateOverrides = pushIfExists('config/private/app.coffee')
  if process.env.PARAM1? and process.env.PARAM1!=''
    cson = require('cson')
    envConfig = process.env.PARAM1.replace(/\n/g,'').replace(/(\t+)/g,'\n$1')
    csonConfig = envConfig.replace(/module.*/,'')
    envConfig = cson.parseSync(csonConfig)
    opts.push envConfig

  env = process.env.NODE_ENV || privateOverrides?.nodeEnv
  if env?
    pushIfExists("config/#{env}_app.coffee")
    pushIfExists("config/private/#{env}_app.coffee")
    pushIfExists('config/private/app.coffee')
  opts

exports.S3Config = ($p, $logger, s3Factory, kmsFactory) ->
  s3 = s3Factory($options?.aws)
  kms = kmsFactory($options?.aws)
  opts = _.pick JSON.parse(fs.readFileSync("package.json").toString()), 'name', 'configBucket'
  opts.configBucket = process.env.CONFIG_BUCKET || opts.configBucket
  throw new Error("Name is required for s3config") unless opts.name?
  throw new Error("Bucket is required for s3config") unless opts.configBucket?
  return self = {
    parse: ->
      file = "#{opts.name}/#{process.env.NODE_ENV}.json"
      $logger.info "READING CONFIG FROM s3://#{opts.configBucket}/#{file}"

      (s3.getObject(Bucket: opts.configBucket, Key: file).then (data) ->
        body = data.Body.toString()
        body = new Buffer(body, 'base64')
        kms.decrypt(CiphertextBlob: body).then (results) ->
          JSON.parse(results.Plaintext.toString())
      ).then
        error: (err) -> $p.error("Unable to load configuration from S3 [#{err.message}]", err)
  }
