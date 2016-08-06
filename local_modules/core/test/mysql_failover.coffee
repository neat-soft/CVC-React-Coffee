should = require('should')
{throttle, $p, $u, di} = require('../index')
_ = require('lodash')

throw new Error("Hostname is required as first argument") unless process.argv[2]?
console.log "TESTING AGAINST: ", process.argv[2]

ctx = di.context()
ctx.configure {
  mysqlConnectionPool:
    reconnectOnReadonlyError: true
    max: 10
    min: 0
    connectionInfo:
      host: process.argv[2]
      port: 3306
      user: process.argv[3]
      password: process.argv[4]
}
ctx.registerAll require('../src/mysql')
ctx.register '$u', $u
ctx.register '$p', $p

ctx.invoke (mysqlConnectionPool) ->
  init = ->
    mysqlConnectionPool (conn) ->
      conn.execute("DROP DATABASE IF EXISTS mysql_failover_test").then ->
        conn.execute("CREATE DATABASE mysql_failover_test").then ->
          conn.execute("CREATE TABLE mysql_failover_test.test_table(value int(11) not null)").then ->
            console.log "STRUCTURE CREATED"

  runTest = ->
    console.log "STARTING TEST"
    counter = 0
    th = throttle(5)
    doIt = ->
      th ->
        mysqlConnectionPool (conn) ->
          console.log "BAD INSTANCE" if conn.shouldNotBeUsed
          counter++
          console.log counter, mysqlConnectionPool.getStats() if counter % 100 == 0
          value = 1
          conn.execute("INSERT INTO mysql_failover_test.test_table(value) VALUE(1)").then ->
            conn.execute("SELECT value FROM mysql_failover_test.test_table").then ->
              $p.resolved()

    failures = 0
    _.map [1..10], ->
      mysqlConnectionPool ->
        $u.pause(1000)
    (_.map [1..2000], ->
      doIt().then
        success: ->
        error: (err) -> console.log("ERRORS: #{failures}", err) if (failures++) % 50 == 0
        failure: (err) -> console.log "FAILURE: ", err
    ).then ->
      console.log "DONE WTIH #{failures} FAILURES"
      mysqlConnectionPool.destroyAllIdle()
      console.log "CLEANEDUP", mysqlConnectionPool.getStats()

  init().then(runTest)
