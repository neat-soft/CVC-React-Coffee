$u = require('./utilities')
throttle = require('./throttle')
retry = require('./retry')
events = require('events')
_ = require('lodash')
moment = require("moment")
fs = require('fs')

exports.AwsServiceWrapperFactory = ($p) ->
  (service) ->
    $p.wrapAll(service, _.keys(service.api.operations))

exports.Aws = ($options) ->
  aws = require('aws-sdk')
  aws.config.update $options || {}
  aws.upcase = (value) -> value.substring(0,1).toUpperCase()+value.substring(1)
  aws.upcaseAttributes = (hash, nested) ->
    nested?=true
    return _.map(hash, (v) -> aws.upcaseAttributes(v, nested)) if _.isArray(hash)
    return hash if _.isDate(hash)
    return hash unless _.isObject(hash)
    result = {}
    _.each hash, (v, k) ->
      uk = aws.upcase(k)
      result[uk]=if nested then aws.upcaseAttributes(v, nested) else v
    result
  aws.lcaseAttributes = (hash) ->
    return _.map(hash, aws.lcaseAttributes) if _.isArray(hash)
    return hash if _.isDate(hash)
    return hash unless _.isObject(hash)
    result = {}
    _.each hash, (v, k) ->
      uk = k.substring(0,1).toLowerCase()+k.substring(1)
      result[uk]=aws.lcaseAttributes(v)
    result
  aws

exports.KinesisSinkFactory = ($p, aws) ->
  (streamName) ->
    kinesis = new aws.Kinesis();
    (data) ->
      data = JSON.stringify(data)
      params = {
        Data: data
        PartitionKey: $u.md5(data)
        StreamName: streamName
      };
      $p.create (p) ->
        kinesis.putRecord params, (err, data) ->
          return p.error(err) if err?
          return p.resolve(data)

exports.KinesisStreamFactory = ($p, aws) ->
  (streamName, shardSequenceNumbers) ->
    kinesis = new aws.Kinesis();
    _monitor = null
    _stop = false
    _pause = false
    _shards = null
    _shardIterators = {}
    return self = {
      listShards: ->
        return _shards if _shards?
        self.refreshShards()

      refreshShards: ->
        _shards = $p.wrap(kinesis.describeStream {StreamName:streamName}, $p.ecb()).then (info) ->
          info.StreamDescription.Shards

      getShardIterator: (shardId, position) ->
        parameters =
          StreamName: streamName
          ShardId: shardId
        if position?
          parameters.ShardIteratorType = 'AFTER_SEQUENCE_NUMBER'
          parameters.StartingSequenceNumber = position
        else
          parameters.ShardIteratorType = 'TRIM_HORIZON'
        $p.wrap(kinesis.getShardIterator parameters, $p.ecb()).then (iterator) -> iterator?.ShardIterator

      monitor: ->
        return _monitor if _monitor?
        _monitor = new events.EventEmitter()
        _stop = false
        _monitor.stop = -> _stop=true
        _monitor.pause = -> _pause=true
        _monitor.resume = -> _pause=false
        _monitor.isPaused = -> _pause
        getIteratorByPosition = (shardId) ->
          self.getShardIterator(shardId, shardSequenceNumbers[shardId])

        iterate = ->
          count = 0
          self.listShards().then (shards) ->
            ids = _.map(shards, (s) -> s.ShardId)
            (_.map ids, (shardId) ->
              _shardIterators[shardId] = getIteratorByPosition(shardId) unless _shardIterators[shardId]?
              $p.when(_shardIterators[shardId]).then (iterator) ->
                $p.wrap(kinesis.getRecords({ShardIterator:iterator}, $p.ecb())).then (results) ->
                  _.each results.Records, (r) -> _monitor.emit 'record', r.Data, shardId, r.SequenceNumber
                  _shardIterators[shardId] = results.NextShardIterator
                  count+=results.Records.length
            ).then ->
              if _stop
                _monitor.emit 'end'
                return
              if _pause
                _monitor.emit 'paused'
                checkPause = ->
                  unless _pause
                    _monitor.emit 'resumed'
                    return iterate()
                  setTimeout(checkPause, 1000)
                return checkPause()

              return iterate() if count > 0
              setTimeout iterate, 2000
          null
        iterate()
        _monitor
    }

