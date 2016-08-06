should = require('should')
{$p, $u, di} = require('../index')

di.describe 'ApplicationState', (ctx, it) ->
  beforeEach (done) ->
    ctx.configure {
      applicationState:
        tablePrefix: 'test'
      aws:
        endpoint: "http://localhost:8000"
        region: 'us-east-1'
    }
    ctx.registerAll require('../src/aws')
    ctx.registerAll require('../src/application_state')
    ctx.invoke (applicationState) ->
      applicationState._stateTable.deleteItem({key: "/test/key1"}).then ->
        done()

  it "should store and retrieve a key", ->
    ctx.applicationState.get("/test/key1").should.not.exist().then ->
      ctx.applicationState.set("/test/key1", "value1").then ->
        ctx.applicationState.get("/test/key1").should.equal("value1")

  it "should store and remove a key", ->
    ctx.applicationState.set("/test/key1", "value1").then ->
      ctx.applicationState.get("/test/key1").should.equal("value1").then ->
        ctx.applicationState.remove("/test/key1").then ->
          ctx.applicationState.get("/test/key1").should.not.exist()

