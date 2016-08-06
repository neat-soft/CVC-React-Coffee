_ = require("lodash")
moment = require('moment')
{EventEmitter} = require('events')

exports.DqsTableDefinition = -> (tableName) -> """
  CREATE TABLE #{tableName}(
    queue VARCHAR(100) NOT NULL,
    ref VARCHAR(50) NOT NULL,
    contentType VARCHAR(20) NOT NULL,
    message TEXT NOT NULL,
    processAfter TIMESTAMP NOT NULL,
    lockedBy VARCHAR(50) NULL,
    attempted INT NOT NULL DEFAULT 0,
    createTime TIMESTAMP NOT NULL,
    updateTime TIMESTAMP NOT NULL,
    PRIMARY KEY(queue, ref),
    KEY(queue, processAfter),
    KEY(queue, attempted)
  )
"""

exports.DqsDataSource = ($options, $p, mysqlTableFactory, mysqlConnectionPool, mysqlConnectionPoolFactory, dqsTableDefinition) ->
  $p.when(
    if $options?.connectionPool
      mysqlConnectionPoolFactory($options?.connectionPool)
    else
      mysqlConnectionPool
  ).then (mysqlConnectionPool) ->
    mysqlTableFactory(mysqlConnectionPool, $options?.tableName || "dqs", dqsTableDefinition)

