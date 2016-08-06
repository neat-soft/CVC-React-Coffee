$p = require('./promise')
$u = require('./utilities')
pool = require('./pool')
scope = require('./scope')
{EventManager} = require('./events')
{EventEmitter} = require('events')
{Readable} = require("stream")
_ = require('lodash')
moment = require('moment')

expandNamedParameters= (sql, params, tz) ->
  if !params
    return [sql, params]
  else if params instanceof Array
    return [sql, (p for p in params)]
  else
    expandedSql = sql
    expandedParameters = []
    expandedSql=sql.replace /:([a-zA-Z0-9_]*)/g, (m,param) ->
      if(_.has(params, param))
        value = params[param]
        value = null unless value?
        if _.isArray(value)
          expandedParameters = expandedParameters.concat(value)
          ("?" for [0...value.length]).join(",")
        else
          expandedParameters.push(value)
          "?"
      else
        return m
    return [expandedSql, expandedParameters]


_prototype = null
mysql = null
augmentConnectionPrototype = ->
  mysql = require('mysql') unless mysql?
  return if _prototype!=null
  conn = mysql.createConnection({})
  _prototype = conn.__proto__
  while(!_prototype.escape?)
    _prototype = _prototype.__proto__

  convertFieldType = (dbFieldType) ->
    types = {
      'Integer'  : /^int\(.*\)/
      'Double'   : /double|decimal/
      'String'   : /varchar\(.*\)|text|char\(.*\)/
      'DateTime' : /datetime|timestamp/
      'Date'     : /^date$/
      'Boolean'  : /tinyint/
    }
    for type, pattern of types
      return type if pattern.test(dbFieldType)
    throw new Error("Unknown field type [#{dbFieldType}]")

  Object.defineProperty _prototype, 'execute',
    enumerable: false
    value: (execute = (query, args) ->
      this.executeWithDefinition(query, args).then (results) -> results
    )
  Object.defineProperty _prototype, 'executeWithDefinition',
    enumerable: false
    value: (executeWithDefinition = (query, args) ->
      [query, args] = expandNamedParameters(query,args)
      ($p.wrap(this.query(query, args, $p.ecb())).then (results, metadata) =>
        if (@config.timezone || "").toUpperCase() == 'UTC' and metadata?.length > 0
          dateFields = _.filter(metadata, (field) -> field.type == 0x0a)
          if dateFields.length > 0
            _.each results, (row) ->
              _.each dateFields, (dateField) ->
                date = row[dateField.name]
                return unless date? and _.isDate(date)
                date = moment(date).utc().format("YYYY-MM-DD")
                row[dateField.name] = date

        $p.resolved(results, metadata)
      ).then(
        error: (err) ->
          if err.code == "ER_PARSE_ERROR"
            newError = new Error("Syntax error while executing [#{query}]")
            newError.code = err.code
          $p.error(newError || err)
      )

    )
  Object.defineProperty _prototype, 'stream',
    enumerable: false
    value: (stream = (query, args) ->
      self = @
      [query, args] = expandNamedParameters(query,args)
      s = this.query(query, args)
      @pause()
      buffer = []
      p = $p.create()
      dateFields = []
      fields = []
      readable = undefined
      s.on 'error', (err) -> p.error(err)
      s.on 'fields', (_fields) ->
        fields = _fields
        readable.emit 'fields', fields if readable?
        if (self.config.timezone || "").toUpperCase() == 'UTC' and fields?.length > 0
          dateFields = _.filter(fields, (field) -> field.type == 0x0a)
      s.on 'result', (row) ->
        if dateFields.length > 0
          _.each dateFields, (dateField) ->
            date = row[dateField.name]
            return unless date? and _.isDate(date)
            date = moment(date).utc().format("YYYY-MM-DD")
            row[dateField.name] = date
        if(!readable.push(row))
          self.pause()
      s.on 'end', -> readable.push(null)
      p.readable = (streamOptions, block) ->
        [streamOptions, block] = [{}, streamOptions] if _.isFunction(streamOptions)
        readable = new Readable(_.defaults {
          objectMode: true
        }, streamOptions)
        readable.on 'end', -> p.resolve()
        readable._read = -> self.resume()
        block(readable) if block?
        readable.emit 'fields', fields if fields?
        p
      p
    )
  Object.defineProperty _prototype, 'first',
    enumerable: false
    value: (first = (query, args) ->
      this.execute(query,args).then (results) ->
        return $p.error("Unable to fetch one row for query [#{query}] it returned more than one row") if results.length > 1
        results[0]
    )
  Object.defineProperty _prototype, 'expandNamedParameters',
    enumerable: false
    value: (query, args) -> expandNamedParameters(query,args)
  Object.defineProperty _prototype, '_createTableDefinition',
    enumerable: false
    value: (tableName, fields) ->
      fields = _.map fields, (field) ->
        f = {
          name: $u.toCamelCase(field.Field)
          type: convertFieldType(field.Type)
          dbFieldName: field.Field
        }
        f.primaryKey = true if field.Key.indexOf('PRI')>-1
        f.auto = true if field.Extra.indexOf('auto_increment')>-1
        f.defaultValue = field.Default if field.Default?
        f
      return {
        tableName: tableName
        fields: $u.toMap(fields, 'name')
        primaryKey: _.map(_.filter(fields, (f) -> f.primaryKey), (f) -> f.name)
      }
  Object.defineProperty _prototype, 'describeTable',
    enumerable: false
    value: (tableName) ->
      @execute("DESCRIBE #{tableName}").then (fields) =>
        @_createTableDefinition(tableName, fields)
  Object.defineProperty _prototype, 'createMigration',
    enumerable: false
    value: (fromStructure, toStructure) ->
      [ this.first("SHOW CREATE TABLE #{fromStructure}").then((createTableSql) -> createTableSql['Create Table'])
        this.first("SHOW CREATE TABLE #{toStructure}").then((createTableSql) -> createTableSql['Create Table'])
      ].then (fromSql, toSql) ->
        parseLine = (line) ->
          line = line.trim().replace(/,$/,'')
          columnMatch = line.match(/^`(\w+)`/)
          return {type: 'column', name: columnMatch[1], sql: line} if columnMatch?
          pkeyMatch = line.match(/^PRIMARY KEY \(`(.*)`\)/)
          return {type: 'pkey', name: pkeyMatch[1], sql: line} if pkeyMatch?
          keyMatch = line.match(/^KEY `(\w+)`/)
          return {type: 'key', name: keyMatch[1], sql: line} if keyMatch?
          ukeyMatch = line.match(/^UNIQUE KEY `(\w+)`/)
          return {type: 'ukey', name: ukeyMatch[1], sql: line} if ukeyMatch?
        setBeforeAfter = (lines) ->
          _.each lines, (line, index) ->
            line.after = lines[index-1]
          lines
        fromSql = fromSql.toString().split(/\n/)
        fromSql.shift()
        fromSql.pop()
        fromSql = setBeforeAfter(_.map fromSql, parseLine)
        toSql = toSql.toString().split(/\n/)
        toSql.shift()
        toSql.pop()
        toSql = setBeforeAfter(_.map toSql, parseLine)
        missing = []
        delayedMissing = []
        broken = []
        extra = []
        pkey = _.filter(fromSql, (mi) -> mi.type=='pkey')[0]
        newColumns = []

        _.each toSql, (item) ->
          matchingItem = _.find(fromSql, (mi) -> mi.type == item.type and mi.name == item.name)
          return if matchingItem? and matchingItem.sql==item.sql
          return broken.push(item) if matchingItem?
          newColumns.push item.name if item.type=='column'
          if item.type=='ukey' and item.name in newColumns
            throw new Error("A singular primary key is required in order to create new unique columns") unless pkey? and pkey.name.match(/\w/)?
            delayedMissing.push(item)
          else
            missing.push(item)
        _.each fromSql, (item) ->
          matchingItem = _.find(toSql, (mi) -> mi.type == item.type and mi.name == item.name)
          return if matchingItem?
          extra.push(item)

        migrations = []
        delayedMigrations = []
        positions = []
        scripts = []
        _.each missing, (item) ->
          migrations.push(
            switch item.type
              when 'column' then "ADD COLUMN #{item.sql}"
              when 'key' then "ADD #{item.sql}"
              when 'pkey' then "ADD #{item.sql}"
              when 'ukey' then "ADD #{item.sql}"
          )
        _.each delayedMissing, (item) ->
          scripts.push "UPDATE #{fromStructure} SET #{item.name} = #{pkey.name}"
          scripts.push "ALTER TABLE #{fromStructure} ADD #{item.sql}"
        _.each broken, (item) ->
          migrations.push(
            switch item.type
              when 'column' then "MODIFY COLUMN #{item.sql}"
              when 'key' then "DROP INDEX #{item.name},\nADD #{item.sql}"
              when 'ukey' then "DROP INDEX #{item.name},\nADD #{item.sql}"
              when 'pkey' then "DROP PRIMARY KEY,\nADD #{item.sql}"
          )
        _.each extra, (item) ->
          migrations.push(
            switch item.type
              when 'key' then "DROP INDEX #{item.name}"
              when 'ukey' then "DROP INDEX #{item.name}"
              when 'pkey' then "DROP PRIMARY KEY"
          )
        _.each toSql, (item) ->
          positions.push(
            switch item.type
              when 'column' then "MODIFY COLUMN #{item.sql} #{if item.after? then 'AFTER '+item.after.name else 'FIRST'}"
          )

        migrations = _.filter migrations, (mig) -> mig?
        positions = _.filter positions, (mig) -> mig?
        extra = _.map _.filter(extra, (item) -> item.type=='column'), (item) -> item.name
        structure = "ALTER TABLE #{fromStructure}\n#{migrations.join(',\n')}" if migrations.length > 0
        positions = "ALTER TABLE #{fromStructure}\n#{positions.join(',\n')}" if positions.length > 0
        scripts.unshift structure if structure?
        $p.resolved(scripts, positions, extra)
  Object.defineProperty _prototype, 'migrateTable',
    enumerable: false
    value: (tableName, toStructure, dryRun, $logger) ->
      dryRun?=true
      tableLogger = $logger.nest(tableName) if $logger?
      tableLogger = {info: ->} unless tableLogger?
      baselineSql = toStructure("baseline_#{tableName}").replace(/CREATE TABLE/,'CREATE TEMPORARY TABLE')
      execute = (sql) =>
        tableLogger.info if !dryRun then "EXECUTING" else "***NOT*** EXECUTING"
        _.each sql.split(/\n/), (line) ->
          tableLogger.info "\t#{line}"
        return $p.resolved() if dryRun
        @execute(sql)
      diff = =>
        [ @first("SHOW CREATE TABLE #{tableName}").then((createTableSql) -> createTableSql['Create Table'])
          @first("SHOW CREATE TABLE baseline_#{tableName}").then((createTableSql) -> createTableSql['Create Table'])
        ].then (tableSql, baselineSql) ->
          tableSql = tableSql.replace(/CREATE.*\(/,'')
          baselineSql = baselineSql.replace(/CREATE.*\(/,'')
          baselineSql!=tableSql
      @execute(baselineSql).then =>
        diff().then (isDifferent) =>
          tableLogger.info "TABLE IS #{if isDifferent then 'DIFFERENT' else 'IDENTICAL'}"
          return false unless isDifferent
          tableLogger = tableLogger.nest("*") if $logger?
          @createMigration(tableName,"baseline_#{tableName}").then (scripts, positions, extra) ->
            tableLogger.info("EXTRA COLUMN(S) DETECTED [#{extra.join(',')}]") if extra?.length > 0
            $p.when(
              if scripts.length > 0
                tableLogger.info "UPDATING STRUCTURE"
                _.map scripts, (script) -> execute(script)
            ).then ->
              tableLogger.info "UPDATING POSITIONS"
              execute(positions).then ->
                true
  return

exports.Ql = ->
  basicOp = (op, value, dbFieldName, paramName) ->
    fragment = "#{dbFieldName} #{op} "
    return {fragment: "#{fragment}:#{paramName}", value: value} unless _.isFunction(value)
    fp = value(dbFieldName, paramName)
    {fragment: "#{fragment}#{fp.fragment}", value: fp.value}

  return self = {
    NOT: (value) -> (dbFieldName, paramName) ->
      value = self.EQ(value) unless _.isFunction(value)
      fp = value(dbFieldName, paramName)
      {fragment: "NOT #{fp.fragment}", value: fp.value}
    EQ: (value) -> (dbFieldName, paramName) ->
      return self.IN(value)(dbFieldName, paramName) if _.isArray(value)
      return {fragment: "#{dbFieldName} IS NULL"} if value is null
      basicOp("=", value, dbFieldName, paramName)
    GTE: (value) -> (dbFieldName, paramName) ->
      basicOp(">=", value, dbFieldName, paramName)
    LTE: (value) -> (dbFieldName, paramName) ->
      basicOp("<=", value, dbFieldName, paramName)
    IN: (value) -> (dbFieldName, paramName) ->
      {fragment: "#{dbFieldName} IN (:#{paramName})", value: value}
    NOW: (interval, type) -> (dbFieldName, paramName) ->
      return {fragment: "NOW()"} if !interval? and !type?
      allowedTypes = ['MINUTE', 'SECOND', 'DAY', 'MONTH', 'YEAR']
      throw new Error("Both type and interval must be omitted or provided") if interval? != type?
      throw new Error("Interval should be numeric") unless _.isNumber(interval)
      throw new Error("Type [#{type}] must be one of [#{allowedTypes.join(',')}]") unless type.toUpperCase() in allowedTypes
      {fragment: "DATE_ADD(NOW(), INTERVAL :#{paramName} #{type.toUpperCase()})", value: interval}
    OR: (clauses...) -> (formatFilter) ->
      params = {}
      clauses = _.map clauses, (clause, i) ->
        [sql, p] = formatFilter(clause, null, paramSuffix: "_#{i}")
        params = _.merge params, p
        "(#{sql})"
      return ["(#{clauses.join(' OR ')})", params]
  }

exports.MysqlTableFactory = ($p, ql, $logger) ->
  mappers =
    Boolean: (v) -> v == 1
    DateTime: (v) ->
      return undefined if !v? or (v? and v.toString() == '0000-00-00 00:00:00')
      moment(v).toDate()
    Date: (v) ->
      return undefined if !v? or (v? and v.toString() == '0000-00-00')
      moment(v).toDate()
    '1': (v) -> v == 1
  factory = (mysqlConnectionPool, name, tableDefinition) ->
    [tableDefinition, name] = [name, undefined] unless tableDefinition?
    if tableDefinition.createSql?
      tableDefinitionOverrides = _.omit(tableDefinition, 'createSql')
      tableDefinition = tableDefinition.createSql
    if _.isFunction(tableDefinition)
      createSqlGenerator = tableDefinition
      createSql = tableDefinition(name)
      return (mysqlConnectionPool (conn) ->
        conn.execute("SHOW TABLES LIKE '#{name}'").then (tables) ->
          $p.when(
            conn.execute(createSql) unless tables.length > 0
          ).then ->
            conn.describeTable(name)
      ).then (tableDefinition) ->
        _.merge tableDefinition, tableDefinitionOverrides if tableDefinitionOverrides?
        tableDefinition.createSqlGenerator = createSqlGenerator
        factory(mysqlConnectionPool, tableDefinition)

    invertedMapping = {}
    _.each tableDefinition.fields, (def, name) ->
      invertedMapping[def.dbFieldName] = def if def.dbFieldName?
    invertedGroupByPrefix = _.invert(tableDefinition.groupByPrefix) if tableDefinition.groupByPrefix?
    parseLimit = (limit) ->
      return ["", {}] unless limit?
      limit = {count: limit} if _.isNumber(limit)
      throw new Error("Invalid limit clause [#{limit}], must be an integer or an object with {count, [start]} or {page, pageSize}") unless _.isObject(limit) and (limit.count? or (limit.page? and limit.pageSize))
      if limit.count?
        throw new Error("Invalid limit clause [#{limit}], both count and start have to be numbers") unless _.isNumber(limit.count) and (!limit.start? or _.isNumber(limit.start))
      else if limit.page?
        throw new Error("Invalid limit clause [#{limit}], both page and pageSize have to be numbers") unless _.isNumber(limit.page) and _.isNumber(limit.pageSize)
        limit.start = (limit.page - 1) * limit.pageSize
        limit.count = limit.pageSize
      sql = "LIMIT #{if limit.start? then ':__limitStart, ' else ''}:__limitCount"
      params = {__limitCount: limit.count}
      params.__limitStart = limit.start if limit.start?
      return [sql, params]
    localEventManager = EventManager()
    #Compatibility with deprecated event handling
    _.each tableDefinition.events || {}, (handler, event) ->
      localEventManager.on event, (args...) -> handler.apply(self, args)
    return self = {
      on: (event, handler) -> localEventManager.on event, handler.bind(self)
      getTableName: -> tableDefinition.tableName
      rowToObject: (row, rowDefinition) ->
        unmapped = {}
        for own k,v of row
          fieldDef = invertedMapping[k]
          if fieldDef?
            mappedValue = v
            mappedValue = mappers[fieldDef.type](mappedValue) if mappers[fieldDef.type]?
            unmapped[fieldDef.name]=mappedValue if mappedValue?
          else if rowDefinition?[k]?
            mappedValue = v
            mappedValue = mappers[rowDefinition[k].type](mappedValue) if mappers[rowDefinition[k].type]?
            unmapped[k] = mappedValue
          else
            unmapped[k] = v
        unmapped = $u.groupByPrefix(unmapped, tableDefinition.groupByPrefix) if tableDefinition.groupByPrefix?
        unmapped = tableDefinition.rowFormatter(unmapped) if tableDefinition.rowFormatter?
        unmapped
      formatKey: (key, extractPrimary = false) ->
        pkey = {}
        emptyArrayDetected = false
        if _.isObject(key)
          _.each key, (v, k) ->
            throw new Error("Unknown field [#{k}] for table [#{tableDefinition.tableName}]") unless tableDefinition.fields[k]?
            if !extractPrimary or (extractPrimary and tableDefinition.fields[k].primaryKey)
              emptyArrayDetected = true if _.isArray(v) and v.length == 0
              pkey[k] = v
        else
          throw new Error("Unable to format singular key value when primary key has multiple columns") if tableDefinition.primaryKey.length > 1
          emptyArrayDetected = true if _.isArray(key) and key.length == 0
          pkey[tableDefinition.primaryKey[0]] = key
        return {emptyArrayDetected: true} if emptyArrayDetected
        pkey
      formatFilter: (filter, params, opts) ->
        filter = self.formatKey(filter)
        return [filter] if filter.emptyArrayDetected == true
        params ?= {}
        paramPrefix = opts?.paramPrefix || ""
        paramSuffix = opts?.paramSuffix || ""
        sql = (_.map filter, (value, field) ->
          dbFieldName = tableDefinition.fields[field]?.dbFieldName
          if value?
            value = ql.EQ(value) unless _.isFunction(value)
            fragmentAndValue = value(dbFieldName, "#{paramPrefix}#{field}#{paramSuffix}", self.formatFilter)
            params["#{paramPrefix}#{field}#{paramSuffix}"] = fragmentAndValue.value if fragmentAndValue.value?
            return fragmentAndValue.fragment
            #return "#{dbFieldName} IN (:#{paramPrefix}#{field})" if _.isArray(value)
            #return "#{dbFieldName}=:#{paramPrefix}#{field}"
          "#{dbFieldName} IS NULL"
        ).join(' AND ')
        [sql, params]
      insert: (row) ->
        row = $u.flattenObject(row, invertedGroupByPrefix)
        fieldNames = []
        names = []
        row.createTime = ql.NOW() unless row.createTime? or !tableDefinition.fields.createTime?
        row.updateTime = ql.NOW() unless row.updateTime? or !tableDefinition.fields.updateTime?
        _.each row, (value, key) ->
          dbFieldName = tableDefinition.fields[key]?.dbFieldName
          if dbFieldName?
            fieldNames.push(dbFieldName)
            return names.push(":#{key}") unless _.isFunction(value)
            fp = value(dbFieldName, key)
            names.push(fp.fragment)
            row[key] = fp.value
            delete row[key] unless fp.value?
        sql = "INSERT INTO #{tableDefinition.tableName}(#{fieldNames.join(', ')}) VALUES(#{names.join(', ')})"
        (mysqlConnectionPool (mysqlConnection) ->
          mysqlConnection.execute(sql, row)
        ).then (results...) ->
          localEventManager.emit('insert', row, results...).then ->
            return $p.resolved(results...)
      replace: (row) ->
        row = $u.flattenObject(row, invertedGroupByPrefix)
        fieldNames = []
        names = []
        row.createTime = ql.NOW() unless row.createTime? or !tableDefinition.fields.createTime?
        row.updateTime = ql.NOW() unless row.updateTime? or !tableDefinition.fields.updateTime?
        _.each row, (value, key) ->
          dbFieldName = tableDefinition.fields[key]?.dbFieldName
          if dbFieldName?
            fieldNames.push(dbFieldName)
            return names.push(":#{key}") unless _.isFunction(value)
            fp = value(dbFieldName, key)
            names.push(fp.fragment)
            row[key] = fp.value
            delete row[key] unless fp.value?
        sql = "REPLACE INTO #{tableDefinition.tableName}(#{fieldNames.join(', ')}) VALUES(#{names.join(', ')})"
        (mysqlConnectionPool (mysqlConnection) ->
          mysqlConnection.execute(sql, row)
        ).then (results...) ->
          localEventManager.emit('replace', row, results...).then ->
            return $p.resolved(results...)
      update: (_filter, _updates) ->
        [filter, updates] = [_filter, _updates]
        updates = $u.flattenObject(updates, invertedGroupByPrefix)
        if _.isObject(filter)
          limit = filter._limit
          filter = _.omit(filter, '_limit')
        [filter, params] = self.formatFilter(filter, {}, {paramPrefix: '_'})
        return $p.resolved(0) if filter.emptyArrayDetected is true
        updates.updateTime = ql.NOW() unless updates.updateTime? and tableDefinition.fields.updateTime?
        updates = _.map updates, (value, field) ->
          fieldDef = tableDefinition.fields[field]
          return unless fieldDef?.dbFieldName?
          if !_.isFunction(value)
            params[field] = value
            return "#{fieldDef.dbFieldName} = :#{field}"
          else
            fp = value(fieldDef.dbFieldName, field)
            params[field] = fp.value if fp.value?
            "#{fieldDef.dbFieldName} = #{fp.fragment}"
        updates = _.filter(updates, (field) -> field?)
        sql = "UPDATE #{tableDefinition.tableName} SET #{updates.join(', ')} WHERE #{filter}"
        if limit?
          [limitClause, limitParams] = parseLimit(limit)
          [sql, params] = ["#{sql} #{limitClause}", _.merge(params, limitParams)]
        (mysqlConnectionPool (mysqlConnection) ->
          mysqlConnection.execute(sql, params)
        ).then (results...) ->
          localEventManager.emit('update', _filter, _updates, results...).then ->
            return $p.resolved(results...)
      upsert: (row) ->
        self.insert(row).then
          error: (err) ->
            return $p.error(err) unless err.code == 'ER_DUP_ENTRY'
            pkey = self.formatKey(row, true)
            self.update(pkey, _.omit(row, _.keys(pkey)))
      query: (filter, params) ->
        if _.isObject(filter)
          sortBy = filter._sortBy
          limit = filter._limit
          filter = _.omit(filter, '_sortBy', '_limit')
          filter = filter.filter if filter.filter?
          [filter, params] = filter(self.formatFilter.bind(self)) if _.isFunction(filter)
        fields = _.filter(_.map(tableDefinition.fields, (field) -> field.dbFieldName), (field) -> field?)
        fields = _.map(fields, (field) -> "#{params?._tableAlias}.#{field}") if params?._tableAlias?
        params = _.omit params, '_tableAlias'
        orderByClause = ""
        if sortBy?
          if _.isString(sortBy) and invertedMapping[sortBy]?
            orderByClause = " ORDER BY #{invertedMapping[sortBy].dbFieldName}"
          else if _.isString(sortBy)
            orderByClause = " ORDER BY #{sortBy}"
          else
            orderByClause = " ORDER BY #{invertedMapping[sortBy.field].dbFieldName} #{sortBy.dir}"
        if _.isString(filter)
          if filter.match(/^FROM/)?
            sql = "SELECT #{fields.join(', ')} #{filter}#{orderByClause}"
          else if filter.match(/^SELECT/)?
            sql = filter
          else
            sql = "SELECT #{fields.join(', ')} FROM #{tableDefinition.tableName} WHERE #{filter}#{orderByClause}"
        else
          [filter, params] = self.formatFilter(filter)
          return $p.resolved([]) if filter.emptyArrayDetected is true
          sql = "SELECT #{fields.join(', ')} FROM #{tableDefinition.tableName} WHERE #{filter}#{orderByClause}"
        if limit?
          [limitClause, limitParams] = parseLimit(limit)
          [sql, params] = ["#{sql} #{limitClause}", _.merge(params, limitParams)]

        mysqlConnectionPool (mysqlConnection) ->
          mysqlConnection.executeWithDefinition(sql, params).then (rows, definition) ->
            definition = $u.toMap(definition, 'name') if definition?
            _.map rows, (row) -> self.rowToObject(row, definition)
      first: (filter, params) ->
        self.query(filter, params).then (rows) -> rows[0]
      delete: (_filter) ->
        [filter, params] = self.formatFilter(_filter)
        return $p.resolved(0) if filter.emptyArrayDetected is true
        sql = "DELETE FROM #{tableDefinition.tableName} WHERE #{filter}"
        (mysqlConnectionPool (mysqlConnection) ->
          mysqlConnection.execute(sql, params)
        ).then (results...) ->
          localEventManager.emit('delete', _filter).then ->
            return $p.resolved(results...)
      migrate: (dryRun) ->
        return $p.failure("Unable to migrate table that wasn't defined via a function definition") unless tableDefinition.createSqlGenerator?
        (mysqlConnectionPool (mysqlConnection) ->
          mysqlConnection.migrateTable(tableDefinition.tableName, tableDefinition.createSqlGenerator, dryRun, $logger)
        ).then ->
    }

exports.MysqlConnectionFactory = ($p) ->
  mysql = require('mysql') unless mysql?
  augmentConnectionPrototype()
  (opts) ->
    mysql.createConnection(opts || {})

exports.MysqlConnectionPoolFactory = ($p, $u, mysqlConnectionFactory) ->
  mysql = require('mysql') unless mysql?
  id = 0
  return (opts) ->
    connectionPoolId = $u.randomString(20)
    localPoolInstance=null
    delayNewConnections = null
    count = 0
    opts = _.merge {
        create: ->
          delayNewConnections = null if delayNewConnections? and delayNewConnections.resolved == true
          $p.when(delayNewConnections).then ->
            connection = mysqlConnectionFactory(opts.connectionInfo)
            connection.on 'error', (err) ->
              localPoolInstance.destroy(connection)
            connection
        destroy: (mysqlClient) ->
          mysqlClient.destroy()
        errorHandler: (poolInstance, instance, err) ->
          delayNewConnections = $u.pause(2000) if err?.code in ['ECONNREFUSED','PROTOCOL_CONNECTION_LOST'] and (!delayNewConnections? or delayNewConnections.isResolved())
          return poolInstance.destroy(instance) if err?.fatal == true
          if opts.reconnectOnReadonlyError == true and err?.code == "ER_OPTION_PREVENTS_STATEMENT"
            delayNewConnections = $u.pause(2000) if !delayNewConnections? or delayNewConnections.isResolved()
            poolInstance.destroyAll()
          poolInstance.release(instance)
        acquire: (acquire, block) ->
          globalTrxInfo = scope.current?.__mysqlTransaction
          return unless globalTrxInfo?
          globalTrxInfo.transactions?={}
          trxInfo = (globalTrxInfo.transactions[connectionPoolId]?={})
          if trxInfo.connection?
            return trxInfo.connection.then(block)
          trxInfo.connection = $p.create()
          trxInfo.connectionReleased = $p.create()
          acquire (connection) ->
            connection.execute("BEGIN").then ->
              trxInfo.connection.resolve(connection)
              globalTrxInfo.release.then (finalSql) ->
                $p.when(connection.execute(finalSql) if finalSql?).then ->
                  trxInfo.connectionReleased.resolve()
          trxInfo.connection.then(block)
      }, opts
    localPoolInstance = pool.create(opts)
    localPoolInstance

exports.MysqlTransactionCoordirnator = ->
  release = (finalSql)->
    scope.current.__mysqlTransaction.release.resolve(finalSql)
    (_.map scope.current.__mysqlTransaction.transactions, (trxInfo) ->
      trxInfo.connectionReleased
    ).then ->
      scope.current.__mysqlTransaction = undefined

  return self = {
    begin: ->
      throw new Error("Transactions are not supported if scope is not in use!") unless scope.active
      throw new Error("Transaction already started, nested transactions are not supported!") if scope.current.__mysqlTransaction?
      scope.current.__mysqlTransaction = {release: $p.create()}
    commit: -> release("COMMIT")
    rollback: -> release("ROLLBACK")
    inTransaction: (block) ->
      throw new Error("Transaction already started, nested transactions are not supported!") if scope.current?.__mysqlTransaction?
      scope.run ->
        self.begin()
        $p.create (p) ->
          $p.when(block()).then
            success: (args...) ->
              self.commit().then ->
                p.resolve(args...)
            error: (args...) ->
              self.rollback().then ->
                p.error(args...)
            failure: (args...) ->
              self.rollback().then ->
                p.failure(args...)
  }

exports.MysqlConnectionPool = ($options, mysqlConnectionPoolFactory) -> mysqlConnectionPoolFactory($options)