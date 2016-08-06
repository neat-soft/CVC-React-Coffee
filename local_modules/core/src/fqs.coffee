_ = require('lodash')

exports.FqsClient = ($p, $u, $logger, $options) ->
  fermata = require('fermata')
  baseUrl = $options.baseUrl
  baseUrl = baseUrl[$u.randomInt(0,baseUrl.length-1)] if _.isArray(baseUrl)
  client = fermata.json(baseUrl)

  done = {}
  headers = {}
  return self = {
    stop: (monitorRef) ->
      done[monitorRef] = true if done[monitorRef]?
    getQueueSizes: ->
      $p.create (p) ->
        client.queue_sizes.get (err, data) ->
          return p.error(err) if err?
          p.resolve(data)
    getSize: (queue) ->
      $p.create (p) ->
        client[queue].stats.get (err, data) ->
          return p.error(err) if err?
          p.resolve(data.size)
    enqueue: (queue, message, priority, processAfter) ->
      $p.create (p) ->
        client[queue](priority:priority, processAfter: processAfter).put message, (err, data, respHeaders) ->
          return p.error(err) if err?
          p.resolve(data?.reference)
    enqueueMulti: (queue, messages) ->
      $p.create (p) ->
        client[queue]({multi:true}).put messages, (err, data, respHeaders) ->
          return p.error(err) if err?
          p.resolve(data?.reference)
    monitor: (queue, retryIn, maxWaitTime, maxCount, cb) ->
      [maxCount, cb] = [null, maxCount] unless cb?
      monitorRef = $u.randomString(20)
      done[monitorRef] = false
      processItem = (reference, item, refsToDelete) ->
        (cb(item).then
          success: -> refsToDelete.push(reference)
          error: -> #Ignore errors and retry later
          failure: (err) -> $p.failure(err)
        ).then ->

      doIt = ->
        return if done[monitorRef]
        client[queue](retryIn: retryIn, maxWaitTime: maxWaitTime, maxCount: maxCount || 1).get headers, (err, data, respHeaders) ->
          return doIt() if err?.code == 'ECONNRESET'
          return setTimeout(doIt, 500) if err?.code == 'ECONNREFUSED'
          return setTimeout(doIt, 500) if err?.status >= 500
          if err?
            $logger.error "UNKNOWN ERROR FROM [#{baseUrl}]", err if err?
            return setTimeout(doIt, 500)
          return setTimeout(doIt, 250) unless data? and data.length > 0 #Queue is empty
          refsToDelete = []
          (_.map data, (envelope) -> processItem(envelope.reference, envelope.message, refsToDelete)).then ->
            return doIt() unless refsToDelete.length > 0
            client[queue].multi.delete headers, refsToDelete, (err) ->
              doIt()
        null
      doIt()
      monitorRef
  }