exports.DqsProvider = ($u, $p, $options, $logger, ql, dqsDataSource, itemBufferFactory) ->
  $options?={}
  $options = _.defaults $options, {
    waitTime: 500
  }
  converters = {
    json: {
      check: (message) -> _.isObject(message)
      serialize: (message) -> JSON.stringify(message)
      deserialize: (message) -> JSON.parse(message)
    }
    integer: {
      check: (message) -> _.isNumber(message) and message % 1 == 0
      serialize: (message) -> message.toString()
      deserialize: (message) -> parseInt(message)
    }
    float: {
      check: (message) -> _.isNumber(message) and message % 1 != 0
      serialize: (message) -> message.toString()
      deserialize: (message) -> parseFloat(message)
    }
    string: {
      check: (message) -> true
      serialize: (message) -> message.toString()
      deserialize: (message) -> message.toString()
    }
  }
  checksum = (message) ->
    return $u.md5(message) if _.isString(message)
  parseMessage = (message, contentType) ->
    return unless message?
    return message unless contentType?
    throw new Error("Unknown contentType [#{contentType}]") unless converters[contentType]?
    return converters[contentType].deserialize(message)
  convertMessage = (message) ->
    contentType = null
    _.each converters, (def, type) ->
      if !contentType and def.check(message)
        contentType = type
        message = def.serialize(message)
    [contentType, message]
  return self = {
    enqueue: (queue, message, delay) ->
      [contentType, message] = convertMessage(message)
      ref = checksum(message)
      item = {
        queue: queue
        ref: ref
        message: message
        contentType: contentType
        processAfter: (if delay? then ql.NOW(delay, "second") else ql.NOW())
      }
      dqsDataSource.insert(item).then
        success: -> item.ref
        error: (err) ->
          return $p.error(err) unless err.code == "ER_DUP_ENTRY"
          dqsDataSource.update({queue: queue, ref: ref}, {processAfter: item.processAfter, attempted: 0}).then ->
            ref

    isInQueue: (queue, message) ->
      [contentType, message] = convertMessage(message)
      self.get(queue, checksum(message)).then (results) ->
        results?[0]?

    get: (queue, ref) ->
      dqsDataSource.query(queue: queue, ref: ref).then (results) ->
        parseMessage(results?[0]?.message, results?[0]?.contentType)

    dequeue: (queue, retryIn, limit = 1) ->
      throw new Error("limit must be numeric when dequeing from #{queue}") unless _.isNumber(limit)
      throw new Error("retryIn is required") unless retryIn?
      limit = Math.min(limit, 1000)
      lockId = $u.randomString(50)
      increment = (dbFieldName, paramName) ->
        {fragment: "#{dbFieldName} + :#{paramName}", value: 1}
      dqsDataSource.update({queue: queue, processAfter: ql.LTE(ql.NOW()), attempted: ql.LTE(4), _limit: limit}, {processAfter: ql.NOW(retryIn, 'second'), lockedBy: lockId, attempted: increment}).then (results) ->
        return {} unless results.affectedRows > 0
        dqsDataSource.query(lockedBy:lockId).then (results) ->
          return _.object _.map(results, (item) -> [item.ref, parseMessage(item.message, item.contentType)])

    getAttemptCount: (queue, ref) ->
      dqsDataSource.query(queue: queue, ref: ref).then (results) ->
        results[0]?.attempted

    getDelay: (queue, ref) ->
      dqsDataSource.query("SELECT processAfter, TIMESTAMPDIFF(second, now(), processAfter) delay FROM #{dqsDataSource.getTableName()} WHERE queue=:queue and ref=:ref", queue: queue, ref: ref).then (result) ->
        return null unless result[0]?
        return 0 unless result[0].delay > 0
        return result[0].delay

    delay: (queue, seconds, refs...) ->
      dqsDataSource.update({queue: queue, ref: refs}, {processAfter: ql.NOW(seconds, "second")}).then (results) ->
        results?.affectedRows > 0

    processAfter: (queue, processAfter, refs...) ->
      dqsDataSource.update({queue: queue, ref: refs}, {processAfter: processAfter}).then (results) ->
        results?.affectedRows > 0

    getTime: ->
      dqsDataSource.first("SELECT NOW() time").then (row) -> row.time

    getQueueSize: (queue) ->
      dqsDataSource.query("SELECT COUNT(*) c FROM #{dqsDataSource.getTableName()} WHERE queue=:queue", {queue:queue}).then (results) ->
        results[0]?.c || 0

    remove: (queue, refs...) ->
      dqsDataSource.delete(queue: queue, ref: refs).then ->

    removeItems: (queue, items...) ->
      self.remove queue, _.map(items, checksum)...
    monitor: (queue, retryIn, processor) ->
      self.monitorBatch(queue, retryIn, 1, processor)
    monitorBatch: (queue, retryIn, dequeueBatchSize, processBatchSize, processor) ->
      [processBatchSize, processor] = [dequeueBatchSize, processBatchSize] unless processor?
      waitPromise = $p.create()
      keepGoing = true
      buffer = itemBufferFactory(dequeueBatchSize)
      removeBuffer = itemBufferFactory(Number.MAX_VALUE) #buffer can be of any size, since there is no practical way to fill the buffer

      processing = false
      dequeueing = false
      removing = false
      buffer.on 'notEmpty', ->
        return if processing
        processing = true
        doIt = ->
          batch = buffer.get(processBatchSize)
          refs = _.map batch, (item) -> item[0]
          messages = _.map batch, (item) -> item[1]
          ($p.when(processor(messages...)).then
            success: ->
              removeBuffer.put refs...
            error: (err) ->
              err = $u.inspect(err.errors, 2) if err.errors?.length > 0
              $logger.error "[#{queue}] Error [#{err?.message || err.toString()}] while processing", messages
            failure: (err) ->
              $logger.error "[#{queue}] Failure [#{err?.message || err.toString()}] while processing", messages
          ).then ->
            refs = []
            return doIt() unless buffer.size() == 0
            processing = false
            buffer.emitEvents()
          null
        doIt()
      buffer.on 'notHalfFull', ->
        return if dequeueing or !keepGoing
        dequeueing = true
        self.dequeue(queue, retryIn, dequeueBatchSize).then
          error: ->
            dequeueing = false
            setTimeout((-> buffer.emitEvents()), $options.waitTime)
          failure: ->
            dequeueing = false
            setTimeout((-> buffer.emitEvents()), $options.waitTime)
          success: (results) ->
            results = _.pairs(results)
            dequeueing = false
            if results.length == 0
              setTimeout((-> buffer.emitEvents()), $options.waitTime)
            else
              buffer.put(results...)
      buffer.on 'empty', ->
        return waitPromise.resolve() if !dequeueing and !processing and !keepGoing and !waitPromise.isResolved() and removeBuffer.size() == 0 and !removing
        removeBuffer.emitEvents() if removeBuffer.size() > 0

      removeBuffer.on 'notEmpty', ->
        return if removing
        removing = true
        (self.remove(queue, removeBuffer.get(removeBuffer.size())).then
          error: ->
          failure: ->
          success: ->
        ).then ->
          removing = false
          buffer.emitEvents()

      removeBuffer.on 'empty', -> buffer.emitEvents()

      buffer.emitEvents()
      return {
        stop: -> keepGoing = false
        wait: -> waitPromise.then ->
        bufferSize: -> buffer.size()
      }
  }

