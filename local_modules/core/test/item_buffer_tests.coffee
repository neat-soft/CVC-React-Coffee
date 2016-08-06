should = require("should")
{$p, di, expect} = require('../index')

di.describe 'ItemBuffer', (ctx, it) ->
  buffer = null
  beforeEach ->
    ctx.registerAll require('../src/item_buffer')
    ctx.registerMock 'eventMocks'
    buffer = ctx.itemBufferFactory(5)

  afterEach ->
    expect.validate(ctx.eventMocks)

  it "should put items into buffer", ->
    buffer.put('abc', 'efg', 'xyz')
    buffer.size().should.equal(3)

  it "should return correct number of items", ->
    buffer.put('abc', 'efg', 'xyz')
    buffer.get(1).should.eql(['abc'])
    buffer.get(2).should.eql(['efg', 'xyz'])
    buffer.size().should.equal(0)

  it "should emit notEmpty", ->
    buffer.on 'notEmpty', ctx.eventMocks.notEmpty = expect().andResolve()
    buffer.put('abc', 'efg', 'xyz')

  it "should emit notEmpty and notFull events", ->
    buffer.on 'notFull', ctx.eventMocks.notFull = expect().andResolve()
    buffer.put('abc', 'efg', 'xyz')

  it "should emit notHalfFull events", ->
    buffer.on 'notHalfFull', ctx.eventMocks.notHalfFull = expect().andResolve()
    buffer.put('abc', 'efg')

  it "should emit empty event when last item is removed", ->
    buffer.put('abc')
    buffer.on 'empty', ctx.eventMocks.empty = expect().andResolve()
    buffer.get()

  it "should emit full event when max size of buffer is reached", ->
    buffer.on 'full', ctx.eventMocks.full = expect().andResolve()
    buffer.put('abc', 'def', 'xyz', '123', '456')