exports.DynamoDbTableFactory = ($p, aws)->
  valueToMap = (v) ->
    if _.isString(v)
      {S:v}
    else if _.isBoolean(v)
      {BOOL: v}
    else if _.isNumber(v)
      {N:v.toString()}
    else if _.isDate(v)
      {S:moment(v).toJSON()}
    else if _.isArray(v)
      {SS: v}
    else if _.isObject(v)
      {M:hashToItem(v)}
    else
      throw "Unknown datatype for #{v}"

  hashToItem = (hash) ->
    item = {}
    for own k,v of hash
      item[k] = valueToMap(v) if v? and v!=''
    item

  itemToHash = (item) ->
    return item unless item?
    hash = {}
    for own k,v of item
      if v.M?
        hash[k]=itemToHash(v.M)
      else if v.BOOL?
        hash[k] = v.BOOL
      else
        hash[k] = v.S || parseFloat(v.N)
    hash

  safeOp = (block) ->
    errorHandler = (err) -> err.code == 'ProvisionedThroughputExceededException'
    retry(errorHandler, 5, 100, block)

  wrap = (action, data, result) ->
    [data, result] = [null, data] unless result?
    $p.wrap(result).then
      error: (err...) ->
        err[0].action = action
        err[0].data = data
        $p.error(err...)

  return (db, tableName, opts) ->
    self = {
      putItems: (items) ->
        chunks = $u.chunkArray(items, 25)
        th = throttle(opts?.putItemsConcurrency || 1)
        (_.map chunks, (chunk, i) ->
          th ->
            requestItems = {}
            requestItems[tableName] = _.map chunk, (item) -> {PutRequest: Item: hashToItem(item)}

            batchWriteItems = (requestItems) ->
              params =
                RequestItems: requestItems
              safeOp ->
                wrap("putItems/#{tableName}", db.batchWriteItem(params, $p.ecb())).then (results) ->
                  unprocessed = results.UnprocessedItems?[tableName]?
                  return unless unprocessed? and unprocessed.length > 0
                  $u.pause(2000).then ->
                    batchWriteItems(unprocessed)

            batchWriteItems(requestItems)
        ).then ->

      putItem: (item) ->
        params =
          TableName: tableName
          Item: hashToItem(item)
        safeOp ->
          wrap("putItem/#{tableName}", db.putItem(params, $p.ecb()))

      getItem: (keyMap, opts) ->
        params =
          TableName: tableName
          Key: hashToItem(keyMap)
        params.ConsistentRead = true if opts?.consistentRead
        safeOp ->
          wrap("getItem/#{tableName}", db.getItem(params, $p.ecb())).then (result) ->
            itemToHash(result.Item)

      getItems: (keyMaps) ->
        return $p.resolved([]) if keyMaps.length == 0
        batches = $u.chunkArray(keyMaps, 100)
        (_.map batches, (batch) ->
          params =
            RequestItems: {}
          params.RequestItems[tableName] =
            Keys: _.map batch, hashToItem
          safeOp ->
            wrap("getItems/#{tableName}", db.batchGetItem(params, $p.ecb())).then (result) ->
              result = result?.Responses?[tableName]
              _.map result, itemToHash
        ).then (results...) ->
          _.flatten(results)

      updateItem: (keyMap, item, returnItem) ->
        item = hashToItem(item)
        for own k,v of item
          item[k] =
            Action: (if v? then "PUT" else "DELETE")
            Value: v
        params =
          TableName: tableName
          Key: hashToItem(keyMap)
          AttributeUpdates: item
          ReturnValues: if returnItem == true then 'ALL_NEW' else 'NONE'
        safeOp ->
          wrap("updateItem/#{tableName}", db.updateItem(params, $p.ecb())).then (results) ->
            return itemToHash(results.Attributes) if returnItem
            results

      upsertItem: (keyMap, item) ->
        expression = $u.concatString(_.map(keyMap, (v, k) -> "attribute_not_exists(#{k})"), "AND")
        params =
          TableName: tableName
          Item: hashToItem(item)
          ConditionExpression: expression
        safeOp ->
          wrap("putItem/#{tableName}", db.putItem(params, $p.ecb())).then
            success: -> item
            error: (err) ->
              return $p.error(err) unless err.code == 'ConditionalCheckFailedException'
              updates = _.omit(item, _.keys(keyMap))
              self.updateItem(keyMap, updates, true)

      upsertItems: (items, keys) ->
        th = throttle((opts?.putItemsConcurrency || 1)*5)
        (_.map items, (item) ->
          th ->
            keyMap = _.pick(item, keys)
            self.upsertItem(keyMap, item)
        ).then (items...) -> items

      deleteItem: (keyMap) ->
        params =
          TableName: tableName
          Key: hashToItem(keyMap)
        safeOp ->
          wrap("deleteItem/#{tableName}", db.deleteItem(params, $p.ecb()))

      query: (opts, keyOpValues...) ->
        indexName = opts
        {indexName, lastEvaluatedKey} = opts if _.isObject(opts)
        keyConditions = {}
        for i in [0..keyOpValues.length / 3-1]
          set = keyOpValues[i*3..i*3+2]
          keyConditions[set[0]] =
            ComparisonOperator: set[1].toUpperCase()
            AttributeValueList: [valueToMap(set[2])]
        params =
          TableName: tableName
          IndexName: indexName
          KeyConditions: keyConditions
        params.ExclusiveStartKey = lastEvaluatedKey if lastEvaluatedKey?
        (safeOp ->
          wrap("query/#{tableName}/#{indexName}", db.query(params, $p.ecb()))
        ).then (results) ->
          results.Items = _.map(results.Items, itemToHash)
          results

      scan: (opts, scanFilter...) ->
        unless _.isObject(opts)
          scanFilter.shift(opts)
          opts = {}
        opts = aws.upcaseAttributes(opts, false)
        keyConditions = {}
        for sf in scanFilter
          keyConditions[sf[0]] =
            ComparisonOperator: sf[1].toUpperCase()
          keyConditions[sf[0]].AttributeValueList = [valueToMap(sf[2])] if sf[2]?
        params = _.merge opts,
          TableName: tableName
          ScanFilter: keyConditions
        (safeOp ->
          wrap("scan/#{tableName}/#{JSON.stringify(scanFilter)}", db.scan(params, $p.ecb()))
        ).then (results) ->
          if results.LastEvaluatedKey?
            lastEvaluatedKey = results.LastEvaluatedKey
            delete results.LastEvaluatedKey
            results.nextPage = ->
              newOpts = _.merge {}, opts, {ExclusiveStartKey: lastEvaluatedKey}
              self.scan newOpts, scanFilter...
          results.Items =  _.map(results.Items, itemToHash)
          results
    }

