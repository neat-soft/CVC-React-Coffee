fs = require('fs')
_ = require('lodash')
{spawn} = require('child_process')
$p = require('./promise')
{EventEmitter} = require('events')
throttle = require('./throttle')
$u = require('./utilities')

pipeToTarget = (streamOrBuffer, target) ->
  if Buffer.isBuffer(streamOrBuffer)
    target.write(streamOrBuffer)
    target.end()
  else if streamOrBuffer.readable?
    streamOrBuffer.pipe target
  else
    stream = fs.createReadStream(streamOrBuffer)
    stream.pipe target

exports.identify = (streamOrBuffer) ->
  proc = $u.spawnBuffered 'identify', ['-']
  pipeToTarget streamOrBuffer, proc.stdin
  proc.then
    success: (stdout) ->
      attribs = stdout.toString().split(" ")
      if(attribs.length>3)
        dims = attribs[2].split('x')
        info =
          type: attribs[1]
          dimensions:
            w:parseInt(dims[0])
            h:parseInt(dims[1])
    error: (code, stdout, stderr) -> $p.error(stderr)

formats = ["JPEG", "PNG"]

exports.normalize = (streamOrBuffer, format) ->
  return $p.error("Invalid format must be one of [#{formats}]") unless format in formats
  proc = $u.spawnUnbufferedOutput "convert", "-", "-strip", "-auto-orient", "-colorspace", "sRGB" ,"#{format}:-"
  pipeToTarget streamOrBuffer, proc.stdin
  result = proc.then
    error: (code, err) ->
      $p.error("FAILED TO CONVERT IMAGE:#{code}")
  result.stdout = proc.stdout
  result

exports.resize = (streamOrBuffer, w, h, format) ->
  return $p.error("Invalid width") unless _.isNumber(w)
  return $p.error("Invalid height") unless _.isNumber(h)
  return $p.error("Invalid format must be one of [#{formats}]") unless format in formats
  cmd = ["convert", "-", "-strip", "-auto-orient", "-resize", "#{w}x#{h}", "-background", "transparent", "-compose", "Copy", "-gravity", "center", "-extent", "#{w}x#{h}", "PNG:-"]
  proc = $u.spawnUnbufferedOutput(cmd...)
  pipeToTarget streamOrBuffer, proc.stdin
  buffers = []
  errBuffers = []
  proc.stdout.on 'data', (data) -> buffers.push(data)
  proc.stderr.on 'data', (data) -> errBuffers.push data
  proc.then
    success: ->
      buffer = Buffer.concat(buffers)
    error: (code, err) ->
      $p.error("FAILED TO CONVERT IMAGE:#{code}", Buffer.concat(errBuffers).toString())
