promise = require('./promise')
$u = require('./utilities')
module.exports = (maxInvocations, maxQueueSize, defaultTimeout) ->
  invocations= 0
  invoke = null
  queue = []
  processQueueScheduled = false

  scheduleProcessQueue = ->
    unless processQueueScheduled or queue.length == 0
      processQueueScheduled = true
      setImmediate processQueue

  processQueue = ->
    processQueueScheduled = false
    while invocations<maxInvocations and queue.length>0
      invoke queue.shift()

  invoke = (timeout, block) ->
    [timeout, block] = [null, timeout] unless block?
    timeout?=defaultTimeout
    unless block.promise?
      block = $u.trace("throttle", block)
      block = $u.bindToActiveDomain(block)
      block.timeout = timeout
      block.promise = promise.create()
    finish = ->
      invocations--
      scheduleProcessQueue()
    if invocations<maxInvocations
      invocations++
      if block.timeout?
        blockTimeout = setTimeout((->
          finish()
          block.promise.error(new Error("TIMEOUT WHILE EXECUTING THROTTLED BLOCK"))
        ), block.timeout)
      (promise.when(block()).then
        success: (results...) ->
          finish()
          block.promise.resolve(results...)
        error: (err...) ->
          finish()
          block.promise.error(err...)
        failure: (err...) ->
          finish()
          block.promise.failure(err...)
      ).then ->
        clearTimeout(blockTimeout) if blockTimeout?
    else
      if queue.length >= maxQueueSize
        return promise.error(new Error(module.exports.MAX_QUEUE_SIZE_REACHED))
      queue.push block
      scheduleProcessQueue()
    return block.promise

  invoke.getBacklog = -> queue.length
  invoke.getConcurrency = -> invocations
  return invoke

module.exports.MAX_QUEUE_SIZE_REACHED = "MAX_QUEUE_SIZE_REACHED"

module.exports.isMaxQueueSizeReached = (err) -> err.message == module.exports.MAX_QUEUE_SIZE_REACHED

module.exports.fifo = (chunkSize, maxBacklog, block) ->
  queue = []
  pending = 0
  processing = false
  waitPromise = null
  process = ->
    return if processing == true
    chunks = $u.chunkArray(queue, chunkSize)
    pending = queue.length
    queue = []
    processChunk = ->
      processing = true
      chunk = chunks.shift()
      block(chunk).then ->
        pending-=chunk.length
        return processChunk() if chunks.length > 0
        processing = false
        waitPromise.resolve() if waitPromise?
        waitPromise = null
        process() if queue.length > 0
      null
    processChunk()

  return self = {
    push: (items) ->
      if self.backlog() >= maxBacklog
        return promise.create (p) ->
          self.waitUntilDone().then ->
            self.push(items).then -> p.resolve()
      queue = queue.concat(items)
      process()
      promise.resolved()
    backlog: -> queue.length + pending
    waitUntilDone: ->
      waitPromise ?= promise.create()
  }