exports.DynamoDbFactory = ($p, aws, dynamoDbTableFactory) ->
  (opts) ->
    db = new aws.DynamoDB(_.defaults _.clone(opts || {}), aws.config)

    return self = {
      createTable: (tableDef) ->
        if tableDef.keySchema?
          parameters = tableDef
        else
          parameters=
            attributeDefinitions: []
            keySchema: []
            provisionedThroughput: tableDef.throughput
            tableName: tableDef.tableName
          _.each tableDef.keyDefinition, (def, k) ->
            parameters.attributeDefinitions.push {attributeName: k, attributeType: def.type}
            parameters.keySchema.push {attributeName: k, keyType: def.keyType}
        $p.wrap(db.createTable(aws.upcaseAttributes(parameters, true), $p.ecb())).then (def) -> aws.lcaseAttributes(def.TableDescription)

      describeTable: (tableName) ->
        $p.wrap(db.describeTable({TableName: tableName}, $p.ecb())).then (def) -> aws.lcaseAttributes(def.Table)

      deleteTable: (tableName) ->
        $p.wrap(db.deleteTable({TableName: tableName}, $p.ecb())).then (results) -> aws.lcaseAttributes(results)

      createOrDescribeTable: (tableDef) ->
        self.createTable(tableDef).then
          error: (e) ->
            return $p.error(e) unless e.code == "ResourceInUseException"
            self.describeTable(tableDef.tableName)

      waitUntil: (tableName, status) ->
        status = _.flatten([status])
        $p.create (p) ->
          doIt = ->
            self.describeTable(tableName).then (def) ->
              return p.resolve() if def.tableStatus in status
              setTimeout doIt, 1000
          doIt()

      updateCapacity: (tableName, throughput) ->
        params =
          tableName: tableName
          provisionedThroughput: throughput
        $p.wrap(db.updateTable(aws.upcaseAttributes(params), $p.ecb()))

      table: (tableName, tableOpts) ->
        dynamoDbTableFactory(db, tableName, _.defaults({}, tableOpts, opts))

      existingTable: (tableDef) ->
        self.createOrDescribeTable(tableDef).then ->
          self.waitUntil(tableDef.tableName, ['ACTIVE', 'UPDATING']).then ->
            self.table(tableDef.tableName)
    }