exports.DqsBatchJobProvider = ($p, $u, $logger, dqsProvider) ->
  definitions = {}
  queue = "JOB_QUEUE"
  jobMonitor = null
  timeoutHandle = null
  return self = {
    _definitions: definitions
    _enqueueMissingJobs: ->
      (_.map definitions, (def, jobKey) ->
        dqsProvider.getDelay(queue, def.ref).then (delay) ->
          return if delay?
          self.scheduleJob(jobKey, def.frequencyDef)
      ).then ->
        return if timeoutHandle?
        timeoutHandle = setTimeout((->
          timeoutHandle = null
          self._enqueueMissingJobs()
        ), 1000)

    _calcNextRunOn: (time, frequencyDef) ->
      time = moment(time).add(frequencyDef.frequency, "minutes")
      time = time.hour(frequencyDef.hour) if frequencyDef.hour?
      time = time.minute(frequencyDef.minute) if frequencyDef.minute?
      time.toDate()

    scheduleJob: (jobKey, frequencyDef) ->
      (dqsProvider.enqueue(queue, jobKey, frequencyDef.frequency * 60).then (ref) ->
        return unless frequencyDef.hour? or frequencyDef.minute?
        dqsProvider.getTime().then (currentTime) ->
          nextRunOn = self._calcNextRunOn(currentTime, frequencyDef)
          dqsProvider.processAfter(queue, nextRunOn, ref)
      ).then ->
        dqsProvider.getDelay(queue, $u.md5(jobKey)).then (delay) ->
          $logger.debug "SCHEDULED [#{jobKey}] WITH DELAY", delay

    executeJob: (jobKey) ->
      def = definitions[jobKey]
      return $p.resolved() unless def?
      rescheduleFrequency = def.rescheduleFrequency || 60*1000
      rescheduleRef = null
      reschedule = ->
        rescheduleRef = null
        self.scheduleJob(jobKey, def.frequencyDef).then ->
          return if rescheduleFrequency == 0
          rescheduleRef = setTimeout reschedule, rescheduleFrequency
      finish = ->
        clearTimeout(rescheduleRef) if rescheduleRef?
        rescheduleFrequency = 0
      reschedule().then ->
        $logger.time "info", "EXECUTING JOB [#{jobKey}]", ->
          $p.when(def.block.apply(null)).then
            success: (args...) -> finish(); $p.resolved(args...)
            error: (args...) -> finish(); $p.error(args...)
            failure: (args...) -> finish(); $p.failure(args...)

    start: ->
      return if jobMonitor?
      self._enqueueMissingJobs()
      jobMonitor = dqsProvider.monitor queue, 60, (jobKey) ->
        $logger.debug "BEGIN PROCESSING", jobKey
        self.executeJob(jobKey)

    stop: ->
      clearTimeout(timeoutHandle) if timeoutHandle?
      return $p.resolved() unless jobMonitor?
      jobMonitor.stop()
      jobMonitor.wait()

    register: (jobKey, frequencyDef, block) ->
      definitions[jobKey] = {
        ref: $u.md5(jobKey)
        frequencyDef: frequencyDef
        block: block
      }
      self._enqueueMissingJobs()
  }