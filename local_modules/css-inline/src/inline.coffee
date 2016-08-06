Styliner = require('styliner')
styliner = new Styliner(__dirname)
{spawn} = require('child_process')

module.exports = (html, cb) ->
  extension = __filename.match(/.*\.([^.]*)$/)[1]
  if extension == 'coffee'
    exec = 'coffee'
  else
    exec = 'node'
  inline = spawn(exec, [__filename], {cwd: __dirname})
  buffer = ""
  errBuffer = ""
  inline.stdout.on 'data', (data) -> buffer+=data.toString()
  inline.stderr.on 'data', (data) -> errBuffer+=data
  inline.on 'close', (code) ->
    return cb(new Error(errBuffer)) if code != 0
    cb(null, buffer)
  inline.stdin.end(html)

if require.main == module
  html = ""
  process.stdin.on 'readable', (chunk) ->
    chunk = process.stdin.read();
    if chunk != null
      html += chunk.toString()

  process.stdin.on 'end', ->
    styliner.processHTML(html).then (html2) ->
      process.stdout.end(html2)