winston = require('winston')
_ = require("lodash")
scope = require("./scope")

exports.LoggerFactory = ($p, $u, $options) ->
  levels=
    debug: 0
    info: 1
    warn: 2
    error: 3
    fatal: 4
  colors =
    debug: 'grey'
    info: 'green'
    warn: 'yellow'
    error: 'red'
    fatal: 'red'

  transports = []
  if $options?.papertrail?
    require('winston-papertrail').Papertrail
    os = require('os')
    transports.push new winston.transports.Papertrail(
      host: $options.papertrail.host
      port: $options.papertrail.port
      hostname: $options.papertrail.hostname || os.hostname()
      program: $options.papertrail.appName
      inlineMeta: true
      level: $options.papertrail.level || 'info'
    )
  consoleLevel = if transports.length > 0 then 'error' else 'debug'
  consoleOpts = $u.merge($options?.console || {}, {colorize:true, level: consoleLevel})
  transports.push(new winston.transports.Console(consoleOpts))

  logWrapper=
    baseLogger: new (winston.Logger)(
      levels: levels
      transports: transports
      colors: colors
    )
    log: (level, tags, message, metadata) ->
      minLevel = scope.context?.__loggerMinLevel
      if minLevel? and levels[minLevel]?
        return unless levels[level]>=levels[minLevel]
      tags = _.flatten([scope.context?.__loggerTags || [], tags])
      if tags.length > 0
        tags = _.flatten(tags)
        tagsStr = ""
        tagsStr+= "[#{tag}]" for tag in tags
        message = "#{tagsStr} #{message}"
      args = [message]
      args.push metadata if metadata?
      @baseLogger.log level, args...

  nest = (logger, tag) ->
    return newLogger = {
      _parent: logger
      log: (level, tags, message, metadata) ->
        @_parent.log(level, [tag, tags], message, metadata)
        newLogger
      debug: (message, metadata) -> newLogger.log('debug', [], message, metadata)
      info: (message, metadata) -> newLogger.log('info', [], message, metadata)
      warn: (message, metadata) -> newLogger.log('warn', [], message, metadata)
      error: (message, metadata) -> newLogger.log('error', [], message, metadata)
      fatal: (message, metadata) -> newLogger.log('fatal', [], message, metadata)
      nest: (tags...) -> nest(newLogger, tags)
      restrictScope: (level) ->
        return newLogger unless scope.active
        scope.context.__loggerMinLevel=level
        newLogger
      tagScope: (tags...) ->
        return newLogger unless scope.active
        scope.context.__loggerTags?=[]
        _.each tags, (t) -> scope.context.__loggerTags.push(t)
        newLogger

      time: (level, description, block) ->
        [description, block] = [description.toString().replace(/function \(\) {\n *|\n *}$/g,''), description] unless block?
        start = process.hrtime()
        finish = ->
          diff = process.hrtime(start)
          timeMs = (diff[0] * 1e9 + diff[1])/1e6
          newLogger.log(level, [], "TIMING #{description} TOOK :#{timeMs}")
        $p.when(block()).then
          success: (results...) -> finish();$p.resolved(results...)
          error: (results...) -> finish();$p.error(results...)
          failure: (results...) -> finish();$p.failure(results...)
    }

  (name) -> nest(logWrapper, name)