exports.DynamoDb = (dynamoDbFactory) -> dynamoDbFactory()

exports.SqsFactory = ($p, $options, $logger, aws) ->
  (opts) ->
    opts = _.merge {}, $options, opts || {}
    opts.prefix?=""
    baseUrl = opts.baseUrl
    baseUrl+= opts.prefix
    sqs = new aws.SQS(opts)

    exists = (queue) ->
      $p.wrap(sqs.getQueueUrl({QueueName: "#{opts.prefix}#{queue}"}, $p.ecb())).then
        success: -> true
        error: (err) ->
          return $p.error(err) unless err.code == 'AWS.SimpleQueueService.NonExistentQueue'
          false

    createQueueOnError = (queue, block) ->
      block().then
        error: (err) ->
          return $p.error(err) unless err.code == 'AWS.SimpleQueueService.NonExistentQueue'
          defaultRedrivePolicy = _.merge {
            maxReceiveCount:5
            deadLetterTargetArn: opts.baseUrl.replace(/https:\/\/sqs.([^.]*)[^\/]*\/([0-9]*)\//, "arn:aws:sqs:$1:$2:#{opts.prefix}#{queue}-FAILED")
          }, opts.defaultRedrivePolicy || {}
          params = _.merge {
            QueueName: "#{opts.prefix}#{queue}"
            Attributes:
              DelaySeconds: '0'
              VisibilityTimeout: '300'
              RedrivePolicy: JSON.stringify(defaultRedrivePolicy)
          }, opts.queueDefaults || {}
          dlqParams = {
            QueueName: "#{opts.prefix}#{queue}-FAILED"
            Attributes:
              DelaySeconds: '0'
              VisibilityTimeout: '300'
              MessageRetentionPeriod: "1209600"
          }
          $p.when(
            exists("#{queue}-FAILED").then (exists) ->
              $p.wrap(sqs.createQueue(dlqParams, $p.ecb())) unless exists
          ).then ->
            $p.wrap(sqs.createQueue(params, $p.ecb())).then ->
              block()

    return self = {
      enqueue: (queue, message, delay) ->
        contentType = "json" unless _.isString(message)
        params = {
          MessageBody: if contentType == 'json' then JSON.stringify(message) else message
          QueueUrl: "#{baseUrl}#{queue}"
          MessageAttributes: {
            contentType:
              DataType: "String"
              StringValue: contentType
          } if contentType?
        }
        createQueueOnError queue, ->
          $p.wrap(sqs.sendMessage(params, $p.ecb()))

      remove: (queue, msgId) ->
        params = {
          QueueUrl: "#{baseUrl}#{queue}"
          ReceiptHandle: msgId
        }
        $p.wrap(sqs.deleteMessage(params, $p.ecb()))

      dequeue: (queue, numMessages, retryDelay, blockingTimeout) ->
        params = {
          QueueUrl: "#{baseUrl}#{queue}"
          MaxNumberOfMessages: numMessages || 1
          MessageAttributeNames: ['All']
          VisibilityTimeout: retryDelay
          WaitTimeSeconds: blockingTimeout
        }
        createQueueOnError queue, ->
          $p.wrap(sqs.receiveMessage(params, $p.ecb())).then (results) ->
            _.each results.Messages, (message) ->
              if message.MessageAttributes?.contentType?.StringValue == 'json'
                message.Body = JSON.parse(message.Body)
            results

      monitor: (queue, numMessages, retryDelay, blockingTimeout, block) ->
        logger = $logger.nest(queue)
        finalizePromise = null
        monitor = {
          stop: ->
            $logger.debug "STOPPING MONITOR FOR [#{queue}]"
            finalizePromise = $p.create()
        }
        checkQueue = ->
          self.dequeue(queue, numMessages, retryDelay, blockingTimeout).then
            error: (err) -> logger.error "Error during dequeue from [#{queue}]", err
            success: (results) ->
              (_.map results.Messages, (msg) ->
                $p.when(block(msg.Body, msg.MessageId)).then
                  success: -> self.remove(queue, msg.ReceiptHandle)
                  error: (err) -> logger.error "Error processing message [#{msg.MessageId}]", err
                  failure: (err) -> $p.failure(err)
              ).then ->
                return finalizePromise.resolve() if finalizePromise?
                checkQueue()

          null
        checkQueue()
        monitor
    }

exports.LogSinkFactory = ($p, aws, awsServiceWrapperFactory) ->
  logs = awsServiceWrapperFactory(new aws.CloudWatchLogs())
  (group, stream) ->
    init = ->
      logs.createLogGroup({logGroupName: group}).rescueIf("ResourceAlreadyExistsException").then ->
        logs.createLogStream({logGroupName: group, logStreamName: stream}).rescueIf("ResourceAlreadyExistsException").then ->

    inited = init()
    nextSequenceToken = null
    retried = false
    return self = {
      log: (level, message) ->
        $p.when(inited).then ->
          logs.putLogEvents(
            logEvents: [
              message: "[#{level}] #{message}"
              timestamp: moment().valueOf()
            ]
            logGroupName: group
            logStreamName: stream
            sequenceToken: nextSequenceToken
          ).then
            error: (err) ->
              return $p.error(err) unless err.code in ['DataAlreadyAcceptedException', 'InvalidSequenceTokenException']
              return $p.error(err) if retried is true
              retried = true
              nextSequenceToken = err.message.replace(/.*: /,'')
              self.log(level, message)
    }

exports.S3Factory = ($options, $p, aws, awsServiceWrapperFactory) ->
  return (opts) ->
    opts = _.defaults opts, $options
    rawS3 = new aws.S3(opts)
    s3 = awsServiceWrapperFactory(rawS3)
    s3.upload = (args...) -> $p.wrap(rawS3.upload(args..., $p.ecb()))
    s3

exports.CloudWatchFactory = ($options, $p, aws, awsMetadataService, awsServiceWrapperFactory) ->
  return (opts) ->
    opts = _.defaults opts, $options
    cloudWatch = awsServiceWrapperFactory(new aws.CloudWatch(opts))
    defaultDimensions = null
    try
      serviceName = JSON.parse(fs.readFileSync("package.json"))?.name
    catch e
    return self = {
      getAlarms: (alarms) ->
        params = {
          AlarmNames: _.flatten([alarms])
          MaxRecords: alarms.length || 1,
        }
        cloudWatch.describeAlarms(params).then (results) ->
          results.MetricAlarms
      getMetricStatistics: (metricName, dimensions, period, statistics, startTime, endTime, unit) ->
        namespace = dimensions.namespace || opts?.namespace || serviceName || 'Custom'
        dimensions = aws.upcaseAttributes(dimensions)
        params = {
          Namespace: namespace
          MetricName: aws.upcase(metricName)
          Dimensions: _.map _.omit(dimensions, 'namespace'), (v, k) -> {Name: k, Value: v}
          Period: period
          Statistics: _.flatten([statistics])
          StartTime: moment(startTime).toDate()
          EndTime: moment(endTime).toDate()
          Unit: unit
        }
        cloudWatch.getMetricStatistics(params).then (response) ->
          response.Datapoints
      recordMetrics: (metrics, dimensions, timestamp) ->
        $p.when(
          unless defaultDimensions?
            awsMetadataService.getInstanceInfo().then (info) ->
              defaultDimensions = _.pick(info, 'availabilityZone', 'instanceType', 'instanceId')
              defaultDimensions.serviceName = serviceName
        ).then ->
          dimensions = _.merge {}, defaultDimensions, dimensions
          namespace = dimensions.namespace || opts?.namespace || serviceName || 'Custom'
          namespace = 'Development' if process.env.NODE_ENV == 'development'
          dimensions = _.omit(dimensions, 'namespace')
          if namespace == defaultDimensions?.serviceName
            delete dimensions.serviceName
          dimensions = aws.upcaseAttributes(dimensions)
          metrics = aws.upcaseAttributes(metrics)
          metricData = _.flatten _.map metrics, (value, metric) ->
            _.map dimensions, (dimensionValue, dimensionName) ->
              entry = {
                MetricName: metric
                Dimensions: (
                  if _.isObject(dimensionValue)
                    _.map dimensionValue, (v, k) -> {Name: k, Value: v}
                  else
                    [{Name: dimensionName, Value: dimensionValue}]
                )
                Unit: value[1]
                Timestamp: timestamp || new Date()
              }
              if _.isObject(value[0])
                entry.StatisticValues = aws.upcaseAttributes(value[0])
              else
                entry.Value = value[0]
              entry
          batches = _.map $u.chunkArray(metricData, 20), (chunk) ->
            params = {
              Namespace: namespace
              MetricData:  chunk
            }
          $u.pageBlock 0, (batchIndex) ->
            return false unless batches[batchIndex]?
            cloudWatch.putMetricData(batches[batchIndex]).then -> true
    }

exports.CloudWatch = (cloudWatchFactory) -> cloudWatchFactory()

exports.MetadataServiceFactory = ($options, $p, aws) ->
  return (opts) ->
    opts = _.defaults opts || {}, $options, {httpOptions: timeout: 1000}
    ms = new aws.MetadataService(opts)
    query = (path) -> $p.wrap(ms.request(path, $p.ecb()))
    API_VERSION = "2014-02-25"
    cachedInfo = null
    return self = {
      getInstanceInfo: ->
        return $p.resolved(cachedInfo) if cachedInfo
        (query("/#{API_VERSION}/dynamic/instance-identity/document/").then (result) ->
          info = JSON.parse(result)
          cachedInfo = _.pick(info, 'region', 'instanceId', 'instanceType', 'imageId', 'privateIp', 'availabilityZone')
        ).then(
          error: (err) ->
            return $p.error(err) unless process.env.NODE_ENV == 'development' and err.code in ['TimeoutError', 'ECONNREFUSED']
            return {
              region: 'development'
              instanceId: 'i-local',
              instanceType: 'laptop',
              imageId: 'unknown',
              privateIp: '127.0.0.1',
              availabilityZone: 'coffee-shop'
            }
        )
    }

exports.AwsMetadataService = ($options, metadataServiceFactory) ->
  metadataServiceFactory($options)

exports.MachineLearningFactory = ($options, aws, awsServiceWrapperFactory) ->
  return (opts) ->
    opts = _.defaults opts, $options
    ml = awsServiceWrapperFactory(new aws.MachineLearning(opts))
    return self = {
      predict: (record, predictOpts) ->
        predictOpts = _.defaults predictOpts || {}, opts
        request = {
          PredictEndpoint: predictOpts.predictionEndpoint
          MLModelId: predictOpts.modelId
          Record: record
        }
        ml.predict(request).then (result) ->
          result.Prediction
    }

exports.MachineLearning = (machineLearningFactory) -> machineLearningFactory()

exports.KmsFactory = ($options, aws, awsServiceWrapperFactory) ->
  return (opts) ->
    opts = _.defaults opts, $options
    kms = awsServiceWrapperFactory(new aws.KMS(opts))
