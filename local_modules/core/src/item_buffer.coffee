{EventEmitter} = require('events')

ItemBuffer = class ItemBuffer extends EventEmitter
  constructor: (@maxSize) ->
  items: []
  emitEvents: ->
    @emit("full") if @items.length >= @maxSize
    @emit("notEmpty") if @items.length > 0
    @emit('notFull') if @items.length < @maxSize
    @emit('notHalfFull') if @items.length < @maxSize / 2
    @emit('empty') if @items.length == 0
  put: (items...) ->
    @items=@items.concat(items)
    @emitEvents()
  get: (count = 1) ->
    return [] if @items.length == 0
    dequeued = @items[...count]
    @items = @items[count..]
    @emitEvents()
    dequeued
  size: -> @items.length

exports.ItemBufferFactory = -> (maxSize) -> new ItemBuffer(maxSize)