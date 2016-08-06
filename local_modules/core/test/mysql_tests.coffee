should = require('should')
{$p, $u, di, expect} = require('../index')
_ = require('lodash')
moment = require('moment')

omit = (fields) -> (p) ->
  p.then (result) ->
    return result unless result?
    return _.omit(result, fields) if _.isObject(result)
    return _.map((result), (item) -> _.omit(item, fields)) if _.isArray(result)
    throw new Error("Unable to omit [#{fields}] in [#{result}]")

di.describe 'MysqlClient', (ctx, it) ->
  basicTableDefinition = null
  beforeEach (done) ->
    ctx.registerMock 'events'
    ctx.register 'basicTableDefinition', (events) -> {
      tableName: 'someTable'
      primaryKey: ["id"]
      events: {
        insert: (args...) -> events.insert.apply(this, args) if events.insert?
        update: (args...) -> events.update.apply(this, args) if events.update?
        delete: (args...) -> events.delete.apply(this, args) if events.delete?
        replace: (args...) -> events.replace.apply(this, args) if events.replace?
      }
      fields:
        id: {name: 'id', type: 'Integer', dbFieldName: 'id', primaryKey: true, auto: true}
        stringField: {name: 'stringField', type: 'String', dbFieldName: 'stringField'}
        dateField: {name: 'dateField', type: 'DateTime', dbFieldName: 'dateField'}
        booleanField: {name: 'booleanField', type: 'Boolean', dbFieldName: 'booleanField', defaultValue: '0'}
        doubleField: {name: 'doubleField', type: 'Double', dbFieldName: 'doubleField'}
        createTime: {name: 'createTime', type: 'DateTime', dbFieldName: 'createTime'}
        updateTime: {name: 'updateTime', type: 'DateTime', dbFieldName: 'updateTime'}
      rowFormatter: (row) ->
        row.testValue = 'OK' if row.stringField == 'FORMATTER'
        row
    }
    ctx.registerAll require('../src/mysql')
    basicTableDefinition = ctx.basicTableDefinition

    done()

  describe "MysqlConnectionFactory", ->
    beforeEach (done) ->
      ctx.register 'mysqlConnection', (mysqlConnectionFactory) -> mysqlConnectionFactory({})
      done()

    it "should add execute and expandNamedParameters methods", ->
      should.exist(ctx.mysqlConnection.execute)
      should.exist(ctx.mysqlConnection.expandNamedParameters)

    describe "expandNamedParameters", ->
      it "should convert :argument to ? notation", ->
        ctx.mysqlConnection.expandNamedParameters("SELECT * FROM table WHERE key = :someKey", {someKey: 123})
          .should.eql ["SELECT * FROM table WHERE key = ?", [123]]

      it "should support expanding arrays", ->
        ctx.mysqlConnection.expandNamedParameters("SELECT * FROM table WHERE key = :someKey AND range IN (:someArray)", {someKey: 123, someArray: [1,2,3,4,5]})
          .should.eql ["SELECT * FROM table WHERE key = ? AND range IN (?,?,?,?,?)", [123,1,2,3,4,5]]

  describe "MysqlConnectionPoolFactory", ->
    it "should create a pool of mysql connections", ->
      pool = ctx.mysqlConnectionPoolFactory()
      pool (conn) ->
        should.exist(conn.execute)

    it "should close all connection if a readonly error is encountered", ->
      pool = ctx.mysqlConnectionPoolFactory({reconnectOnReadonlyError: true})
      acquiredPromises = ($p.create() for [0..8])
      releasedPromises = _.map [0..8], (index) ->
        pool ->
          acquiredPromises[index].resolve()
          $u.pause(100)
      acquiredPromises.then ->
        pool.getAvailable().should.equal(1)
        releasedPromises.then ->
          pool.getAvailable().should.equal(10)
          pool.getIdle().should.equal(9)
          ((pool (conn) ->
            return $p.error(code: "ER_OPTION_PREVENTS_STATEMENT")
          ).then
            error: (err) -> err
          ).should.eql(code: "ER_OPTION_PREVENTS_STATEMENT").then ->
            $u.pause(100).then ->
              pool.getAvailable().should.equal(10)
              pool.getIdle().should.equal(0)
  describe "MysqlTableFactory", ->
    ql = null
    currentTime = moment().milliseconds(0).toDate()
    beforeEach (done) ->
      ctx.register 'testTable', (mysqlTableFactory, mysqlConnectionPool, basicTableDefinition) -> mysqlTableFactory(mysqlConnectionPool, basicTableDefinition)
      ctx.register 'mysqlConnectionPool', (mysqlConnection) ->
        pool = (block) -> block(mysqlConnection)
        pool.currentTime = -> currentTime
        pool
      ctx.registerMock 'mysqlConnection'
      ctx.invoke (testTable) ->
        ql = ctx.ql
        basicTableDefinition = ctx.basicTableDefinition
        done()

    it "should support insert method", ->
      row = {stringField: 'Hello', booleanField: false}
      ctx.mysqlConnection.execute = expect("INSERT INTO someTable(stringField, booleanField, createTime, updateTime) VALUES(:stringField, :booleanField, NOW(), NOW())", row).andResolve({insertId: 0})
      ctx.testTable.insert(row).should.eql(insertId: 0)

    it "should support replace method", ->
      row = {stringField: 'Hello', booleanField: false}
      ctx.mysqlConnection.execute = expect("REPLACE INTO someTable(stringField, booleanField, createTime, updateTime) VALUES(:stringField, :booleanField, NOW(), NOW())", row).andResolve({insertId: 0})
      ctx.testTable.replace(row).should.eql(insertId: 0)

    it "should support update method", ->
      row = {stringField: 'Hello', booleanField: false}
      ctx.mysqlConnection.execute = expect("UPDATE someTable SET stringField = :stringField, booleanField = :booleanField, updateTime = NOW() WHERE id = :_id", _.merge({_id: 1},row)).andResolve(changedRows: 1)
      ctx.testTable.update(1, row).should.eql(changedRows: 1)

    it "should support upsert method", ->
      ctx.mysqlConnection.execute = expect("INSERT INTO someTable(id, stringField, createTime, updateTime) VALUES(:id, :stringField, NOW(), NOW())", {id: 1, stringField: 'hello'}).andResolve($p.error({code: 'ER_DUP_ENTRY'}))
                                   .expect("UPDATE someTable SET stringField = :stringField, updateTime = NOW() WHERE id = :_id", {_id: 1, stringField: 'hello'}).andResolve(changedRows: 1)
      ctx.testTable.upsert({id: 1, stringField: 'hello'}).should.eql(changedRows: 1)

    it "should support delete method", ->
      ctx.mysqlConnection.execute = expect("DELETE FROM someTable WHERE id = :id", {id: 1}).andResolve(affectedRows: 1)
      ctx.testTable.delete(1).should.eql(affectedRows: 1)

    it "should support query method", ->
      rows = [{id: 1, stringField: 'ONE'},{id: 2, stringField: 'TWO'}]
      filter = {stringField: 'xyz', doubleField: 1.2}
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE stringField = :stringField AND doubleField = :doubleField", filter).andResolve(rows)
      ctx.testTable.query(filter).should.eql(rows)

    it "should support rowFormatter method", ->
      rows = [{id: 1, stringField: 'FORMATTER'},{id: 2, stringField: 'TWO'}]
      filter = {stringField: 'xyz', doubleField: 1.2}
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE stringField = :stringField AND doubleField = :doubleField", filter).andResolve(rows)
      rows[0].testValue = 'OK'
      ctx.testTable.query(filter).should.eql(rows)

    it "should return [] without calling database if one of the filters is an empty array", ->
      filter = {stringField: []}
      ctx.testTable.query(filter).should.eql([])

    it "should construct a correct query with an orderBy clause", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE stringField = :stringField ORDER BY dateField", {stringField: 1}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: 1, _sortBy: 'dateField').should.eql([stringField:1])

    it "should construct a correct query with an orderBy clause with direction", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE stringField = :stringField ORDER BY dateField DESC", {stringField: 1}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: 1, _sortBy: {field: 'dateField', dir: 'DESC'}).should.eql([stringField:1])

    it "should construct a correct query with an arbitrary orderBy clause", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE stringField = :stringField ORDER BY dateField ASC", {stringField: 1}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: 1, _sortBy: 'dateField ASC').should.eql([stringField:1])

    it "should construct a correct query with an array clause", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE stringField IN (:stringField)", {stringField: [1,2]}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: [1,2]).should.eql([stringField:1])

    it "should construct a correct query when a where clause and parameters are provided instead of a filter", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE field = :value", {value: 1}).andResolve([{stringField: 1}])
      ctx.testTable.query("field = :value", value: 1).should.eql([stringField:1])

    it "should construct a correct query that uses ql parameter wrappers", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE NOT stringField = :stringField", {stringField: "OK"}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: ql.NOT("OK")).should.eql([stringField:1])

    it "should construct a correct query that uses ql.or function", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE ((stringField = :stringField_0) OR (stringField = :stringField_1))", {stringField_0: 1, stringField_1: 2}).andResolve([])
      ctx.testTable.query(filter: ql.OR({stringField: 1}, {stringField: 2})).should.eql([])

    it "should construct a correct query that uses a null value", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE stringField IS NULL", {}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: null).should.eql([stringField:1])

    it "should construct a correct query that uses a null value in ql.EQ function", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE stringField IS NULL", {}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: ql.EQ(null)).should.eql([stringField:1])

    it "should construct a correct query that uses a not null value", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE NOT stringField IS NULL", {}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: ql.NOT(null)).should.eql([stringField:1])

    it "should construct a correct query that uses ql GTE function ", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE stringField >= :stringField", {stringField: 1}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: ql.GTE(1)).should.eql([stringField:1])

    it "should construct a correct query that uses ql NOW function ", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE createTime >= NOW()", {}).andResolve([{stringField: 1}])
      ctx.testTable.query(createTime: ql.GTE(ql.NOW())).should.eql([stringField:1])

    it "should construct a correct query that uses ql NOW function with parameters ", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE createTime >= DATE_ADD(NOW(), INTERVAL :createTime DAY)", {createTime: 5}).andResolve([{stringField: 1}])
      ctx.testTable.query(createTime: ql.GTE(ql.NOW(5, "day"))).should.eql([stringField:1])

    it "should support insert method with ql functions", ->
      row = {dateField: ql.NOW()}
      ctx.mysqlConnection.execute = expect("INSERT INTO someTable(dateField, createTime, updateTime) VALUES(NOW(), NOW(), NOW())", {}).andResolve({insertId: 0})
      ctx.testTable.insert(row).should.eql(insertId: 0)

    it "should support update with a date value", ->
      now = new Date()
      row = {dateField: now}
      ctx.mysqlConnection.execute = expect("UPDATE someTable SET dateField = :dateField, updateTime = NOW() WHERE id = :_id", {_id: 1, dateField: now}).andResolve(changedRows: 1)
      ctx.testTable.update(1, row).should.eql(changedRows: 1)

    it "should support update method with ql functions", ->
      row = {dateField: ql.NOW()}
      ctx.mysqlConnection.execute = expect("UPDATE someTable SET dateField = NOW(), updateTime = NOW() WHERE id = :_id", {_id: 1}).andResolve(changedRows: 1)
      ctx.testTable.update(1, row).should.eql(changedRows: 1)

    it "should construct a correct query when a from clause and parameters are provided instead of a filter", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{_.keys(basicTableDefinition.fields).join(', ')} FROM someTable WHERE field = :value", {value: 1}).andResolve([{stringField: 1}])
      ctx.testTable.query("FROM someTable WHERE field = :value", value: 1).should.eql([stringField:1])

    it "should construct a correct query when a from uses a table alias", ->
      aliasFields = _.map basicTableDefinition.fields, (v, field) -> "t.#{field}"
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT #{aliasFields.join(', ')} FROM someTable t WHERE field = :value", {value: 1}).andResolve([{stringField: 1}])
      ctx.testTable.query("FROM someTable t WHERE field = :value", _tableAlias: 't', value: 1).should.eql([stringField:1])

    it "should construct a correct query when a full select clause and parameters are provided instead of a filter", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT * FROM someTable WHERE field = :value", {value: 1}).andResolve([{stringField: 1}])
      ctx.testTable.query("SELECT * FROM someTable WHERE field = :value", value: 1).should.eql([stringField:1])

    it "should construct a select query that uses a simple limit clause", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT id, stringField, dateField, booleanField, doubleField, createTime, updateTime FROM someTable WHERE stringField = :stringField LIMIT :__limitCount", {stringField: 1, __limitCount: 5}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: 1, _limit: 5).should.eql([stringField:1])

    it "should construct a select query that uses a range limit clause", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT id, stringField, dateField, booleanField, doubleField, createTime, updateTime FROM someTable WHERE stringField = :stringField LIMIT :__limitStart, :__limitCount", {stringField: 1, __limitStart: 5, __limitCount: 4}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: 1, _limit: {start: 5, count: 4}).should.eql([stringField:1])

    it "should construct a select query that uses a limit with pagination", ->
      ctx.mysqlConnection.executeWithDefinition = expect("SELECT id, stringField, dateField, booleanField, doubleField, createTime, updateTime FROM someTable WHERE stringField = :stringField LIMIT :__limitStart, :__limitCount", {stringField: 1, __limitStart: 4, __limitCount: 4}).andResolve([{stringField: 1}])
      ctx.testTable.query(stringField: 1, _limit: {page: 2, pageSize: 4}).should.eql([stringField:1])

    it "should construct an update query that uses a simple limit clause", ->
      ctx.mysqlConnection.execute = expect("UPDATE someTable SET stringField = :stringField, updateTime = NOW() WHERE stringField = :_stringField LIMIT :__limitCount", {_stringField: 1, stringField: 2, __limitCount: 5}).andResolve(1)
      ctx.testTable.update({stringField: 1, _limit: 5}, {stringField: 2}).should.eql(1)

    it "should invoke insert event", ->
      ctx.mysqlConnection.execute = -> $p.resolved(1)
      ctx.events.insert = expect({stringField: 1}, 1).andResolve()
      ctx.testTable.insert({stringField: 1}).should.eql(1)

    it "should invoke replace event", ->
      ctx.mysqlConnection.execute = -> $p.resolved(1)
      ctx.events.replace = expect({stringField: 1}, 1).andResolve()
      ctx.testTable.replace({stringField: 1}).should.eql(1)

    it "should invoke update event", ->
      ctx.mysqlConnection.execute = -> $p.resolved(1)
      ctx.events.update = expect({stringField: 1}, {stringField: 2}, 1).andResolve()
      ctx.testTable.update({stringField: 1}, {stringField: 2}).should.eql(1)

    it "should invoke delete event", ->
      ctx.mysqlConnection.execute = -> $p.resolved(1)
      ctx.events.delete = expect({stringField: 1}).andResolve()
      ctx.testTable.delete({stringField: 1}).should.eql(1)

    it "should invoke events registered via 'on'", ->
      ctx.mysqlConnection.execute = -> $p.resolved(1)
      events = {
        delete: expect({stringField: 1}).andResolve()
        update: expect({id: 2}, {stringField: 2}, 1).andResolve()
        insert: expect({stringField: 3}, 1).andResolve()
        replace: expect({stringField: 4}, 1).andResolve()
      }
      _.each events, (f, name) ->
        ctx.testTable.on name, f
      [ ctx.testTable.delete({stringField: 1}).should.eql(1)
        ctx.testTable.update({id: 2}, {stringField: 2}).should.eql(1)
        ctx.testTable.insert({stringField: 3}).should.eql(1)
        ctx.testTable.replace({stringField: 4}).should.eql(1)
      ].then ->
        _.each events, (f, name) ->
          f.hasExpectations().should.equal(false, "#{name} was not called")

    it "should support second form and create a table if one doesn't exist", ->
      testTable2Sql = (name) -> """
        CREATE TABLE #{name}(
          id INT(11) NOT NULL
        )
      """
      ctx.mysqlConnection.execute = expect("SHOW TABLES LIKE 'testTable2'").andResolve([])
                                   .expect(testTable2Sql('testTable2')).andResolve()
                                   .expect("INSERT INTO testTable2(id) VALUES(:id)", {id:1}).andResolve(1)
      ctx.mysqlConnection.describeTable = expect("testTable2").andResolve({tableName: 'testTable2', fields: {id: {primaryKey: true, name: 'id', dbFieldName: 'id', type: 'int'}}})
      $p.when(ctx.mysqlTableFactory(ctx.mysqlConnectionPool, "testTable2", testTable2Sql)).then (table) ->
        table.insert(id: 1).should.eql(1)

    it "should support second form and not create a table if one exists", ->
      ctx.mysqlConnection.execute = expect("SHOW TABLES LIKE 'testTable2'").andResolve([{name: 'testTable2'}])
                                   .expect("INSERT INTO testTable2(id) VALUES(:id)", {id:1}).andResolve(1)
      ctx.mysqlConnection.describeTable = expect("testTable2").andResolve({tableName: 'testTable2', fields: {id: {primaryKey: true, name: 'id', dbFieldName: 'id', type: 'int'}}})
      $p.when(ctx.mysqlTableFactory(ctx.mysqlConnectionPool, "testTable2", ->)).then (table) ->
        table.insert(id: 1).should.eql(1)

    it "should support third form and propogate additional parameters to table definition", ->
      ctx.mysqlConnection.execute = expect("SHOW TABLES LIKE 'testTable2'").andResolve([{name: 'testTable2'}])
                                   .expect("INSERT INTO testTable2(id) VALUES(:id)", {id:1}).andResolve(1)
      ctx.mysqlConnection.describeTable = expect("testTable2").andResolve({tableName: 'testTable2', fields: {id: {primaryKey: true, name: 'id', dbFieldName: 'id', type: 'int'}}})
      events = {insert: expect({id: 1}, 1).andResolve()}
      $p.when(ctx.mysqlTableFactory(ctx.mysqlConnectionPool, "testTable2", {events: events, createSql: ->})).then (table) ->
        table.insert(id: 1).should.eql(1).then ->
          events.insert.hasExpectations().should.equal(false)

  describe "Connection Integration Tests", ->
    conn = null
    currentTime = moment().milliseconds(0).toDate()
    beforeEach (done) ->
      ctx.register 'mysqlConnection', (mysqlConnectionFactory) -> mysqlConnectionFactory({host: 'localhost', user:'dev', password: 'pass', timezone: 'UTC'})
      ctx.register 'mysqlConnectionPool', (mysqlConnection) ->
        pool = (block) -> block(mysqlConnection)
        pool.currentTime = -> currentTime
        pool

      ctx.invoke (mysqlConnection, mysqlTransactionCoordirnator, mysqlTableFactory) ->
        conn = ctx.mysqlConnection
        conn.execute("USE test").then ->
          done()

    describe "type mappings", ->
      beforeEach (done) ->
        conn.execute("""
          CREATE TEMPORARY TABLE someTable(
            id int(11) NOT NULL AUTO_INCREMENT,
            b tinyint(1) NOT NULL,
            d date NULL,
            t timestamp NULL,
            d1 date NOT NULL DEFAULT 0,
            t1 timestamp NOT NULL DEFAULT 0,
            PRIMARY KEY(id)
          )
        """).then ->
          conn.execute("INSERT INTO someTable(b) VALUES(1)").then ->
            conn.describeTable("someTable").then (tableDefinition) ->
              ctx.register 'testTable', ctx.mysqlTableFactory(ctx.mysqlConnectionPool, tableDefinition)
              ctx.invoke (testTable) -> done()

      it "should passthrough fields that don't have a mapping in case we have a custom query", ->
        ctx.testTable.query("SELECT id, b, 1 v FROM someTable").should.eql([{id: 1, b: true, v: 1}])

      it "should map datatypes for fields that don't have a mapping", ->
        ctx.testTable.query("SELECT id, b, b v FROM someTable").should.eql([{id: 1, b: true, v: true}])

      it "should correctly handle null timestamp columns", ->
        ctx.testTable.query("SELECT id, t FROM someTable").should.eql([{id: 1}])

      it "should correctly handle null date columns", ->
        ctx.testTable.query("SELECT id, d FROM someTable").should.eql([{id: 1}])

      it "should correctly handle not null timestamp columns", ->
        ctx.testTable.query("SELECT id, t1 FROM someTable").should.eql([{id: 1}])

      it "should correctly handle not null date columns", ->
        ctx.testTable.query("SELECT id, d1 FROM someTable").should.eql([{id: 1}])

      it "should correctly convert date columns", ->
        conn.execute("INSERT INTO someTable(d) VALUES('2015-02-01')").then ->
          ctx.testTable.query("SELECT id, d FROM someTable WHERE id = 2").should.eql([{id: 2, d: moment('2015-02-01').toDate()}])

      it "should correctly convert timestamp columns", ->
        conn.execute("INSERT INTO someTable(t) VALUES('2015-02-01 01:02:03')").then ->
          ctx.testTable.query("SELECT id, t FROM someTable WHERE id = 2").should.eql([{id: 2, t: moment('2015-02-01 01:02:03Z').toDate()}])

    describe "groupByPrefix", ->
      table = null
      beforeEach (done) ->
        conn.execute("""
          CREATE TEMPORARY TABLE someTable(
            id int(11) NOT NULL AUTO_INCREMENT,
            valueA int(11) NULL,
            valueB int(11) NULL,
            otherValue int(11) NULL,
            PRIMARY KEY(id)
          )
        """).then ->
          [ conn.describeTable("someTable")
            conn.execute("INSERT INTO someTable(valueA, valueB, otherValue) VALUES(1,2,3)")
            conn.execute("INSERT INTO someTable(valueA, valueB, otherValue) VALUES(1,3,4)")
          ].then (tableDefinition) ->
            tableDefinition.groupByPrefix = {value: 'value'}
            table = ctx.mysqlTableFactory(ctx.mysqlConnectionPool, tableDefinition)
            ctx.invoke (mysqlTableFactory) ->
              done()

      it "should correctly group by common prefix", ->
        table.query(valueA:1).should.eql([
          {id: 1, value: {a: 1, b: 2}, otherValue: 3}
          {id: 2, value: {a: 1, b: 3}, otherValue: 4}
        ])

      it "should correctly insert objects with common prefix", ->
        table.insert(value: {a: 1, b: 3}, otherValue: 5).then (result) ->
          table.query(id: result.insertId).then (item) ->
            item.should.eql([id: 3, value: {a: 1, b: 3}, otherValue: 5])

    describe "Streaming", ->
      it "should support streaming", ->
        rows = []
        fields = undefined
        conn.stream("SELECT 1 as v UNION SELECT 2 UNION SELECT 3").readable({highWaterMark: 1}, (stream) ->
          stream.on 'fields', (_fields) -> fields = _fields
          stream.on 'readable', ->
            $u.pause(100).then ->
              while((row=stream.read(1))?)
                rows.push(row)
        ).then ->
          fields.length.should.equal(1)
          fields[0].name.should.equal("v")
          rows.should.eql([{v: 1}, {v: 2}, {v: 3}])

    describe "Migrations", ->
      it "should invoke execute method and return an array of json object", ->
        conn.execute("SELECT 1 as v1, 2 as v2").then (results) ->
          results.should.eql([{v1: 1, v2: 2}])

      it "should describe tables", ->
        conn.execute("""
          CREATE TEMPORARY TABLE someTable(
            id int(11) NOT NULL AUTO_INCREMENT,
            stringField varchar(11) NULL,
            dateField datetime NOT NULL,
            booleanField tinyint NOT NULL DEFAULT 0,
            doubleField double NULL,
            createTime DATETIME NOT NULL,
            updateTime DATETIME NOT NULL,
            PRIMARY KEY(id)
          )
        """).then ->
          conn.describeTable("someTable").should.eql(_.omit(basicTableDefinition, 'events', 'rowFormatter'))

      it "should create a migration from one table structure to another", ->
        table1 = """
          CREATE TEMPORARY TABLE someTable1(
            id int(11) NOT NULL AUTO_INCREMENT,
            stringField varchar(11) NULL,
            dateField datetime NOT NULL,
            createTime DATETIME NOT NULL,
            doubleField double NULL,
            PRIMARY KEY(id),
            UNIQUE KEY(stringField)
          )
        """
        table2 = """
          CREATE TEMPORARY TABLE someTable2(
            id int(11) NOT NULL AUTO_INCREMENT,
            stringField varchar(11) NULL,
            dateField datetime NOT NULL,
            booleanField tinyint NOT NULL DEFAULT 0,
            doubleField double NULL,
            createTime DATETIME NOT NULL,
            updateTime DATETIME NOT NULL,
            PRIMARY KEY(id, stringField),
            UNIQUE KEY someUniqueKey(dateField),
            KEY someKey(booleanField),
            KEY(booleanField)
          )
        """
        [ conn.execute(table1)
          conn.execute(table2)
        ].then ->
          conn.createMigration("someTable1", "someTable2").then (structure, positions, extraColumns) ->
            conn.execute(structure[0]).then ->
              conn.execute(positions).then ->
                [ conn.first("SHOW CREATE TABLE someTable1").then((createTableSql) -> createTableSql['Create Table'])
                  conn.first("SHOW CREATE TABLE someTable2").then((createTableSql) -> createTableSql['Create Table'])
                ].then (createSql1, createSql2) ->
                  createSql1.replace(/someTable1/,'someTable2').should.equal(createSql2)

      it "should correctly add fields with a unique index", ->
        table1 = """
          CREATE TEMPORARY TABLE someTable1(
            id int(11) NOT NULL AUTO_INCREMENT,
            v int(11) NOT NULL,
            PRIMARY KEY(id)
          )
        """
        table2 = """
          CREATE TEMPORARY TABLE someTable2(
            id int(11) NOT NULL AUTO_INCREMENT,
            uniqueField int(11) NOT NULL,
            v int(11) NOT NULL,
            PRIMARY KEY(id),
            UNIQUE KEY uniqueField(uniqueField)
          )
        """
        [ (conn.execute(table1).then ->
            [ conn.execute("INSERT INTO someTable1(v) VALUES(1)")
              conn.execute("INSERT INTO someTable1(v) VALUES(2)")
              conn.execute("INSERT INTO someTable1(v) VALUES(3)")
            ].then ->
          )
          conn.execute(table2)
        ].then ->
          conn.createMigration("someTable1", "someTable2").then (scripts, positions, extraColumns) ->
            _.map(scripts, (script) -> conn.execute(script)).then ->
              conn.execute(positions).then ->
                [ conn.first("SHOW CREATE TABLE someTable1").then((createTableSql) -> createTableSql['Create Table'])
                  conn.first("SHOW CREATE TABLE someTable2").then((createTableSql) -> createTableSql['Create Table'])
                ].then (createSql1, createSql2) ->
                  createSql1 = createSql1.replace(/someTable1/,'someTable2')
                  createSql1 = createSql1.replace(/.AUTO_INCREMENT=\w/,'')
                  createSql1.should.equal(createSql2)

      it "should migrate table", ->
        table1sql = """
            CREATE TEMPORARY TABLE someTable(
              id int(11) NOT NULL AUTO_INCREMENT,
              PRIMARY KEY(id)
            )
          """
        table2sql = (name) -> """
            CREATE TEMPORARY TABLE #{name}(
              id int(11) NOT NULL AUTO_INCREMENT,
              v int(11) NOT NULL,
              PRIMARY KEY(id)
            )
          """
        conn.execute(table1sql).then ->
          conn.migrateTable("someTable", table2sql, false).should.equal(true).then ->
            conn.describeTable("someTable").then (tableDef) ->
              should.exist(tableDef.fields.v)
              tableDef.fields.v.should.eql(name: 'v', type: 'Integer', dbFieldName: 'v')

      it "should not migrate identical tables", ->
        tableSql = (name) -> """
            CREATE TEMPORARY TABLE #{name}(
              id int(11) NOT NULL AUTO_INCREMENT,
              v int(11) NOT NULL,
              PRIMARY KEY(id)
            )
          """
        conn.execute(tableSql("someTable")).then ->
          conn.migrateTable("someTable", tableSql, false).should.equal(false)

  describe "Connection Pool Integration Tests", ->
    pool = null
    beforeEach (done) ->
      opts = {host: 'localhost', user:'dev', password: 'pass', database: 'test'}
      ctx.register 'mysqlConnectionPool', (mysqlConnectionPoolFactory) -> mysqlConnectionPoolFactory(connectionInfo: opts)

      ctx.invoke (mysqlConnectionPool) ->
        pool = mysqlConnectionPool
        done()

    describe "Transaction Coordinator", ->
      scope = require('../src/scope')
      refConn = null
      beforeEach (done) ->
        ctx.invoke (mysqlTransactionCoordirnator) ->
          pool().then (conn) ->
            refConn = conn
            conn.execute("DROP TABLE IF EXISTS someTable2").then ->
              conn.execute("""
                CREATE TABLE someTable2(
                  id int(11) NOT NULL AUTO_INCREMENT,
                  value int(11) NOT NULL,
                  PRIMARY KEY(id)
                )
              """).then ->
                done()

      afterEach (done) ->
        refConn.execute("DROP TABLE someTable2").then ->
          done()

      it "should support returning the same connection no matter how many times it is invoked", ->
        $p.when(
          pool (c1) ->
            pool (c2) ->
              c1.should.not.equal(c2)
        ).then ->
          c = 0
          scope.run ->
            pool.getAvailable().should.equal(9)
            (ctx.mysqlTransactionCoordirnator.inTransaction ->
              $p.when(
                pool (c1) ->
                  pool (c2) ->
                    (c1==c2).should.equal(true, "Connections are not identical")
              ).then ->
                pool.getAvailable().should.equal(8)
            ).then ->
              pool.getAvailable().should.equal(9)

      it "should properly maintain and commit a transaction", ->
        scope.run ->
          (ctx.mysqlTransactionCoordirnator.inTransaction ->
            pool (conn) ->
              conn.execute("INSERT INTO someTable2(value) VALUES(1)").then ->
                refConn.execute("SELECT * FROM someTable2").should.eql([]).then ->
                  "OK"
          ).then (result) ->
            result.should.equal("OK")
            refConn.execute("SELECT * FROM someTable2").should.eql([{id: 1, value: 1}])

      it "should rollback a transaction if there is an error", ->
        scope.run ->
          (ctx.mysqlTransactionCoordirnator.inTransaction ->
            pool (conn) ->
              conn.execute("INSERT INTO someTable2(value) VALUES(1)").then ->
                $p.error("OOPS")
          ).then
            success: -> should.fail("success should not have been called")
            error: (args...) ->
              args.should.eql(["OOPS"])
              refConn.execute("SELECT * FROM someTable2").should.eql([])

      it "should properly handle noop transactions", ->
        scope.run ->
          (ctx.mysqlTransactionCoordirnator.inTransaction -> "OK").should.equal("OK")

      it "start a new scope if one doesn't exist", ->
        scope.active.should.equal(false)
        (ctx.mysqlTransactionCoordirnator.inTransaction ->
          scope.active.should.equal(true)
          "OK"
        ).should.equal("OK").then ->
          scope.active.should.equal(false)

      it "should support parallel transactions within the same scope", ->
        (scope.run ->
          [ (ctx.mysqlTransactionCoordirnator.inTransaction -> $u.pause(5).then -> "OK1")
            (ctx.mysqlTransactionCoordirnator.inTransaction -> $u.pause(5).then -> "OK2")
          ].toPromise()
        ).should.eql ["OK1", "OK2"]

      it "should not support nested transactions", ->
        ( (ctx.mysqlTransactionCoordirnator.inTransaction ->
            ctx.mysqlTransactionCoordirnator.inTransaction ->
          ).then(failure: (err) -> err.message)
        ).should.equal("Transaction already started, nested transactions are not supported!")

